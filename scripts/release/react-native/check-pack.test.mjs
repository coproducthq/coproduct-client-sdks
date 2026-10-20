import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkPack, REQUIRED } from './check-pack.mjs';

const plist = (v) => `<dict><key>CFBundleShortVersionString</key><string>${v}</string></dict>`;
const DEVICE = 'package/ios/CoproductFFI.xcframework/ios-arm64/CoproductFFI.framework/Info.plist';
const SIM = 'package/ios/CoproductFFI.xcframework/ios-arm64_x86_64-simulator/CoproductFFI.framework/Info.plist';

function good(version = '1.0.3') {
  return {
    entries: [...REQUIRED],
    files: {
      'package/package.json': JSON.stringify({ name: '@coproduct/react-native-sdk', version }),
      [DEVICE]: plist(version),
      [SIM]: plist(version),
    },
    size: 3_500_000,
    version,
  };
}
const run = (p) => checkPack(p);

test('a complete package passes', () => {
  assert.deepEqual(run(good()), []);
});

test('a missing native library fails and names it', () => {
  const p = good();
  p.entries = p.entries.filter((e) => !e.includes('jniLibs/x86/'));
  assert.match(run(p)[0], /missing package\/android\/src\/main\/jniLibs\/x86\/libcoproduct_ffi_uniffi\.so/);
});

test('files that must not ship fail', () => {
  for (const extra of ['package/CORE_RELEASE_TRIGGER', 'package/example/App.tsx', 'package/scripts/readme-typecheck.sh', 'package/src/__tests__/a.test.ts', 'package/build/x']) {
    const p = good();
    p.entries.push(extra);
    assert.match(run(p).join('\n'), new RegExp(`must not ship ${extra.replace(/[./]/g, '\\$&')}`), extra);
  }
});

test('a framework version that differs from package.json fails', () => {
  const p = good();
  p.files[SIM] = plist('1.0.2');
  assert.match(run(p)[0], /simulator.*CFBundleShortVersionString is 1\.0\.2, expected 1\.0\.3/);
});

test('a package.json version that differs from the expected version fails', () => {
  const p = good();
  p.files['package/package.json'] = JSON.stringify({ version: '1.0.2' });
  assert.match(run(p)[0], /package\.json version is 1\.0\.2, expected 1\.0\.3/);
});

test('an oversized package fails', () => {
  const p = good();
  p.size = 6_000_001;
  assert.match(run(p)[0], /6000001 bytes, over the 6000000 byte limit/);
});
