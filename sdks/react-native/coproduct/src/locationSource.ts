import { Platform } from 'react-native';
import { PERMISSIONS, request } from 'react-native-permissions';

/** A single GPS fix as the [lat, lng] pair the core reads for a geo-fence. */
export type LocationFix = [number, number];

// `@react-native-community/geolocation` is an optional peer, loaded lazily the
// same way the paywall loads react-native-iap: an app that never enables
// location must not need the dependency, and a static import would make it
// required. Metro treats a require() inside try as optional.
type GeolocationModule = {
  getCurrentPosition(
    success: (position: { coords: { latitude: number; longitude: number } }) => void,
    error: (err: { code: number; message: string }) => void,
    options?: { enableHighAccuracy?: boolean; timeout?: number; maximumAge?: number }
  ): void;
};

let cachedModule: GeolocationModule | null | undefined;

function loadGeolocation(): GeolocationModule | null {
  if (cachedModule !== undefined) return cachedModule;
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const mod = require('@react-native-community/geolocation');
    cachedModule = (mod.default ?? mod) as GeolocationModule;
  } catch {
    console.error(
      '[coproduct] location requested but @react-native-community/geolocation is not installed'
    );
    cachedModule = null;
  }
  return cachedModule;
}

/**
 * Requests OS location permission (when-in-use / fine). Returns whether it was
 * granted. Called the first time the host enables location, never at initialize,
 * so the prompt appears on the host's terms.
 */
export async function requestLocationPermission(): Promise<boolean> {
  const target =
    Platform.OS === 'ios'
      ? PERMISSIONS.IOS.LOCATION_WHEN_IN_USE
      : PERMISSIONS.ANDROID.ACCESS_FINE_LOCATION;
  try {
    const status = await request(target);
    return status === 'granted' || status === 'limited';
  } catch (error) {
    console.error('[coproduct] location permission request failed', error);
    return false;
  }
}

/**
 * Reads one GPS fix. Returns `null` when the module is absent or the OS cannot
 * produce a fix, so the caller leaves `device_location` unset and geo-fence
 * rules fall through rather than matching on a bad position.
 */
export function acquireFix(timeoutMs = 10_000): Promise<LocationFix | null> {
  const geolocation = loadGeolocation();
  if (geolocation === null) return Promise.resolve(null);
  return new Promise((resolve) => {
    geolocation.getCurrentPosition(
      (position) => resolve([position.coords.latitude, position.coords.longitude]),
      (error) => {
        console.error('[coproduct] failed to read location', error);
        resolve(null);
      },
      { enableHighAccuracy: false, timeout: timeoutMs, maximumAge: 0 }
    );
  });
}
