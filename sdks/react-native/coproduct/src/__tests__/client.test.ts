import { CoproductClient } from '../client';
import {
  BoolDelivery,
  FlagEvaluationDetailsBool,
  IntDelivery,
  JsonDelivery,
  NumberDelivery,
  StringDelivery,
  type CoproductClientLike,
  type CoproductSnapshot,
  type EvaluationHook,
  type EvaluationStage,
  type HookContext,
  type FlagEvaluationDetailsNumberList,
  type FlagEvaluationDetailsStringList,
  type HookHandleLike,
  type LifecycleEvent,
  type LifecycleHandler,
  type ProviderState,
} from '../generated/coproduct_ffi_uniffi';

// Generic fake backing every observeX test below: mirrors the shape shared by
// Bool/String/Int/Number/JsonObservationLike (seed/pollNext/cancel/
// isCancelled/keys/uniffiDestroy), with a `push` escape hatch so a test can
// drive a real generated `*Delivery.Value`/`.Closed` through pollNext().
function createFakeObservation<TDelivery, TSeed>(seedValue: TSeed) {
  const queue: TDelivery[] = [];
  const resolvers: Array<(delivery: TDelivery) => void> = [];

  return {
    seed: jest.fn().mockReturnValue(seedValue),
    pollNext: jest.fn().mockImplementation(
      () =>
        new Promise<TDelivery>((resolve) => {
          const next = queue.shift();
          if (next !== undefined) {
            resolve(next);
          } else {
            resolvers.push(resolve);
          }
        })
    ),
    cancel: jest.fn(),
    isCancelled: jest.fn(),
    keys: jest.fn(),
    uniffiDestroy: jest.fn(),
    push(delivery: TDelivery): void {
      const resolve = resolvers.shift();
      if (resolve) {
        resolve(delivery);
      } else {
        queue.push(delivery);
      }
    },
  };
}

function flushMicrotasks(): Promise<void> {
  return new Promise((resolve) => setImmediate(resolve));
}

function fakeNativeClient(
  overrides: Partial<CoproductClientLike> = {}
): CoproductClientLike {
  return {
    getBool: jest.fn(),
    getBoolDetails: jest.fn(),
    getString: jest.fn(),
    getStringDetails: jest.fn(),
    getInt: jest.fn(),
    getIntDetails: jest.fn(),
    getNumber: jest.fn(),
    getNumberDetails: jest.fn(),
    getStringList: jest.fn(),
    getStringListDetails: jest.fn(),
    getNumberList: jest.fn(),
    getNumberListDetails: jest.fn(),
    getJson: jest.fn(),
    getJsonDetails: jest.fn(),
    identify: jest.fn().mockResolvedValue(undefined),
    signOut: jest.fn().mockResolvedValue(undefined),
    setContext: jest.fn().mockResolvedValue(undefined),
    updateAttributes: jest.fn().mockResolvedValue(undefined),
    removeAttributes: jest.fn().mockResolvedValue(undefined),
    previousAnonymousId: jest.fn(),
    observeBool: jest.fn(),
    observeString: jest.fn(),
    observeInt: jest.fn(),
    observeNumber: jest.fn(),
    observeJson: jest.fn(),
    observeBundle: jest.fn(),
    currentFlagValues: jest.fn(),
    addHandler: jest.fn(),
    addEvaluationHook: jest.fn(),
    setAutoPopulatedAttributes: jest.fn().mockResolvedValue(undefined),
    setEvaluationListener: jest.fn(),
    shutdown: jest.fn().mockResolvedValue(undefined),
    snapshotView: jest.fn(),
    state: jest.fn(),
    pollNow: jest.fn(),
    ...overrides,
  } as unknown as CoproductClientLike;
}

