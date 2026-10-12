import { observeDrain, type ObservationDecoded } from '../observation';

type FakeDelivery = { kind: 'value'; value: number } | { kind: 'closed' };

function decode(delivery: FakeDelivery): ObservationDecoded<number> {
  return delivery.kind === 'value'
    ? { kind: 'value', value: delivery.value }
    : { kind: 'closed' };
}

class FakeObservation {
  private queue: FakeDelivery[] = [];
  private resolvers: Array<(delivery: FakeDelivery) => void> = [];
  cancelled = false;
  destroyed = false;

  constructor(private seedValue: number | undefined) {}

  seed(): number | undefined {
    return this.seedValue;
  }

  push(delivery: FakeDelivery): void {
    const resolve = this.resolvers.shift();
    if (resolve) {
      resolve(delivery);
    } else {
      this.queue.push(delivery);
    }
  }

  pollNext(): Promise<FakeDelivery> {
    const next = this.queue.shift();
    if (next) return Promise.resolve(next);
    return new Promise((resolve) => this.resolvers.push(resolve));
  }

  cancel(): void {
    this.cancelled = true;
    this.push({ kind: 'closed' });
  }

  uniffiDestroy(): void {
    this.destroyed = true;
  }
}

function flushMicrotasks() {
  return new Promise((resolve) => setImmediate(resolve));
}

describe('observeDrain', () => {
  it('delivers the seed value first', async () => {
    const observation = new FakeObservation(5);
    const values: number[] = [];

    observeDrain(observation, 0, decode, (value) => {
      values.push(value);
    });
    await flushMicrotasks();

    expect(values).toEqual([5]);
  });

  it('falls back to the default value when seed is undefined', async () => {
    const observation = new FakeObservation(undefined);
    const values: number[] = [];

    observeDrain(observation, 99, decode, (value) => {
      values.push(value);
    });
    await flushMicrotasks();

    expect(values).toEqual([99]);
  });

  it('delivers later values in order', async () => {
    const observation = new FakeObservation(1);
    const values: number[] = [];

    observeDrain(observation, 0, decode, (value) => {
      values.push(value);
    });
    await flushMicrotasks();

    observation.push({ kind: 'value', value: 2 });
    await flushMicrotasks();
    observation.push({ kind: 'value', value: 3 });
    await flushMicrotasks();

    expect(values).toEqual([1, 2, 3]);
  });

  it('stops delivering once cancelled, and destroys the native handle', async () => {
    const observation = new FakeObservation(1);
    const values: number[] = [];

    const cancellable = observeDrain(observation, 0, decode, (value) => {
      values.push(value);
    });
    await flushMicrotasks();

    cancellable.cancel();
    await flushMicrotasks();

    expect(observation.cancelled).toBe(true);
    expect(observation.destroyed).toBe(true);

    observation.push({ kind: 'value', value: 2 });
    await flushMicrotasks();
    expect(values).toEqual([1]);
  });

  it('cancel is idempotent', async () => {
    const observation = new FakeObservation(1);
    const cancellable = observeDrain(observation, 0, decode, () => {});
    await flushMicrotasks();

    cancellable.cancel();
    expect(() => cancellable.cancel()).not.toThrow();
  });

  it('a handler that throws does not stop later delivery', async () => {
    const observation = new FakeObservation(1);
    const values: number[] = [];
    const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {});

    observeDrain(observation, 0, decode, (value) => {
      values.push(value);
      if (value === 1) throw new Error('boom');
    });
    await flushMicrotasks();

    observation.push({ kind: 'value', value: 2 });
    await flushMicrotasks();

    expect(values).toEqual([1, 2]);
    expect(errorSpy).toHaveBeenCalled();
    errorSpy.mockRestore();
  });
});
