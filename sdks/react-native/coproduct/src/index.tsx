import RNFS from 'react-native-fs';

import installer from './NativeCoproduct';
import {
  default as generatedCoproduct,
  initialize as nativeInitialize,
  ProviderState,
  type FfiConfig,
  type HostSecureStore,
  type HostTransport,
  type HttpRequest,
  type HttpResponse,
} from './generated/coproduct_ffi_uniffi';
import { CoproductClient } from './client';
import { HostTimer } from './hostTimer';
import { staticDeviceAttributes } from './deviceContext';
import { readSessionAttributes } from './sessionStore';
import { NetworkMonitor } from './networkMonitor';
import { FetchTransport } from './defaultTransport';
import { KeychainSecureStore } from './defaultSecureStore';

export { CoproductClient } from './client';
export type { AttributeValue } from './attributeValue';
export type { Cancellable } from './observation';
export type { HostSecureStore, HostTransport };

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

// Validation transport used only by tests and examples that opt in
// explicitly via CoproductInitializeOptions.transport; no longer the
// implicit production default (see FetchTransport).
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

// Validation secure store used only by tests and examples that opt in
// explicitly via CoproductInitializeOptions.secureStore; no longer the
// implicit production default (see KeychainSecureStore).
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

export type CoproductInitializeOptions = {
  transport?: HostTransport;
  secureStore?: HostSecureStore;
  pollIntervalSecs?: number;
  startupTimeoutSecs?: number;
  anonymousId?: string;
  endpoint?: string;
  pollOnForeground?: boolean;
  // Per-request timeout applied by the default FetchTransport. Ignored when
  // a caller supplies their own `transport`. Mirrors iOS's
  // CoproductConfig.requestTimeout (Task 9's "Interfaces" note anticipates
  // this field; this is where it's actually added).
  requestTimeoutMs?: number;
};

// A shutdown() racing an in-flight initialize() rejects that initialize()
// call with this error, rather than silently resurrecting a torn-down
// instance, matching iOS's CoproductError.cancelledByShutdown.
export class CoproductCancelledError extends Error {
  constructor() {
    super('[coproduct] initialize cancelled by shutdown');
  }
}

// User agent identifying this platform wrapper to the Coproduct backend.
const USER_AGENT = 'coproduct-rn/1.0.2'; // x-release-please-version

type Stored = {
  sdkKey: string;
  client: CoproductClient;
  timer: HostTimer;
  networkMonitor: NetworkMonitor;
};

let stored: Stored | null = null;
let inFlight: Promise<CoproductClient> | null = null;
let inFlightKey: string | null = null;
// Bumped by every shutdown. An initialize captures the generation it was
// claimed under, so a completion whose generation no longer matches knows a
// shutdown intervened and must not store or resurrect the instance.
let generation = 0;

export class Coproduct {
  static async initialize(
    sdkKey: string,
    options: CoproductInitializeOptions = {}
  ): Promise<CoproductClient> {
    if (stored) {
      if (stored.sdkKey !== sdkKey) {
        console.warn(
          '[coproduct] initialize called with different sdkKey; returning existing instance'
        );
      }
      return stored.client;
    }
    if (inFlight) {
      if (inFlightKey !== sdkKey) {
        console.warn(
          '[coproduct] initialize called with a different sdkKey while initialization is in progress; joining the in-flight initialize'
        );
      }
      return inFlight;
    }

    const claimedGeneration = generation;
    inFlightKey = sdkKey;
    const task = runInitialize(sdkKey, options, claimedGeneration);
    inFlight = task;
    try {
      return await task;
    } finally {
      if (generation === claimedGeneration) {
        inFlight = null;
        inFlightKey = null;
      }
    }
  }

  static async shutdown(): Promise<void> {
    generation += 1;
    const current = stored;
    stored = null;
    inFlight = null;
    inFlightKey = null;
    if (!current) return;

    current.timer.stop();
    current.networkMonitor.stop();
    await current.client.shutdown();
  }
}

export default Coproduct;

async function runInitialize(
  sdkKey: string,
  options: CoproductInitializeOptions,
  claimedGeneration: number
): Promise<CoproductClient> {
  // The cache directory is platform-sandboxed and computed automatically.
  // Developers do not pick cache locations, so no override is exposed.
  const cacheDir = RNFS.CachesDirectoryPath;
  const transport =
    options.transport ?? new FetchTransport(options.requestTimeoutMs);
  const secureStore = options.secureStore ?? new KeychainSecureStore();
  const pollIntervalSecs = options.pollIntervalSecs ?? 60;
  const startupTimeoutSecs = options.startupTimeoutSecs ?? 3;
  const pollOnForeground = options.pollOnForeground ?? true;

  const config: FfiConfig = {
    pollIntervalSecs: BigInt(pollIntervalSecs),
    startupTimeoutSecs: BigInt(startupTimeoutSecs),
    anonymousId: options.anonymousId,
    endpoint: options.endpoint,
    pollOnForeground,
  };

  const nativeClient = await nativeInitialize(
    sdkKey,
    USER_AGENT,
    cacheDir,
    config,
    transport,
    secureStore
  );
  const client = new CoproductClient(nativeClient);

  const sessionAttributes = await readSessionAttributes();
  await client.setAutoPopulatedAttributes({
    ...staticDeviceAttributes(),
    ...sessionAttributes,
  });

  const timer = new HostTimer({
    intervalSecs: pollIntervalSecs,
    pollOnForeground,
    poll: () => client.pollNow(),
  });

  const networkMonitor = new NetworkMonitor((networkType) => {
    client
      .setAutoPopulatedAttributes({ network_type: networkType })
      .catch((error) => {
        console.error('[coproduct] failed to publish network_type', error);
      });
  });

  // A shutdown that ran during the construct above must not resurrect this
  // instance: tear the orphan down and report the cancellation so the caller
  // never sees initialize succeed against a torn-down SDK.
  if (generation !== claimedGeneration) {
    await client.shutdown();
    throw new CoproductCancelledError();
  }

  stored = { sdkKey, client, timer, networkMonitor };
  timer.start();
  networkMonitor.start();

  await waitForFirstPoll(client, startupTimeoutSecs, claimedGeneration);

  if (generation !== claimedGeneration) {
    throw new CoproductCancelledError();
  }
  return client;
}

// Waits up to startupTimeoutSecs for the first poll to move the provider off
// NotReady, so a fast network resolves initialize as ready while a slow or
// unreachable one still returns within the deadline. Reads served during and
// after the wait fall back to cache or developer defaults.
async function waitForFirstPoll(
  client: CoproductClient,
  startupTimeoutSecs: number,
  claimedGeneration: number
): Promise<void> {
  if (startupTimeoutSecs <= 0) return;
  const deadline = Date.now() + startupTimeoutSecs * 1000;
  while (client.state === ProviderState.NotReady && Date.now() < deadline) {
    if (generation !== claimedGeneration) return;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
}