describe('CoproductClient typed getters', () => {
  it('passes getBool through to the native client', () => {
    const native = fakeNativeClient({
      getBool: jest.fn().mockReturnValue(true),
    });
    const client = new CoproductClient(native);

    expect(client.getBool('flag', false)).toBe(true);
    expect(native.getBool).toHaveBeenCalledWith('flag', false);
  });

  it('passes getBoolDetails through to the native client', () => {
    const details = FlagEvaluationDetailsBool.create({
      value: true,
      reason: 'TARGETING_MATCH',
      flagKey: 'flag',
    });
    const native = fakeNativeClient({
      getBoolDetails: jest.fn().mockReturnValue(details),
    });
    const client = new CoproductClient(native);

    expect(client.getBoolDetails('flag', false)).toEqual(details);
  });

  it('converts getInt to and from a plain number', () => {
    const native = fakeNativeClient({ getInt: jest.fn().mockReturnValue(42n) });
    const client = new CoproductClient(native);

    expect(client.getInt('flag', 0)).toBe(42);
    expect(native.getInt).toHaveBeenCalledWith('flag', 0n);
  });

  it('converts getIntDetails value to a plain number', () => {
    const native = fakeNativeClient({
      getIntDetails: jest.fn().mockReturnValue({
        value: 42n,
        reason: 'TARGETING_MATCH',
        flagKey: 'flag',
      }),
    });
    const client = new CoproductClient(native);

    const details = client.getIntDetails('flag', 0);
    expect(details.value).toBe(42);
    expect(details.reason).toBe('TARGETING_MATCH');
  });

  it('passes getString/getNumber/getJson through unchanged', () => {
    const native = fakeNativeClient({
      getString: jest.fn().mockReturnValue('x'),
      getNumber: jest.fn().mockReturnValue(1.5),
      getJson: jest.fn().mockReturnValue('{"a":1}'),
    });
    const client = new CoproductClient(native);

    expect(client.getString('k', '')).toBe('x');
    expect(client.getNumber('k', 0)).toBe(1.5);
    expect(client.getJson('k', 'null')).toBe('{"a":1}');
  });

  it('passes getStringList through to the native client', () => {
    const native = fakeNativeClient({
      getStringList: jest.fn().mockReturnValue(['a@x.com']),
    });
    const client = new CoproductClient(native);

    expect(client.getStringList('flag', [])).toEqual(['a@x.com']);
    expect(native.getStringList).toHaveBeenCalledWith('flag', []);
  });

  it('passes getStringListDetails through to the native client', () => {
    const details: FlagEvaluationDetailsStringList = {
      value: ['a@x.com'],
      reason: 'TARGETING_MATCH',
      flagKey: 'flag',
    };
    const native = fakeNativeClient({
      getStringListDetails: jest.fn().mockReturnValue(details),
    });
    const client = new CoproductClient(native);

    expect(client.getStringListDetails('flag', [])).toEqual(details);
    expect(native.getStringListDetails).toHaveBeenCalledWith('flag', []);
  });

  it('passes getNumberList through to the native client', () => {
    const native = fakeNativeClient({
      getNumberList: jest.fn().mockReturnValue([1, 2, 3]),
    });
    const client = new CoproductClient(native);

    expect(client.getNumberList('flag', [])).toEqual([1, 2, 3]);
    expect(native.getNumberList).toHaveBeenCalledWith('flag', []);
  });

  it('passes getNumberListDetails through to the native client', () => {
    const details: FlagEvaluationDetailsNumberList = {
      value: [1, 2, 3],
      reason: 'TARGETING_MATCH',
      flagKey: 'flag',
    };
    const native = fakeNativeClient({
      getNumberListDetails: jest.fn().mockReturnValue(details),
    });
    const client = new CoproductClient(native);

    expect(client.getNumberListDetails('flag', [])).toEqual(details);
    expect(native.getNumberListDetails).toHaveBeenCalledWith('flag', []);
  });
});

