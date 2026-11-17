import {
  ANONYMOUS_ID_STORAGE_KEY,
  AnonymousIdCapturingSecureStore,
  setSharedAnonymousIdSource,
  sharedAnonymousId,
} from '../anonymousId';
import type { HostSecureStore } from '../generated/coproduct_ffi_uniffi';

function fakeStore(overrides: Partial<HostSecureStore> = {}): HostSecureStore {
  const values = new Map<string, string>();
  return {
    read: jest.fn(async (key: string) => values.get(key)),
    write: jest.fn(async (key: string, value: string) => {
      values.set(key, value);
    }),
    ...overrides,
  };
}

describe('AnonymousIdCapturingSecureStore', () => {
  it('has no anonymous id until one is read or written', () => {
    const store = new AnonymousIdCapturingSecureStore(fakeStore());

    expect(store.anonymousId).toBeUndefined();
  });

  it('captures a stored anonymous id when the core reads it', async () => {
    const store = new AnonymousIdCapturingSecureStore(
      fakeStore({ read: jest.fn().mockResolvedValue('anon-stored') })
    );

    const value = await store.read(ANONYMOUS_ID_STORAGE_KEY);

    expect(value).toBe('anon-stored');
    expect(store.anonymousId).toBe('anon-stored');
  });

  it('ignores a missing or empty read', async () => {
    const read = jest
      .fn()
      .mockResolvedValueOnce(undefined)
      .mockResolvedValueOnce('');
    const store = new AnonymousIdCapturingSecureStore(fakeStore({ read }));

    await store.read(ANONYMOUS_ID_STORAGE_KEY);
    await store.read(ANONYMOUS_ID_STORAGE_KEY);

    expect(store.anonymousId).toBeUndefined();
  });

  it('captures the id the core writes and passes the write through', async () => {
    const inner = fakeStore();
    const store = new AnonymousIdCapturingSecureStore(inner);

    await store.write(ANONYMOUS_ID_STORAGE_KEY, 'anon-fresh');

    expect(store.anonymousId).toBe('anon-fresh');
    expect(inner.write).toHaveBeenCalledWith(
      ANONYMOUS_ID_STORAGE_KEY,
      'anon-fresh'
    );
  });

  it('keeps the latest written id over an earlier read', async () => {
    const store = new AnonymousIdCapturingSecureStore(
      fakeStore({ read: jest.fn().mockResolvedValue('anon-old') })
    );

    await store.read(ANONYMOUS_ID_STORAGE_KEY);
    await store.write(ANONYMOUS_ID_STORAGE_KEY, 'anon-rotated');

    expect(store.anonymousId).toBe('anon-rotated');
  });

  it('captures a written id even when the write fails', async () => {
    const failure = new Error('keychain locked');
    const store = new AnonymousIdCapturingSecureStore(
      fakeStore({ write: jest.fn().mockRejectedValue(failure) })
    );

    await expect(
      store.write(ANONYMOUS_ID_STORAGE_KEY, 'anon-session')
    ).rejects.toBe(failure);

    expect(store.anonymousId).toBe('anon-session');
  });

  it('captures nothing when the read fails', async () => {
    const failure = new Error('keychain locked');
    const store = new AnonymousIdCapturingSecureStore(
      fakeStore({ read: jest.fn().mockRejectedValue(failure) })
    );

    await expect(store.read(ANONYMOUS_ID_STORAGE_KEY)).rejects.toBe(failure);

    expect(store.anonymousId).toBeUndefined();
  });

  it('ignores other keys', async () => {
    const store = new AnonymousIdCapturingSecureStore(
      fakeStore({ read: jest.fn().mockResolvedValue('other-value') })
    );

    await store.read('scaffold-handshake-id');
    await store.write('scaffold-handshake-id', 'ok');

    expect(store.anonymousId).toBeUndefined();
  });
});

describe('sharedAnonymousId', () => {
  afterEach(() => setSharedAnonymousIdSource(undefined));

  it('is undefined with no shared instance', () => {
    expect(sharedAnonymousId()).toBeUndefined();
  });

  it('reads the current value from the shared source', () => {
    let current: string | undefined;
    setSharedAnonymousIdSource(() => current);

    expect(sharedAnonymousId()).toBeUndefined();
    current = 'anon-1';
    expect(sharedAnonymousId()).toBe('anon-1');
  });
});
