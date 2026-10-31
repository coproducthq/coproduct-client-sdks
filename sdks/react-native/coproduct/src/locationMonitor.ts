import { AppState, type AppStateStatus } from 'react-native';
import { acquireFix, type LocationFix } from './locationSource';

/** The interval used when the host enables location without naming one. */
export const DEFAULT_INTERVAL_MS = 120_000;

/** The smallest repeating interval, to keep an over-eager caller from draining the battery. */
export const MIN_INTERVAL_MS = 30_000;

/** Clamp a requested interval: `0` disables the loop (one fix only), anything else is floored. */
export function clampIntervalMs(ms: number): number {
  if (ms <= 0) return 0;
  return Math.max(ms, MIN_INTERVAL_MS);
}

type LocationMonitorOptions = {
  onFix: (fix: LocationFix) => void;
};

/**
 * Drives foreground location refresh. Porting the HostTimer shape (a
 * self-rescheduling timeout plus an AppState listener), but foreground-ONLY: the
 * loop pauses when the app backgrounds and resumes, with a fresh fix, when it
 * returns. Each tick reads one fix and hands it to `onFix`, which publishes
 * `device_location` so a geo-fence re-evaluates. The SDK holds no continuous OS
 * location subscription; it reads a single fix per tick on the host's cadence.
 */
export class LocationMonitor {
  private readonly onFix: (fix: LocationFix) => void;
  private intervalMs = DEFAULT_INTERVAL_MS;
  private enabled = false;
  private paused = false;
  private stopped = false;
  private acquiring = false;
  private timeoutId: ReturnType<typeof setTimeout> | null = null;
  private appStateSubscription: { remove(): void } | null = null;

  constructor(options: LocationMonitorOptions) {
    this.onFix = options.onFix;
  }

  /**
   * Turn location on: take a first fix now and, unless the interval is `0`, start
   * the repeating foreground loop. Idempotent, so a later interval change does
   * not restart the first fix.
   */
  enable(): void {
    if (this.stopped || this.enabled) return;
    this.enabled = true;
    this.paused = false;
    this.appStateSubscription = AppState.addEventListener(
      'change',
      (next: AppStateStatus) => {
        if (next === 'active') this.resume();
        else this.pause();
      }
    );
    void this.tick();
  }

  /** Enable (if needed) and set the repeating interval. `0` keeps only the one-shot fix. */
  setIntervalMs(ms: number): void {
    this.intervalMs = clampIntervalMs(ms);
    if (!this.enabled) {
      this.enable();
      return;
    }
    this.schedule();
  }

  /** On-demand fix, ignored until the host has enabled location. */
  async refreshNow(): Promise<void> {
    if (!this.enabled || this.stopped) return;
    await this.tick();
  }

  stop(): void {
    this.stopped = true;
    this.enabled = false;
    this.clearTimer();
    this.appStateSubscription?.remove();
    this.appStateSubscription = null;
  }

  private pause(): void {
    this.paused = true;
    this.clearTimer();
  }

  private resume(): void {
    if (!this.enabled || this.stopped || !this.paused) return;
    this.paused = false;
    void this.tick();
  }

  private clearTimer(): void {
    if (this.timeoutId !== null) {
      clearTimeout(this.timeoutId);
      this.timeoutId = null;
    }
  }

  private schedule(): void {
    this.clearTimer();
    if (this.stopped || this.paused || !this.enabled || this.intervalMs <= 0) return;
    this.timeoutId = setTimeout(() => void this.tick(), this.intervalMs);
  }

  private async tick(): Promise<void> {
    if (this.stopped || this.acquiring) return;
    this.acquiring = true;
    try {
      const fix = await acquireFix();
      if (fix !== null && !this.stopped) this.onFix(fix);
    } finally {
      this.acquiring = false;
      this.schedule();
    }
  }
}
