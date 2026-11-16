import type { HostSecureStore } from './generated/coproduct_ffi_uniffi';

// The secure-store key the Rust core owns for the persisted anonymous id.
// Defined once in core/coproduct-core/src/identity.rs and shared by every SDK,
// so it is deliberately not app.coproduct.* namespaced.
export const ANONYMOUS_ID_STORAGE_KEY = 'coproduct.anonymous_id';

/**
 * Wraps the host secure store handed to the Rust core and remembers the last
 * anonymous id that passed through it. The core exposes no getter for the id,
 * but it reads the id from this store on cold start and writes it whenever it
 * generates, overrides, or rotates one, so the last value seen here is the
 * install's current anonymous id.
 *
 * A value the core asks to write is captured even when the write then fails,
 * because the core keeps using that id for the session. The one case this
 * cannot see is a failed cold-start read: the core then generates a
 * session-only id and never writes it, so anonymousId stays undefined.
 */
export class AnonymousIdCapturingSecureStore implements HostSecureStore {
  private captured: string | undefined;

  constructor(private readonly inner: HostSecureStore) {}

  /** The last anonymous id read or written, or undefined until one is seen. */
  get anonymousId(): string | undefined {
    return this.captured;
  }

  async read(key: string): Promise<string | undefined> {
    const value = await this.inner.read(key);
    // The core treats an empty stored value as missing and generates a fresh
    // id, so an empty read is not an id.
    if (key === ANONYMOUS_ID_STORAGE_KEY && value != null && value !== '') {
      this.captured = value;
    }
    return value;
  }

  async write(key: string, value: string): Promise<void> {
    if (key === ANONYMOUS_ID_STORAGE_KEY && value !== '') {
      this.captured = value;
    }
    await this.inner.write(key, value);
  }
}

// The anonymous id source of the shared Coproduct instance. Kept in this
// dependency-free module, rather than read off the client in index.tsx, so the
// paywall subpath can default to it without importing the base entrypoint and
// its native module installation.
let sharedSource: (() => string | undefined) | undefined;

/**
 * Sets, or clears with undefined, the anonymous id source of the shared
 * Coproduct instance. Internal: called by initialize and shutdown.
 */
export function setSharedAnonymousIdSource(
  source: (() => string | undefined) | undefined
): void {
  sharedSource = source;
}

/**
 * The shared Coproduct instance's anonymous id, or undefined when the SDK is
 * not initialized or the id is not known yet.
 */
export function sharedAnonymousId(): string | undefined {
  return sharedSource?.();
}
