import { AppState, type AppStateStatus } from 'react-native';
import { PollOutcome } from './generated/coproduct_ffi_uniffi';

// A stale provider polls at this multiple of the normal interval, mirroring
// the core's stale_retry_interval and HostTimer.swift's backoffMultiplier.
const BACKOFF_MULTIPLIER = 5;

// The delay in seconds before the next poll for a given outcome. `null` stops
// polling. A 429 honors the server's retry-after but never polls faster than
// the normal interval. Retrying stays at normal cadence (the core's own short
// recovery window); only a stale provider backs off.
export function nextDelay(
  outcome: PollOutcome,
  intervalSecs: number
): number | null {
  if (PollOutcome.RateLimited.instanceOf(outcome)) {
    return Math.max(Number(outcome.inner.retryAfterSecs), intervalSecs);
  }
  if (PollOutcome.Stale.instanceOf(outcome)) {
    return intervalSecs * BACKOFF_MULTIPLIER;
  }
  if (PollOutcome.Fatal.instanceOf(outcome)) {
    return null;
  }
  return intervalSecs;
}

// Whether an outcome opens a back-off window a foreground event must wait
// out rather than bypass. Retrying is normal cadence, so a foreground
// refreshes during it.
export function isBackoff(outcome: PollOutcome): boolean {
  return (
    PollOutcome.RateLimited.instanceOf(outcome) ||
    PollOutcome.Stale.instanceOf(outcome)
  );
}

type HostTimerOptions = {
  intervalSecs: number;
  pollOnForeground: boolean;
  poll: () => Promise<PollOutcome>;
};

// React Native polling trigger, porting HostTimer.swift's state machine: a
// self-rescheduling timeout plus an optional AppState foreground listener.
// Each poll's outcome decides the next delay (see nextDelay/isBackoff above),
// so a 429 retry-after and a stale back-off are honored. The foreground fast
// path refreshes during normal cadence but waits out an active back-off.
export class HostTimer {
  private readonly intervalSecs: number;
  private readonly pollOnForeground: boolean;
  private readonly poll: () => Promise<PollOutcome>;

  private timeoutId: ReturnType<typeof setTimeout> | null = null;
  private appStateSubscription: { remove(): void } | null = null;
  private stopped = false;
  private pollInFlight = false;
  // Earliest time a foreground event may trigger an off-schedule poll. In the
  // past during normal cadence (foreground always refreshes), in the future
  // while backing off (foreground must wait out the window).
  private earliestForegroundPollAt = 0;

  constructor(options: HostTimerOptions) {
    this.intervalSecs = options.intervalSecs;
    this.pollOnForeground = options.pollOnForeground;
    this.poll = options.poll;
  }

  start(): void {
    if (this.stopped || this.timeoutId !== null) return;
    this.scheduleAfter(0);

    if (this.pollOnForeground) {
      this.appStateSubscription = AppState.addEventListener(
        'change',
        (nextState: AppStateStatus) => {
          if (nextState === 'active') this.foregroundFired();
        }
      );
    }
  }

  stop(): void {
    this.stopped = true;
    if (this.timeoutId !== null) {
      clearTimeout(this.timeoutId);
      this.timeoutId = null;
    }
    this.appStateSubscription?.remove();
    this.appStateSubscription = null;
  }

  private scheduleAfter(delaySecs: number): void {
    if (this.timeoutId !== null) {
      clearTimeout(this.timeoutId);
    }
    this.timeoutId = setTimeout(
      () => this.triggerPoll(),
      Math.max(delaySecs, 0) * 1000
    );
  }

  private foregroundFired(): void {
    const allowed =
      !this.stopped &&
      !this.pollInFlight &&
      Date.now() >= this.earliestForegroundPollAt;
    if (allowed) this.triggerPoll();
  }

  private triggerPoll(): void {
    if (this.stopped || this.pollInFlight) return;
    this.pollInFlight = true;
    this.poll().then(
      (outcome) => this.rescheduleAfterPoll(outcome),
      (error) => {
        this.pollInFlight = false;
        console.error('[coproduct] host timer poll failed', error);
      }
    );
  }

  private rescheduleAfterPoll(outcome: PollOutcome): void {
    this.pollInFlight = false;
    if (this.stopped) return;
    const delay = nextDelay(outcome, this.intervalSecs);
    if (delay === null) {
      this.stop();
      return;
    }
    this.earliestForegroundPollAt = isBackoff(outcome)
      ? Date.now() + delay * 1000
      : Date.now();
    this.scheduleAfter(delay);
  }
}
