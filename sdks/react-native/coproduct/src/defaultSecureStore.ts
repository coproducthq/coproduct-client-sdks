import * as Keychain from 'react-native-keychain';
import {
  SecureStoreError,
  type HostSecureStore,
} from './generated/coproduct_ffi_uniffi';

// Namespace prefix for every key this SDK stores, matching the
// app.coproduct.* reverse-DNS convention AGENTS.md documents for iOS's
// Keychain service.
const SERVICE_PREFIX = 'app.coproduct.sdk';

// Production HostSecureStore default, backed by the OS keychain/keystore via
// react-native-keychain. One keychain service per key, since
// setGenericPassword stores a single username/password pair per service.
// MockSecureStore (src/index.tsx) stays available for tests but is no longer
// the implicit default. Mirrors KeychainSecureStore.swift: a missing item is
// an empty identity (undefined), not an error; a genuine keychain failure
// throws a typed SecureStoreError so the core can distinguish the two.
export class KeychainSecureStore implements HostSecureStore {
  async read(key: string): Promise<string | undefined> {
    let credentials: Awaited<ReturnType<typeof Keychain.getGenericPassword>>;
    try {
      credentials = await Keychain.getGenericPassword({
        service: serviceFor(key),
      });
    } catch {
      throw SecureStoreError.ReadFailed.new();
    }
    if (!credentials) return undefined;
    return credentials.password;
  }

  async write(key: string, value: string): Promise<void> {
    try {
      await Keychain.setGenericPassword(key, value, {
        service: serviceFor(key),
      });
    } catch {
      throw SecureStoreError.WriteFailed.new();
    }
  }
}

function serviceFor(key: string): string {
  return `${SERVICE_PREFIX}.${key}`;
}
