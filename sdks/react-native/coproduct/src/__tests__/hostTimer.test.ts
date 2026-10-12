import { AppState, type AppStateStatus } from 'react-native';
import { nextDelay, isBackoff, HostTimer } from '../hostTimer';
import { PollOutcome } from '../generated/coproduct_ffi_uniffi';

// The brief's `flushMicrotasks` helper (`new Promise((resolve) => setImmediate(resolve))`) hangs
// every HostTimer test under `jest.useFakeTimers()`: Jest's modern (sinon-based) fake timers fake
// `setImmediate` itself, so that promise never settles until fake time is advanced — but nothing
// in these tests calls `jest.useRealTimers()` first, so the 5s test timeout always wins. Verified
// with a throwaway probe test: `setImmediate` callbacks only fire after `jest.runAllTimers()` (or
// an async advance). `jest.advanceTimersByTimeAsync` is Jest's built-in replacement for exactly
// this situation — it advances fake time AND drains the real microtask queue between each tick, so
// pending `poll().then(...)` chains resolve before the assertion runs. We use `advanceTimersByTimeAsync(0)`
// wherever the original just needed a microtask flush with no time passing.
async function flushMicrotasks() {
  await jest.advanceTimersByTimeAsync(0);
}

// The react-native jest preset's AppState mock (node_modules/react-native/jest/mocks/AppState.js)
// is a plain `{ addEventListener: jest.fn(() => ({ remove: jest.fn() })), ... }` — it does not
// record or expose the registered listener, and it has no `.emit` method to drive a 'change'
// event the way a real EventEmitter would. So instead of `AppState.emit?.(...)` (which would
// silently no-op against this mock), we reach into `addEventListener`'s mock.calls to grab the
// listener HostTimer registered and invoke it directly. This preserves the test's intent —
// simulate the OS notifying the app it came to the foreground — against the mock that's actually
// installed.
function fireAppStateChange(nextState: AppStateStatus) {
  const addEventListener = AppState.addEventListener as jest.Mock;
  const changeCalls = addEventListener.mock.calls.filter(
    ([eventName]) => eventName === 'change'
  );
  const [, listener] = changeCalls[changeCalls.length - 1] ?? [];
  listener?.(nextState);
}

describe('nextDelay', () => {
  it('uses the normal interval for updated, notModified, retrying, and dedupedSkipped', () => {
    expect(nextDelay(PollOutcome.Updated.new(), 60)).toBe(60);
    expect(nextDelay(PollOutcome.NotModified.new(), 60)).toBe(60);
    expect(nextDelay(PollOutcome.Retrying.new(), 60)).toBe(60);
    expect(nextDelay(PollOutcome.DedupedSkipped.new(), 60)).toBe(60);
  });

  it('honors retry-after but never polls faster than the normal interval', () => {
    expect(
      nextDelay(PollOutcome.RateLimited.new({ retryAfterSecs: 120n }), 60)
    ).toBe(120);
    expect(
      nextDelay(PollOutcome.RateLimited.new({ retryAfterSecs: 10n }), 60)
    ).toBe(60);
  });

  it('backs off to 5x the interval when stale', () => {
    expect(nextDelay(PollOutcome.Stale.new(), 60)).toBe(300);
  });

  it('returns null for fatal, stopping the timer', () => {
    expect(nextDelay(PollOutcome.Fatal.new(), 60)).toBeNull();
  });
});

describe('isBackoff', () => {
  it('is true only for rateLimited and stale', () => {
    expect(
      isBackoff(PollOutcome.RateLimited.new({ retryAfterSecs: 10n }))
    ).toBe(true);
    expect(isBackoff(PollOutcome.Stale.new())).toBe(true);
    expect(isBackoff(PollOutcome.Updated.new())).toBe(false);
    expect(isBackoff(PollOutcome.NotModified.new())).toBe(false);
    expect(isBackoff(PollOutcome.Retrying.new())).toBe(false);
    expect(isBackoff(PollOutcome.DedupedSkipped.new())).toBe(false);
    expect(isBackoff(PollOutcome.Fatal.new())).toBe(false);
  });
});

describe('HostTimer', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    // Without this, fireAppStateChange's search through addEventListener's mock.calls would
    // reach back into listeners registered by earlier tests' (already-stopped) HostTimer
    // instances, since nothing else resets this shared mock between tests.
    (AppState.addEventListener as jest.Mock).mockClear();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('polls immediately on start', async () => {
    const poll = jest.fn().mockResolvedValue(PollOutcome.Updated.new());
    const timer = new HostTimer({
      intervalSecs: 60,
      pollOnForeground: true,
      poll,
    });

    timer.start();
    await flushMicrotasks();

    expect(poll).toHaveBeenCalledTimes(1);
    timer.stop();
  });

  it('reschedules at the normal interval after an updated outcome', async () => {
    const poll = jest.fn().mockResolvedValue(PollOutcome.Updated.new());
    const timer = new HostTimer({
      intervalSecs: 60,
      pollOnForeground: true,
      poll,
    });

    timer.start();
    await flushMicrotasks();
    expect(poll).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(59_000);
    expect(poll).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(1_000);
    expect(poll).toHaveBeenCalledTimes(2);

    timer.stop();
  });

  it('stops permanently after a fatal outcome', async () => {
    const poll = jest.fn().mockResolvedValue(PollOutcome.Fatal.new());
    const timer = new HostTimer({
      intervalSecs: 60,
      pollOnForeground: true,
      poll,
    });

    timer.start();
    await flushMicrotasks();
    expect(poll).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(300_000);
    expect(poll).toHaveBeenCalledTimes(1);

    timer.stop();
  });

  it('does not poll again after stop', async () => {
    const poll = jest.fn().mockResolvedValue(PollOutcome.Updated.new());
    const timer = new HostTimer({
      intervalSecs: 60,
      pollOnForeground: true,
      poll,
    });

    timer.start();
    await flushMicrotasks();
    timer.stop();

    await jest.advanceTimersByTimeAsync(120_000);
    expect(poll).toHaveBeenCalledTimes(1);
  });

  it('re-polls on foreground during normal cadence', async () => {
    const poll = jest.fn().mockResolvedValue(PollOutcome.Updated.new());
    const timer = new HostTimer({
      intervalSecs: 60,
      pollOnForeground: true,
      poll,
    });

    timer.start();
    await flushMicrotasks();
    expect(poll).toHaveBeenCalledTimes(1);

    fireAppStateChange('active');
    await flushMicrotasks();
    expect(poll).toHaveBeenCalledTimes(2);

    timer.stop();
  });

  it('does not re-poll on foreground when pollOnForeground is false', async () => {
    const poll = jest.fn().mockResolvedValue(PollOutcome.Updated.new());
    const timer = new HostTimer({
      intervalSecs: 60,
      pollOnForeground: false,
      poll,
    });

    timer.start();
    await flushMicrotasks();
    expect(poll).toHaveBeenCalledTimes(1);

    fireAppStateChange('active');
    await flushMicrotasks();
    expect(poll).toHaveBeenCalledTimes(1);

    timer.stop();
  });
});
