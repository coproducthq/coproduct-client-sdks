import RNFS from 'react-native-fs';

import installer from './NativeCoproduct';
import {
  BoolDelivery,
  default as generatedCoproduct,
  initialize as nativeInitialize,
  type BoolObservationLike,
  type CoproductClientLike,
  type FfiConfig,
  type HostSecureStore,
  type HostTransport,
  type HttpRequest,
  type HttpResponse,
} from './generated/coproduct_ffi_uniffi';

type GlobalWithCoproduct = typeof globalThis & {
  __coproductRustInstalled?: boolean;
  __coproductRustInitialized?: boolean;
};

const coproductGlobal = globalThis as GlobalWithCoproduct;

if (!coproductGlobal.__coproductRustInstalled) {
  installer.installRustCrate();
  coproductGlobal.__coproductRustInstalled = true;
}

if (!coproductGlobal.__coproductRustInitialized) {
  generatedCoproduct.initialize();
  coproductGlobal.__coproductRustInitialized = true;
}

export type { HostSecureStore, HostTransport };

export async function uniffiInitAsync(): Promise<void> {
  // Native RN does synchronous module installation; this keeps parity with
  // UBRN's async web entrypoint and lets examples await a common hook.
}

function emptyJsonBody(): ArrayBuffer {
  const body = new ArrayBuffer(2);
  const bytes = new Uint8Array(body);
  bytes[0] = 123;
  bytes[1] = 125;
  return body;
}

// Validation transport used when callers do not supply a host transport.
export class MockTransport implements HostTransport {
  requestCount = 0;
  lastRequest: HttpRequest | null = null;

  get completedHandshake(): boolean {
    return this.requestCount > 0;
  }

  async request(req: HttpRequest): Promise<HttpResponse> {
    this.requestCount += 1;
    this.lastRequest = req;

    return {
      status: 200,
      body: emptyJsonBody(),
      headers: [{ name: 'content-type', value: 'application/json' }],
    };
  }
}

// Validation secure store used when callers do not supply a host secure store.
export class MockSecureStore implements HostSecureStore {
  readCount = 0;
  writeCount = 0;

  private values = new Map<string, string>();

  get completedHandshake(): boolean {
    return (
      this.writeCount > 0 &&
      this.readCount > 0 &&
      this.values.get('scaffold-handshake-id') === 'ok'
    );
  }

  async read(key: string): Promise<string | undefined> {
    this.readCount += 1;
    return this.values.get(key);
  }

  async write(key: string, value: string): Promise<void> {
    this.writeCount += 1;
    this.values.set(key, value);
  }
}

export const mockTransport = new MockTransport();
export const mockSecureStore = new MockSecureStore();

export type Cancellable = {
  cancel(): void;
};

type NativeObservation = BoolObservationLike & {
  uniffiDestroy?: () => void;
};

export class CoproductClient {
  constructor(private readonly nativeClient: CoproductClientLike) {}

  getBool(key: string, defaultValue: boolean): boolean {
    return this.nativeClient.getBool(key, defaultValue);
  }

  // Low-level observation hook used by current demos. Higher-level React bindings
  // can layer on top of this cancellation primitive. onChange is invoked once with
  // the value at subscription and then on every change. A key with no usable value
  // resolves to defaultValue
  observe(
    key: string,
    defaultValue: boolean,
    onChange: (value: boolean) => void | Promise<void>
  ): Cancellable {
    const observation = this.nativeClient.observeBool(key);
    let cancelled = false;

    // A handler failure is the developer's, not the SDK's. It is reported and
    // swallowed so one rejection cannot end delivery for a live observation
    const deliver = async (value: boolean): Promise<void> => {
      try {
        await onChange(value);
      } catch (error) {
        console.error('[coproduct] flag observation handler failed', error);
      }
    };

    // The drain awaits the native mailbox, so it never blocks the JavaScript
    // thread and a handler that calls back into the SDK cannot stall delivery
    const drain = async (): Promise<void> => {
      // A cancel that lands in the same tick as observe() (a synchronous
      // `sub.cancel()` right after the call, or React 18 StrictMode's
      // synchronous dev-mode double-invoke) runs before this scheduled
      // microtask does. By then the observation handle is destroyed, and a
      // generated method called after uniffiDestroy throws, so both the
      // early return and the try/catch below are needed: the guard skips
      // the common case, and the try/catch contains a destroy that races in
      // between the guard and the call itself
      if (cancelled) {
        return;
      }
      let seedValue: boolean;
      try {
        seedValue = observation.seed() ?? defaultValue;
      } catch (error) {
        console.error('[coproduct] flag observation drain ended', error);
        return;
      }
      await deliver(seedValue);
      while (!cancelled) {
        let delivery;
        try {
          delivery = await observation.pollNext();
        } catch (error) {
          // The observation was destroyed underneath the loop, or the bridge
          // failed. Either way there is nothing left to drain
          console.error('[coproduct] flag observation drain ended', error);
          return;
        }
        if (!BoolDelivery.Value.instanceOf(delivery)) {
          return;
        }
        await deliver(delivery.inner.value ?? defaultValue);
      }
    };

    // Scheduled rather than started inline. An async function runs synchronously
    // up to its first await, so calling drain() here would invoke the handler
    // before observe() returned, breaking the ordinary
    // `sub = client.observe(k, d, () => sub.cancel())` shape and diverging from
    // the other platforms' delivery timing. Promise.resolve().then(...) schedules
    // the same microtask as queueMicrotask would, using only Promise, which the
    // package's ESNext lib already declares
    Promise.resolve().then(() => {
      void drain();
    });

    return {
      cancel(): void {
        // Idempotent: a generated method called after uniffiDestroy throws
        if (cancelled) {
          return;
        }
        cancelled = true;
        // Closing the mailbox resolves a parked pollNext to Closed. The loop may
        // still be between that resolution and its return when the handle is
        // released, which is why the drain treats a throw from pollNext as a
        // normal end
        observation.cancel();
        (observation as NativeObservation).uniffiDestroy?.();
      },
    };
  }
}

export type CoproductInitializeOptions = {
  transport?: HostTransport;
  secureStore?: HostSecureStore;
};

// User agent identifying this platform wrapper to the Coproduct backend
const USER_AGENT = 'coproduct-rn/0.0.1-dev';

// Default config mirroring coproduct_core::config::CoproductConfig::default
const DEFAULT_CONFIG: FfiConfig = {
  pollIntervalSecs: 60n,
  startupTimeoutSecs: 3n,
  anonymousId: undefined,
  endpoint: undefined,
  pollOnForeground: true,
};

export class Coproduct {
  static async initialize(
    sdkKey: string,
    options: CoproductInitializeOptions = {}
  ): Promise<CoproductClient> {
    // The cache directory is platform-sandboxed and computed automatically.
    // Customers do not pick cache locations, so no override is exposed.
    const cacheDir = RNFS.CachesDirectoryPath;
    const transport = options.transport ?? mockTransport;
    const secureStore = options.secureStore ?? mockSecureStore;
    const nativeClient = await nativeInitialize(
      sdkKey,
      USER_AGENT,
      cacheDir,
      DEFAULT_CONFIG,
      transport,
      secureStore
    );

    return new CoproductClient(nativeClient);
  }
}

export default Coproduct;