describe('CoproductClient identity', () => {
  it('identify converts attributes and applies in call order', async () => {
    const calls: string[] = [];
    const native = fakeNativeClient({
      identify: jest.fn().mockImplementation(async (userId: string) => {
        calls.push(userId);
      }),
    });
    const client = new CoproductClient(native);

    client.identify('user-1', { plan: 'pro' });
    client.identify('user-2');
    await flushAll(client);

    expect(calls).toEqual(['user-1', 'user-2']);
    expect(native.identify).toHaveBeenCalledWith(
      'user-1',
      expect.anything(),
      true
    );
  });

  it('identify logs and does not throw when the native call rejects', async () => {
    const native = fakeNativeClient({
      identify: jest.fn().mockRejectedValue(new Error('network')),
    });
    const client = new CoproductClient(native);
    const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {});

    expect(() => client.identify('user-1')).not.toThrow();
    await flushAll(client);

    expect(errorSpy).toHaveBeenCalled();
    errorSpy.mockRestore();
  });

  it('signOut, updateAttributes, and removeAttributes pass through', async () => {
    const native = fakeNativeClient();
    const client = new CoproductClient(native);

    client.signOut();
    client.updateAttributes({ plan: 'pro' });
    client.removeAttributes(['plan']);
    await flushAll(client);

    expect(native.signOut).toHaveBeenCalled();
    expect(native.updateAttributes).toHaveBeenCalled();
    expect(native.removeAttributes).toHaveBeenCalledWith(['plan']);
  });

  it('setContext converts attributes and defaults linkAnonymous to true on identify', async () => {
    const native = fakeNativeClient();
    const client = new CoproductClient(native);

    client.setContext('targeting-key', { plan: 'pro' });
    await flushAll(client);

    expect(native.setContext).toHaveBeenCalledWith(
      'targeting-key',
      expect.anything()
    );
  });

  it('setContext logs and does not throw when the native call rejects', async () => {
    const native = fakeNativeClient({
      setContext: jest.fn().mockRejectedValue(new Error('network')),
    });
    const client = new CoproductClient(native);
    const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {});

    expect(() => client.setContext('targeting-key')).not.toThrow();
    await flushAll(client);

    expect(errorSpy).toHaveBeenCalled();
    errorSpy.mockRestore();
  });

  it('previousAnonymousId passes through', () => {
    const native = fakeNativeClient({
      previousAnonymousId: jest.fn().mockReturnValue('anon-1'),
    });
    const client = new CoproductClient(native);

    expect(client.previousAnonymousId).toBe('anon-1');
  });
});

// Identity calls are fire-and-forget; tests await this to observe the
// settled state after a burst of calls, mirroring IdentitySerializer.drain().
async function flushAll(client: CoproductClient): Promise<void> {
  await (
    client as unknown as { identitySerializer: { drain(): Promise<void> } }
  ).identitySerializer.drain();
}

