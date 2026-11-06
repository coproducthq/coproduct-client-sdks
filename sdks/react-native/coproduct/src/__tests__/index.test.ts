jest.mock('react-native-fs', () => ({
  CachesDirectoryPath: '/mock-caches',
  DocumentDirectoryPath: '/mock-documents',
  exists: jest.fn().mockResolvedValue(false),
  readFile: jest.fn(),
  writeFile: jest.fn().mockResolvedValue(undefined),
}));

jest.mock('react-native-device-info', () => ({
  getSystemVersion: jest.fn(() => '17.0'),
  getVersion: jest.fn(() => '1.0.0'),
  getBuildNumber: jest.fn(() => '1'),
  getDeviceType: jest.fn(() => 'Handset'),
}));

jest.mock('@react-native-community/netinfo', () => ({
  __esModule: true,
  default: { addEventListener: jest.fn(() => jest.fn()) },
}));

jest.mock('react-native-keychain', () => ({
  getGenericPassword: jest.fn().mockResolvedValue(false),
  setGenericPassword: jest.fn().mockResolvedValue(true),
}));

// react-native-permissions calls TurboModuleRegistry.getEnforcing('RNPermissions')
// on import, which throws without the native binary, so stub the surface the
// location source touches
jest.mock('react-native-permissions', () => ({
  PERMISSIONS: {
    IOS: { LOCATION_WHEN_IN_USE: 'ios.permission.LOCATION_WHEN_IN_USE' },
    ANDROID: { ACCESS_FINE_LOCATION: 'android.permission.ACCESS_FINE_LOCATION' },
  },
  RESULTS: {
    UNAVAILABLE: 'unavailable',
    DENIED: 'denied',
    LIMITED: 'limited',
    GRANTED: 'granted',
    BLOCKED: 'blocked',
  },
  request: jest.fn().mockResolvedValue('granted'),
  check: jest.fn().mockResolvedValue('granted'),
}));

jest.mock('../NativeCoproduct', () => ({
  __esModule: true,
  default: {
    installRustCrate: jest.fn(() => true),
    cleanupRustCrate: jest.fn(() => true),
  },
}));

import {
  InitError,
  initialize as nativeInitialize,
  LifecycleEvent,
  PollOutcome,
  ProviderState,
} from '../generated/coproduct_ffi_uniffi';
import {
  Coproduct,
  LifecycleEvent as PublicLifecycleEvent,
  ProviderState as PublicProviderState,
} from '../index';

// `var`, not `const`: index.tsx's module-top-level `generatedCoproduct
// .initialize()` call (see the jest.mock factory below) runs during this
// file's import phase, before this declaration's assignment executes (ES
// imports hoist above it). A `const`/`let` binding would throw
// ReferenceError (TDZ) when that premature call reads it; `var` hoists the
// binding itself, so the premature read harmlessly sees `undefined`.
var mockNativeClient = {
  getBool: jest.fn(),
  state: jest.fn().mockReturnValue(ProviderState.Ready),
  setAutoPopulatedAttributes: jest.fn().mockResolvedValue(undefined),
  pollNow: jest.fn().mockResolvedValue(PollOutcome.Updated.new()),
  shutdown: jest.fn().mockResolvedValue(undefined),
  addHandler: jest.fn(() => ({ cancel: jest.fn() })),
};

jest.mock('../generated/coproduct_ffi_uniffi', () => {
  const actual = jest.requireActual('../generated/coproduct_ffi_uniffi');
  return {
    ...actual,
    // Deferred (not `.mockResolvedValue(mockNativeClient)`) so this factory,
    // which Babel's commonjs transform hoists above the `var
    // mockNativeClient` declaration below, doesn't read it before it's
    // assigned. The closure only reads it when `initialize()` is actually
    // invoked.
    //
    // Note on `generatedCoproduct.initialize()` (index.tsx's unrelated
    // Rust-crate-init call, run once at module load): the returned object
    // here has no (enumerable) `__esModule` flag, because `{...actual}`
    // drops the real module's non-enumerable one. That makes Babel's
    // default-import interop treat this whole object as "the default
    // export", so `generatedCoproduct` in index.tsx resolves to this mock
    // object rather than `actual.default` -- meaning the crate-init call
    // harmlessly invokes this same `initialize` mock instead of the real
    // native `uniffiEnsureInitialized`, which would crash in a JS-only test
    // environment. This is relied upon, not accidental.
    initialize: jest.fn(() => Promise.resolve(mockNativeClient)),
  };
});

