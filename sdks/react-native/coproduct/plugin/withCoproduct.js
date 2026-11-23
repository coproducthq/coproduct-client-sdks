// Expo config plugin for @coproduct/react-native-sdk. It configures the native
// projects that `npx expo prebuild` generates for the device permissions an
// app's onboarding flows request, and for location targeting:
//
//   ["@coproduct/react-native-sdk", {
//     "permissions": {
//       "notifications": true,
//       "camera": "Lets you add a profile photo.",
//       "location": "Shows content for where you are."
//     }
//   }]
//
// For each permission it adds the iOS usage description, the iOS permission
// handler react-native-permissions needs, and the Android manifest permission.
// The SDK needs nothing else from the native projects, so an app that requests
// no permissions does not need this plugin.
//
// It runs only inside the Expo CLI, which provides expo/config-plugins, so a
// React Native app without Expo never loads it.
const {
  AndroidConfig,
  CodeGenerator,
  createRunOncePlugin,
  withDangerousMod,
  withInfoPlist,
} = require('expo/config-plugins');
const fs = require('fs');
const path = require('path');

const pkg = require('../package.json');

const PERMISSIONS_PACKAGE = 'react-native-permissions';

// Each permission an onboarding flow can request, by the name the flow uses.
// iosHandler is react-native-permissions' handler for the permission, and
// iosUsageKey the Info.plist key that must describe why the app asks.
// notifications needs no usage description on iOS, so it takes `true`
const PERMISSIONS = {
  notifications: {
    iosHandler: 'Notifications',
    iosUsageKey: null,
    android: ['android.permission.POST_NOTIFICATIONS'],
  },
  camera: {
    iosHandler: 'Camera',
    iosUsageKey: 'NSCameraUsageDescription',
    android: ['android.permission.CAMERA'],
  },
  microphone: {
    iosHandler: 'Microphone',
    iosUsageKey: 'NSMicrophoneUsageDescription',
    android: ['android.permission.RECORD_AUDIO'],
  },
  photos: {
    iosHandler: 'PhotoLibrary',
    iosUsageKey: 'NSPhotoLibraryUsageDescription',
    android: ['android.permission.READ_MEDIA_IMAGES'],
  },
  // Android shows the precise-location prompt only when the app also declares
  // coarse location
  location: {
    iosHandler: 'LocationWhenInUse',
    iosUsageKey: 'NSLocationWhenInUseUsageDescription',
    android: [
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.ACCESS_COARSE_LOCATION',
    ],
  },
};

function pluginError(message) {
  return new Error(`[${pkg.name}] ${message}`);
}

// The requested permissions as [name, usage description or null] pairs,
// rejecting anything the SDK cannot request so a typo fails prebuild instead
// of a prompt silently never appearing
function requestedPermissions(props) {
  if (props == null) return [];
  if (typeof props !== 'object' || Array.isArray(props)) {
    throw pluginError(
      'Plugin options must be an object, such as { "permissions": { "notifications": true } }.'
    );
  }
  for (const key of Object.keys(props)) {
    if (key !== 'permissions') {
      throw pluginError(
        `Unknown plugin option "${key}". The only option is "permissions".`
      );
    }
  }
  const permissions = props.permissions ?? {};
  if (typeof permissions !== 'object' || Array.isArray(permissions)) {
    throw pluginError(
      '"permissions" must be an object, such as { "notifications": true }.'
    );
  }

  const requested = [];
  for (const [name, value] of Object.entries(permissions)) {
    const permission = PERMISSIONS[name];
    if (permission == null) {
      throw pluginError(
        `Unknown permission "${name}". Use one of: ${Object.keys(PERMISSIONS).join(', ')}.`
      );
    }
    if (value === false || value == null) continue;
    if (permission.iosUsageKey == null) {
      if (value !== true) {
        throw pluginError(
          `Set "${name}" to true. It needs no usage description.`
        );
      }
      requested.push([name, null]);
    } else {
      if (typeof value !== 'string' || value.trim() === '') {
        throw pluginError(
          `Set "${name}" to the sentence iOS shows when it asks for this permission, such as "Lets you add a profile photo." App Review rejects apps without one.`
        );
      }
      requested.push([name, value]);
    }
  }
  return requested;
}

