jest.mock('react-native-keychain', () => ({
  getGenericPassword: jest.fn(),
  setGenericPassword: jest.fn(),
}));

import * as Keychain from 'react-native-keychain';
import { KeychainSecureStore } from '../defaultSecureStore';
import { SecureStoreError } from '../generated/coproduct_ffi_uniffi';

describe('KeychainSecureStore', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('writes a value under a per-key service', async () => {
    (Keychain.setGenericPassword as jest.Mock).mockResolvedValue(true);
    const store = new KeychainSecureStore();

    await store.write('scaffold-handshake-id', 'ok');

    expect(Keychain.setGenericPassword).toHaveBeenCalledWith(
      'scaffold-handshake-id',
      'ok',
      expect.objectContaining({
        service: 'app.coproduct.sdk.scaffold-handshake-id',
      })
    );
  });

  it('reads back a previously written value', async () => {
    (Keychain.getGenericPassword as jest.Mock).mockResolvedValue({
      username: 'scaffold-handshake-id',
      password: 'ok',
    });
    const store = new KeychainSecureStore();

    const value = await store.read('scaffold-handshake-id');

    expect(value).toBe('ok');
    expect(Keychain.getGenericPassword).toHaveBeenCalledWith(
      expect.objectContaining({
        service: 'app.coproduct.sdk.scaffold-handshake-id',
      })
    );
  });

  it('returns undefined when no value has been written', async () => {
    (Keychain.getGenericPassword as jest.Mock).mockResolvedValue(false);
    const store = new KeychainSecureStore();

    const value = await store.read('missing-key');

    expect(value).toBeUndefined();
  });

  it('maps a genuine read failure to SecureStoreError.ReadFailed', async () => {
    (Keychain.getGenericPassword as jest.Mock).mockRejectedValue(
      new Error('keychain unavailable')
    );
    const store = new KeychainSecureStore();

    try {
      await store.read('some-key');
      throw new Error('expected read() to throw');
    } catch (error) {
      expect(SecureStoreError.ReadFailed.instanceOf(error)).toBe(true);
    }
  });

  it('maps a genuine write failure to SecureStoreError.WriteFailed', async () => {
    (Keychain.setGenericPassword as jest.Mock).mockRejectedValue(
      new Error('keychain unavailable')
    );
    const store = new KeychainSecureStore();

    try {
      await store.write('some-key', 'value');
      throw new Error('expected write() to throw');
    } catch (error) {
      expect(SecureStoreError.WriteFailed.instanceOf(error)).toBe(true);
    }
  });
});