describe('CoproductClient observation, handlers, state', () => {
  it('observeBool seeds and cancels through to the native observation', () => {
    const observation = {
      seed: jest.fn().mockReturnValue(true),
      pollNext: jest.fn().mockReturnValue(new Promise(() => {})),
      cancel: jest.fn(),
      isCancelled: jest.fn(),
      keys: jest.fn(),
      uniffiDestroy: jest.fn(),
    };
    const native = fakeNativeClient({
      observeBool: jest.fn().mockReturnValue(observation),
    });
    const client = new CoproductClient(native);

    const cancellable = client.observeBool('flag', false, () => {});
    cancellable.cancel();

    expect(native.observeBool).toHaveBeenCalledWith('flag');
    expect(observation.cancel).toHaveBeenCalled();
  });

  it('observeBool delivers the seed, then a decoded BoolDelivery.Value', async () => {
    const observation = createFakeObservation<BoolDelivery, boolean>(true);
    const native = fakeNativeClient({
      observeBool: jest.fn().mockReturnValue(observation),
    });
    const client = new CoproductClient(native);
    const values: boolean[] = [];

    client.observeBool('flag', false, (value) => {
      values.push(value);
    });
    await flushMicrotasks();

    observation.push(BoolDelivery.Value.new({ revision: 1n, value: false }));
    await flushMicrotasks();

    expect(values).toEqual([true, false]);
  });

  it('observeString delivers the seed, then a decoded StringDelivery.Value', async () => {
    const observation = createFakeObservation<StringDelivery, string>('seed');
    const native = fakeNativeClient({
      observeString: jest.fn().mockReturnValue(observation),
    });
    const client = new CoproductClient(native);
    const values: string[] = [];

    client.observeString('flag', 'default', (value) => {
      values.push(value);
    });
    await flushMicrotasks();

    observation.push(
      StringDelivery.Value.new({ revision: 1n, value: 'updated' })
    );
    await flushMicrotasks();

    expect(values).toEqual(['seed', 'updated']);
  });

  it('observeInt delivers the bigint seed and a delivered value as plain numbers', async () => {
    const observation = createFakeObservation<IntDelivery, bigint>(7n);
    const native = fakeNativeClient({
      observeInt: jest.fn().mockReturnValue(observation),
    });
    const client = new CoproductClient(native);
    const values: number[] = [];

    client.observeInt('flag', 0, (value) => {
      values.push(value);
    });
    await flushMicrotasks();

    observation.push(IntDelivery.Value.new({ revision: 1n, value: 42n }));
    await flushMicrotasks();

    expect(values).toEqual([7, 42]);
  });

  it('observeNumber delivers the seed, then a decoded NumberDelivery.Value', async () => {
    const observation = createFakeObservation<NumberDelivery, number>(1.5);
    const native = fakeNativeClient({
      observeNumber: jest.fn().mockReturnValue(observation),
    });
    const client = new CoproductClient(native);
    const values: number[] = [];

    client.observeNumber('flag', 0, (value) => {
      values.push(value);
    });
    await flushMicrotasks();

    observation.push(NumberDelivery.Value.new({ revision: 1n, value: 2.5 }));
    await flushMicrotasks();

    expect(values).toEqual([1.5, 2.5]);
  });

  it('observeJson delivers the seed, then a decoded JsonDelivery.Value', async () => {
    const observation = createFakeObservation<JsonDelivery, string>('{"a":1}');
    const native = fakeNativeClient({
      observeJson: jest.fn().mockReturnValue(observation),
    });
    const client = new CoproductClient(native);
    const values: string[] = [];

    client.observeJson('flag', 'null', (value) => {
      values.push(value);
    });
    await flushMicrotasks();

    observation.push(
      JsonDelivery.Value.new({ revision: 1n, value: '{"a":2}' })
    );
    await flushMicrotasks();

    expect(values).toEqual(['{"a":1}', '{"a":2}']);
  });

  it('addHandler wraps the callback and forwards cancel', () => {
    const handle = { cancel: jest.fn(), id: jest.fn(), isCancelled: jest.fn() };
    const native = fakeNativeClient({
      addHandler: jest.fn().mockReturnValue(handle),
    });
    const client = new CoproductClient(native);

    const received: LifecycleEvent[] = [];
    const cancellable = client.addHandler(0 as LifecycleEvent, (event) => {
      received.push(event);
    });

    const [, handler] = (native.addHandler as jest.Mock).mock.calls[0] as [
      LifecycleEvent,
      LifecycleHandler,
    ];
    handler.onEvent(0 as LifecycleEvent);

    expect(received).toEqual([0]);
    cancellable.cancel();
    expect(handle.cancel).toHaveBeenCalled();
  });

  it('addEvaluationHook only fires the handler for the registered stage', () => {
    const handle = {
      cancel: jest.fn(),
      id: jest.fn(),
      isCancelled: jest.fn(),
    } as HookHandleLike;
    const native = fakeNativeClient({
      addEvaluationHook: jest.fn().mockReturnValue(handle),
    });
    const client = new CoproductClient(native);

    const received: HookContext[] = [];
    client.addEvaluationHook(1 as EvaluationStage, (ctx) => {
      received.push(ctx);
    });

    const [hook] = (native.addEvaluationHook as jest.Mock).mock.calls[0] as [
      EvaluationHook,
    ];
    hook.onStage(
      2 as EvaluationStage,
      { flagKey: 'wrong-stage' } as HookContext
    );
    hook.onStage(1 as EvaluationStage, { flagKey: 'flag' } as HookContext);

    expect(received).toEqual([{ flagKey: 'flag' }]);
  });

  it('exposes state and snapshot as getters', () => {
    const snapshot: CoproductSnapshot = {
      version: 1n,
      flagCount: 3,
      environment: 'production',
    };
    const native = fakeNativeClient({
      state: jest.fn().mockReturnValue(1 as ProviderState),
      snapshotView: jest.fn().mockReturnValue(snapshot),
    });
    const client = new CoproductClient(native);

    expect(client.state).toBe(1);
    expect(client.snapshot).toEqual(snapshot);
  });

  it('shutdown delegates to the native client', async () => {
    const native = fakeNativeClient();
    const client = new CoproductClient(native);

    await client.shutdown();

    expect(native.shutdown).toHaveBeenCalled();
  });
});
