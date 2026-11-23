import NativeCoproductStorage from './NativeCoproductStorage';

// Small JSON files the SDK keeps in the app's documents directory: the session
// counters, UTM attribution, and the last GPS fix. The SDK's own native module
// reads and writes them, at the paths earlier releases wrote through
// react-native-fs, so upgrading keeps the stored values. Every failure is
// logged and reported as "nothing stored", never thrown, because none of these
// values may stop initialize

export async function readDocumentJson<T>(
  name: string,
  label: string
): Promise<T | null> {
  try {
    const raw = NativeCoproductStorage?.readDocumentFile(name);
    return raw == null || raw === '' ? null : (JSON.parse(raw) as T);
  } catch (error) {
    console.error(`[coproduct] failed to read ${label} store`, error);
    return null;
  }
}

export async function writeDocumentJson(
  name: string,
  value: unknown,
  label: string
): Promise<void> {
  try {
    const written = NativeCoproductStorage?.writeDocumentFile(
      name,
      JSON.stringify(value)
    );
    if (written !== true) {
      console.error(`[coproduct] failed to persist ${label} store`);
    }
  } catch (error) {
    console.error(`[coproduct] failed to persist ${label} store`, error);
  }
}
