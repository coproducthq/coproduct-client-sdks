export type Cancellable = {
  cancel(): void;
};

export type ObservationDecoded<TValue> =
  | { kind: 'value'; value: TValue | undefined }
  | { kind: 'closed' };

type DrainableObservation<TDelivery, TValue> = {
  seed(): TValue | undefined;
  pollNext(): Promise<TDelivery>;
  cancel(): void;
  uniffiDestroy?(): void;
};

// Generic drain loop backing every observeX method. The core hands each
// subscription its full current state through seed(), then pollNext() awaits
// a Rust-owned mailbox — no thread is blocked while it is pending, so a
// handler that re-enters the SDK cannot deadlock delivery (see AGENTS.md's
// "ordered observation drain" architecture rule).
export function observeDrain<TDelivery, TValue>(
  observation: DrainableObservation<TDelivery, TValue>,
  defaultValue: TValue,
  decode: (delivery: TDelivery) => ObservationDecoded<TValue>,
  onChange: (value: TValue) => void | Promise<void>
): Cancellable {
  let cancelled = false;

  const deliver = async (value: TValue): Promise<void> => {
    try {
      await onChange(value);
    } catch (error) {
      console.error('[coproduct] flag observation handler failed', error);
    }
  };

  const drain = async (): Promise<void> => {
    // A cancel that lands in the same tick as the call that created this
    // observation (a synchronous cancel() right after, or a React 18
    // StrictMode double-invoke) runs before this scheduled microtask does.
    if (cancelled) return;

    let seedValue: TValue;
    try {
      seedValue = observation.seed() ?? defaultValue;
    } catch (error) {
      console.error('[coproduct] flag observation drain ended', error);
      return;
    }
    await deliver(seedValue);

    while (!cancelled) {
      let delivery: TDelivery;
      try {
        delivery = await observation.pollNext();
      } catch (error) {
        console.error('[coproduct] flag observation drain ended', error);
        return;
      }
      const decoded = decode(delivery);
      if (decoded.kind === 'closed') return;
      await deliver(decoded.value ?? defaultValue);
    }
  };

  // Scheduled rather than started inline, so the handler never fires before
  // the caller receives the returned Cancellable (an async function runs
  // synchronously up to its first await).
  Promise.resolve().then(() => {
    // eslint-disable-next-line no-void
    void drain();
  });

  return {
    cancel(): void {
      if (cancelled) return;
      cancelled = true;
      observation.cancel();
      observation.uniffiDestroy?.();
    },
  };
}
