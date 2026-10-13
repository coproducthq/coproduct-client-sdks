import { Platform } from 'react-native';
import {
  PERMISSIONS,
  request,
  requestNotifications,
  type Permission,
} from 'react-native-permissions';

export type PermissionRequestFn = (
  permission: string
) => Promise<Record<string, string>>;

const BY_PLATFORM: Partial<
  Record<string, Partial<Record<'ios' | 'android', Permission>>>
> = {
  camera: { ios: PERMISSIONS.IOS.CAMERA, android: PERMISSIONS.ANDROID.CAMERA },
  microphone: {
    ios: PERMISSIONS.IOS.MICROPHONE,
    android: PERMISSIONS.ANDROID.RECORD_AUDIO,
  },
  location: {
    ios: PERMISSIONS.IOS.LOCATION_WHEN_IN_USE,
    android: PERMISSIONS.ANDROID.ACCESS_FINE_LOCATION,
  },
  photos: {
    ios: PERMISSIONS.IOS.PHOTO_LIBRARY,
    android: PERMISSIONS.ANDROID.READ_MEDIA_IMAGES,
  },
};

// Maps an authored flow's requestPermission action to a real OS permission
// prompt. Mirrors Flutter's _defaultRequestPermission/_permissionByName
// (flow_runtime.dart), backed by react-native-permissions instead of
// permission_handler. "notifications" is handled separately because this
// library exposes it through requestNotifications(), not the PERMISSIONS
// constant table -- iOS notification permission is a UNUserNotificationCenter
// API distinct from the generic permission system, and requestNotifications
// already handles the Android 13+ POST_NOTIFICATIONS permission internally.
export const defaultRequestPermission: PermissionRequestFn = async (
  permission
): Promise<Record<string, string>> => {
  if (permission === 'notifications') {
    const { status } = await requestNotifications();
    return { status };
  }

  const target = BY_PLATFORM[permission]?.[Platform.OS as 'ios' | 'android'];
  if (target == null) {
    return { status: 'error', message: `Unknown permission "${permission}"` };
  }

  const status = await request(target);
  return { status };
};
