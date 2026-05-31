import RNFS from 'react-native-fs';

import installer from './NativeCoproduct';
import {
  computeBucket,
  default as generatedCoproduct,
  initialize as nativeInitialize,
  type CoproductClientLike,
  type FlagObserver,
  type HostSecureStore,
  type HostTransport,
  type HttpRequest,
  type HttpResponse,
  type SubscriptionLike,
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

export { computeBucket };
export type { FlagObserver, HostSecureStore, HostTransport };

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

// SCAFFOLD-ONLY: replaced by real Transport wiring in M1.
// The M1 door is already wired: Coproduct.initialize(sdkKey, { transport, secureStore }).
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

// SCAFFOLD-ONLY: replaced by real SecureStore wiring in M1.
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

type NativeSubscription = SubscriptionLike & {
  uniffiDestroy?: () => void;
};

const retainedObservers = new Set<FlagObserver>();

class ObserverSubscription implements Cancellable {
  private observer: FlagObserver | null;

  constructor(
    private readonly subscription: NativeSubscription,
    observer: FlagObserver
  ) {
    this.observer = observer;
    retainedObservers.add(observer);
  }

  cancel(): void {
    this.subscription.uniffiDestroy?.();
    if (this.observer !== null) {
      retainedObservers.delete(this.observer);
    }
    this.observer = null;
  }
}

export class CoproductClient {
  constructor(private readonly nativeClient: CoproductClientLike) {}

  getBool(key: string, defaultValue: boolean): boolean {
    return this.nativeClient.getBool(key, defaultValue);
  }

  observe(
    key: string,
    _defaultValue: boolean,
    onChange: (value: boolean) => void | Promise<void>
  ): Cancellable {
    const observer: FlagObserver = {
      async onChangeBool(value: boolean): Promise<void> {
        await onChange(value);
      },
    };

    const subscription = this.nativeClient.observe(key, observer);
    return new ObserverSubscription(
      subscription as NativeSubscription,
      observer
    );
  }

  wasLoadedFromCache(): boolean {
    return this.nativeClient.wasLoadedFromCache();
  }

  async simulateChange(key: string, newValue: boolean): Promise<void> {
    await this.nativeClient.simulateChange(key, newValue);
  }
}

export type CoproductInitializeOptions = {
  cacheDir?: string;
  transport?: HostTransport;
  secureStore?: HostSecureStore;
};

export class Coproduct {
  static async initialize(
    sdkKey: string,
    options: CoproductInitializeOptions = {}
  ): Promise<CoproductClient> {
    const cacheDir = options.cacheDir ?? RNFS.CachesDirectoryPath;
    const transport = options.transport ?? mockTransport;
    const secureStore = options.secureStore ?? mockSecureStore;
    const nativeClient = await nativeInitialize(
      sdkKey,
      cacheDir,
      transport,
      secureStore
    );

    return new CoproductClient(nativeClient);
  }
}

export default Coproduct;
