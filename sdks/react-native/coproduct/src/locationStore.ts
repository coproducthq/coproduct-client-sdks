import type { AttributeValue } from './attributeValue';
import { readDocumentJson, writeDocumentJson } from './documentStore';

const LOCATION_FILE_NAME = 'coproduct-location.json';

type LocationFile = {
  lat: number;
  lng: number;
  capturedAt: number;
};

// Persists the most recent GPS fix as a small JSON file in the documents
// directory, like sessionStore.ts (see documentStore.ts). The stored fix seeds
// `device_location` at initialize so a geo-fence can evaluate immediately from
// the last known position, before a fresh fix arrives. The value is a two-element
// [lat, lng] array, the shape the core reads for a geo-fence.
export async function readStoredLocation(): Promise<LocationFile | null> {
  return readDocumentJson<LocationFile>(LOCATION_FILE_NAME, 'location');
}

export async function writeStoredLocation(
  lat: number,
  lng: number,
  now: number = Date.now()
): Promise<void> {
  const next: LocationFile = { lat, lng, capturedAt: now };
  await writeDocumentJson(LOCATION_FILE_NAME, next, 'location');
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