describe('Coproduct.initialize', () => {
  afterEach(async () => {
    await Coproduct.shutdown();
    jest.clearAllMocks();
    mockNativeClient.state.mockReturnValue(ProviderState.Ready);
  });

  it('returns the same client for concurrent initialize calls with the same key', async () => {
    const [first, second] = await Promise.all([
      Coproduct.initialize('cpk_mob_test'),
      Coproduct.initialize('cpk_mob_test'),
    ]);

    expect(first).toBe(second);
  });

  it('returns the existing instance for a later initialize call after the first resolves', async () => {
    const first = await Coproduct.initialize('cpk_mob_test');
    const second = await Coproduct.initialize('cpk_mob_test');

    expect(first).toBe(second);
  });

  it('publishes static device and session attributes before resolving', async () => {
    await Coproduct.initialize('cpk_mob_test');

    expect(mockNativeClient.setAutoPopulatedAttributes).toHaveBeenCalled();
  });

  it('bounds the wait for readiness by startupTimeoutSecs without rejecting', async () => {
    mockNativeClient.state.mockReturnValue(ProviderState.NotReady);

    const client = await Coproduct.initialize('cpk_mob_test', {
      startupTimeoutSecs: 0,
    });

    expect(client).toBeDefined();
  });
});

describe('Coproduct.shutdown', () => {
  // Without this, `second` (created mid-test) is never torn down: its real
  // HostTimer (60s poll interval) and NetInfo listener stay alive past the
  // test, which is why Jest reported "did not exit one second after the
  // test run has completed" before this cleanup was added.
  afterEach(async () => {
    await Coproduct.shutdown();
  });

  it('allows a fresh initialize after shutdown', async () => {
    const first = await Coproduct.initialize('cpk_mob_test');
    await Coproduct.shutdown();
    const second = await Coproduct.initialize('cpk_mob_test');

    expect(second).not.toBe(first);
    expect(mockNativeClient.shutdown).toHaveBeenCalled();
  });
});

describe('ProviderState', () => {
  afterEach(async () => {
    await Coproduct.shutdown();
    mockNativeClient.state.mockReturnValue(ProviderState.Ready);
  });

  it('is exported from the package root so callers can compare client.state', async () => {
    mockNativeClient.state.mockReturnValue(ProviderState.Fatal);

    const client = await Coproduct.initialize('cpk_mob_test');

    expect(client.state).toBe(PublicProviderState.Fatal);
  });
});

describe('LifecycleEvent', () => {
  afterEach(async () => {
    await Coproduct.shutdown();
  });

  it('is exported from the package root so callers can register a handler', async () => {
    const client = await Coproduct.initialize('cpk_mob_test');

    client.addHandler(PublicLifecycleEvent.Fatal, () => {});

    expect(mockNativeClient.addHandler).toHaveBeenCalledWith(
      LifecycleEvent.Fatal,
      expect.anything()
    );
  });
});

describe('Coproduct.initialize errors', () => {
  afterEach(async () => {
    await Coproduct.shutdown();
  });

  function rejectNextInitialize(error: Error): void {
    (nativeInitialize as jest.Mock).mockImplementationOnce(() =>
      Promise.reject(error)
    );
  }

  it('adds the reason to the message and keeps the same error', async () => {
    const original = InitError.MalformedSdkKey.new({
      reason: 'expected 40 characters total, got 21',
    });
    rejectNextInitialize(original);

    const error = await Coproduct.initialize('cpk_mob_short').catch(
      (e: unknown) => e
    );

    expect(error).toBe(original);
    expect(InitError.MalformedSdkKey.instanceOf(error)).toBe(true);
    expect((error as Error).message).toBe(
      'InitError.MalformedSdkKey: expected 40 characters total, got 21'
    );
  });

  it('explains a key of the wrong type without echoing the key', async () => {
    const original = InitError.InvalidKeyType.new({ prefix: '(redacted)' });
    rejectNextInitialize(original);

    const error = await Coproduct.initialize('sk_live_x').catch(
      (e: unknown) => e
    );

    expect(error).toBe(original);
    expect((error as Error).message).toBe(
      'InitError.InvalidKeyType: expected a Coproduct mobile SDK key (cpk_mob_)'
    );
  });

  it('leaves an error without a reason unchanged', async () => {
    const original = InitError.MissingSdkKey.new();
    rejectNextInitialize(original);

    const error = await Coproduct.initialize('').catch((e: unknown) => e);

    expect(error).toBe(original);
    expect((error as Error).message).toBe('InitError.MissingSdkKey');
  });
});
