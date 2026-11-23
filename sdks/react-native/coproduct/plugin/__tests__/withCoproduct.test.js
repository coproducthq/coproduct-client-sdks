// The Expo CLI provides expo/config-plugins to an app's plugins. This
// workspace has no expo package, so the same module comes from the
// @expo/config-plugins dev dependency
jest.mock(
  'expo/config-plugins',
  () => jest.requireActual('@expo/config-plugins'),
  {
    virtual: true,
  }
);

const withCoproduct = require('../withCoproduct');
const { requestedPermissions, withPermissionsPodfile } = withCoproduct;

// The lines of an Expo 56 prebuild Podfile the plugin anchors to
const PODFILE = [
  'require File.join(File.dirname(`node --print "require.resolve(\'expo/package.json\')"`), "scripts/autolinking")',
  'require File.join(File.dirname(`node --print "require.resolve(\'react-native/package.json\')"`), "scripts/react_native_pods")',
  '',
  "platform :ios, '15.1'",
  'prepare_react_native_project!',
  '',
  "target 'App' do",
  'end',
].join('\n');

describe('requestedPermissions', () => {
  it('accepts true for notifications and a usage description for the rest', () => {
    expect(
      requestedPermissions({
        permissions: { notifications: true, location: 'Shows nearby content.' },
      })
    ).toEqual([
      ['notifications', null],
      ['location', 'Shows nearby content.'],
    ]);
  });

  it('skips a permission set to false', () => {
    expect(requestedPermissions({ permissions: { camera: false } })).toEqual(
      []
    );
  });

  it('requests nothing without options', () => {
    expect(requestedPermissions(undefined)).toEqual([]);
  });

  it('rejects a permission the SDK cannot request', () => {
    expect(() =>
      requestedPermissions({ permissions: { bluetooth: true } })
    ).toThrow('Unknown permission "bluetooth"');
  });

  it('rejects a usage-described permission set to true', () => {
    expect(() =>
      requestedPermissions({ permissions: { camera: true } })
    ).toThrow('Set "camera" to the sentence iOS shows');
  });

  it('rejects an unknown option', () => {
    expect(() => requestedPermissions({ paywall: true })).toThrow(
      'Unknown plugin option "paywall"'
    );
  });
});

describe('withPermissionsPodfile', () => {
  it('adds the setup require and one setup_permissions call', () => {
    const podfile = withPermissionsPodfile(PODFILE, [
      'Notifications',
      'Camera',
    ]);

    expect(podfile).toContain(
      'require.resolve(\'react-native-permissions/package.json\')"`), "scripts/setup")'
    );
    expect(podfile).toContain(
      "setup_permissions([\n  'Camera',\n  'Notifications',\n])"
    );
    expect(podfile.match(/setup_permissions\(/g)).toHaveLength(1);
  });

  it('replaces its block on the next prebuild, dropping a removed permission', () => {
    const first = withPermissionsPodfile(PODFILE, ['Notifications', 'Camera']);
    const second = withPermissionsPodfile(first, ['Notifications']);

    expect(second).toContain("setup_permissions([\n  'Notifications',\n])");
    expect(second).not.toContain("'Camera'");
    expect(second.match(/setup_permissions\(/g)).toHaveLength(1);
    expect(second.match(/scripts\/setup/g)).toHaveLength(1);
  });

  it('names the fix when the Podfile has no anchor', () => {
    expect(() =>
      withPermissionsPodfile("target 'App' do\nend\n", ['Camera'])
    ).toThrow('Could not find where to add the react-native-permissions setup');
  });
});

describe('withCoproduct', () => {
  const baseConfig = () => ({ name: 'app', slug: 'app' });

  it('leaves the config alone when no permission is requested', () => {
    const config = withCoproduct(baseConfig(), {});
    expect(config.mods).toBeUndefined();
    expect(config.android).toBeUndefined();
  });

  it('adds the Android permissions for each requested permission', () => {
    const config = withCoproduct(baseConfig(), {
      permissions: { notifications: true, location: 'Shows nearby content.' },
    });

    expect(config.android.permissions).toEqual(
      expect.arrayContaining([
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.ACCESS_COARSE_LOCATION',
      ])
    );
  });

  it('refuses a react-native-permissions entry with its own handlers listed first', () => {
    const config = {
      ...baseConfig(),
      plugins: [
        ['react-native-permissions', { iosPermissions: ['Contacts'] }],
        [
          '@coproduct/react-native-sdk',
          { permissions: { notifications: true } },
        ],
      ],
    };

    expect(() =>
      withCoproduct(config, { permissions: { notifications: true } })
    ).toThrow(
      'List "@coproduct/react-native-sdk" before "react-native-permissions"'
    );
  });

  it('accepts the bare react-native-permissions entry that expo install adds', () => {
    const config = {
      ...baseConfig(),
      plugins: [
        'react-native-permissions',
        [
          '@coproduct/react-native-sdk',
          { permissions: { notifications: true } },
        ],
      ],
    };

    expect(() =>
      withCoproduct(config, { permissions: { notifications: true } })
    ).not.toThrow();
  });
});
