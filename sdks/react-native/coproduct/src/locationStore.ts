import RNFS from 'react-native-fs';
import type { AttributeValue } from './attributeValue';

const LOCATION_FILE_NAME = 'coproduct-location.json';

type LocationFile = {
  lat: number;
  lng: number;
  capturedAt: number;
};

// Persists the most recent GPS fix as a small JSON file via the SDK's existing
// react-native-fs dependency, mirroring sessionStore.ts. The stored fix seeds
// `device_location` at initialize so a geo-fence can evaluate immediately from
// the last known position, before a fresh fix arrives. The value is a two-element
// [lat, lng] array, the shape the core reads for a geo-fence.
export async function readStoredLocation(): Promise<LocationFile | null> {
  const path = `${RNFS.DocumentDirectoryPath}/${LOCATION_FILE_NAME}`;
  try {
    if (await RNFS.exists(path)) {
      const raw = await RNFS.readFile(path, 'utf8');
      return JSON.parse(raw) as LocationFile;
    }
  } catch (error) {
    console.error('[coproduct] failed to read location store', error);
  }
  return null;
}

export async function writeStoredLocation(
  lat: number,
  lng: number,
  now: number = Date.now()
): Promise<void> {
  const path = `${RNFS.DocumentDirectoryPath}/${LOCATION_FILE_NAME}`;
  try {
    const next: LocationFile = { lat, lng, capturedAt: now };
    await RNFS.writeFile(path, JSON.stringify(next), 'utf8');
  } catch (error) {
    console.error('[coproduct] failed to persist location store', error);
  }
}

// The auto-populated attribute a stored fix contributes, or an empty map when
// none is stored. Folded into the initial auto-populated batch like the session
// attributes, so a geo-fence rule can match on launch from the last known fix.
export async function readLocationAttributes(): Promise<
  Record<string, AttributeValue>
> {
  const stored = await readStoredLocation();
  if (stored === null) return {};
  return { device_location: [stored.lat, stored.lng] };
}