// The iOS permission handlers a react-native-permissions plugin entry in the
// app config asks for, and that entry's position in the plugins list
function permissionsPluginEntry(config) {
  const plugins = config.plugins ?? [];
  for (let index = 0; index < plugins.length; index += 1) {
    const entry = plugins[index];
    const name = Array.isArray(entry) ? entry[0] : entry;
    if (name !== PERMISSIONS_PACKAGE) continue;
    const options = Array.isArray(entry) ? entry[1] : undefined;
    return { index, iosPermissions: options?.iosPermissions ?? [] };
  }
  return null;
}

function pluginIndex(config) {
  return (config.plugins ?? []).findIndex(
    (entry) => (Array.isArray(entry) ? entry[0] : entry) === pkg.name
  );
}

// react-native-permissions compiles only the handlers named in one
// setup_permissions call, and a second call replaces the first. This writes
// that single call with every handler asked for, under the same
// generated-block tags react-native-permissions' own plugin uses, so the two
// plugins edit one block rather than writing competing ones. Each prebuild
// replaces the block, so a permission removed from the config is removed here
function withPermissionsPodfile(podfile, handlers) {
  const all = [...new Set(handlers)].sort();
  try {
    return mergeSetup(podfile, all);
  } catch (error) {
    if (error?.code !== 'ERR_NO_MATCH') throw error;
    throw pluginError(
      `Could not find where to add the ${PERMISSIONS_PACKAGE} setup in ios/Podfile. Add setup_permissions to it by hand, as ${PERMISSIONS_PACKAGE} describes.`
    );
  }
}

function mergeSetup(podfile, all) {
  const withRequire = CodeGenerator.mergeContents({
    tag: 'require',
    src: podfile,
    anchor:
      /^require File\.join\(File\.dirname\(`node --print "require\.resolve\('react-native\/package\.json'\)"`\), "scripts\/react_native_pods"\)$/m,
    newSrc: `require File.join(File.dirname(\`node --print "require.resolve('${PERMISSIONS_PACKAGE}/package.json')"\`), "scripts/setup")`,
    offset: 1,
    comment: '#',
  });
  const withSetup = CodeGenerator.mergeContents({
    tag: 'setup',
    src: withRequire.contents,
    anchor: /^prepare_react_native_project!$/m,
    newSrc: `setup_permissions([\n${all.map((h) => `  '${h}',`).join('\n')}\n])`,
    offset: 1,
    comment: '#',
  });
  return withSetup.contents;
}

function withCoproduct(config, props) {
  const requested = requestedPermissions(props);
  if (requested.length === 0) return config;

  // iOS usage descriptions. A value the app already sets in its own config
  // wins, so the plugin never overwrites the app's wording
  config = withInfoPlist(config, (cfg) => {
    for (const [name, description] of requested) {
      const key = PERMISSIONS[name].iosUsageKey;
      if (key != null && cfg.modResults[key] == null) {
        cfg.modResults[key] = description;
      }
    }
    return cfg;
  });

  // react-native-permissions' iOS handlers. Expo runs file edits in reverse
  // plugin order, so an app's own react-native-permissions entry listed before
  // this plugin edits the Podfile last and drops these handlers. Only an
  // entry that names its own handlers does that: the bare entry
  // `npx expo install` adds edits nothing
  const handlers = requested.map(([name]) => PERMISSIONS[name].iosHandler);
  const entry = permissionsPluginEntry(config);
  if (
    entry != null &&
    entry.iosPermissions.length > 0 &&
    entry.index < pluginIndex(config)
  ) {
    throw pluginError(
      `List "${pkg.name}" before "${PERMISSIONS_PACKAGE}" in your app config's plugins, so the iOS permission handlers both of them need are kept.`
    );
  }
  const otherHandlers = entry?.iosPermissions ?? [];
  config = withDangerousMod(config, [
    'ios',
    async (cfg) => {
      const file = path.join(cfg.modRequest.platformProjectRoot, 'Podfile');
      const podfile = await fs.promises.readFile(file, 'utf8');
      const next = withPermissionsPodfile(podfile, [
        ...handlers,
        ...otherHandlers,
      ]);
      if (next !== podfile) await fs.promises.writeFile(file, next, 'utf8');
      return cfg;
    },
  ]);

  // Android manifest permissions
  const androidPermissions = requested.flatMap(
    ([name]) => PERMISSIONS[name].android
  );
  config = AndroidConfig.Permissions.withPermissions(
    config,
    androidPermissions
  );

  return config;
}

module.exports = createRunOncePlugin(withCoproduct, pkg.name, pkg.version);
module.exports.requestedPermissions = requestedPermissions;
module.exports.withPermissionsPodfile = withPermissionsPodfile;
module.exports.PERMISSIONS = PERMISSIONS;
