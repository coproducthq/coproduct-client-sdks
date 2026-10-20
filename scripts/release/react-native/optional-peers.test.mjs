import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { checkOptionalPeers } from './optional-peers.mjs';

const BRIDGE = 'src/paywall/iapPaywallBridge.ts';
const PKG_JSON = {
  peerDependencies: { 'react-native-iap': '^17.0.1', 'react-native-nitro-modules': '>=0.36.5' },
  peerDependenciesMeta: { 'react-native-iap': { optional: true }, 'react-native-nitro-modules': { optional: true } },
  dependencies: { 'uniffi-bindgen-react-native': '0.31.0-6' },
};
const withPkg = (change) => {
  const pkgJson = structuredClone(PKG_JSON);
  change(pkgJson);
  return { 'package.json': JSON.stringify(pkgJson) };
};

function pkg(extra = {}) {
  const root = mkdtempSync(join(tmpdir(), 'peers-'));
  const files = {
    [BRIDGE]: "import type * as Iap from 'react-native-iap';\nimport type {\n  Purchase,\n} from 'react-native-iap';\n// see react-native-iap's docs\nconst m = require('react-native-iap') as typeof Iap;\n",
    'src/index.tsx': "export const MESSAGE = 'npm install react-native-iap react-native-nitro-modules';\n",
    'src/__tests__/a.test.ts': "import { initConnection } from 'react-native-iap';\n",
    'android/src/main/AndroidManifest.xml': '<manifest xmlns:android="http://schemas.android.com/apk/res/android" />\n',
    'Coproduct.podspec': "s.dependency 'React-Core'\n",
    'android/build.gradle': "dependencies { implementation 'com.facebook.react:react-android' }\n",
    'package.json': JSON.stringify(PKG_JSON),
    ...extra,
  };
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), text);
  }
  return root;
}

test('type imports, the one lazy require, comments, strings, and tests pass', () => {
  assert.deepEqual(checkOptionalPeers(pkg()), []);
});

test('a loading import fails', () => {
  const [p] = checkOptionalPeers(pkg({ 'src/paywall/index.ts': "import { initConnection } from 'react-native-iap';\n" }));
  assert.match(p, /src\/paywall\/index\.ts loads react-native-iap at import time/);
});

test('an inline type specifier still loads the module and fails', () => {
  assert.equal(checkOptionalPeers(pkg({ 'src/a.ts': "import { type Purchase } from 'react-native-iap';\n" })).length, 1);
});

test('a multi-line loading import fails', () => {
  assert.equal(checkOptionalPeers(pkg({ 'src/a.ts': "import {\n  initConnection,\n} from 'react-native-iap';\n" })).length, 1);
});

test('a bare import, a re-export, and a dynamic import fail', () => {
  const problems = checkOptionalPeers(pkg({
    'src/a.ts': "import 'react-native-nitro-modules';\n",
    'src/b.ts': "export { initConnection } from 'react-native-iap';\n",
    'src/c.ts': "const m = await import('react-native-iap');\n",
  }));
  assert.equal(problems.length, 3);
});

test('a require anywhere else, or of Nitro, fails', () => {
  const problems = checkOptionalPeers(pkg({
    'src/paywall/other.ts': "const m = require('react-native-iap');\n",
    [BRIDGE]: "const n = require('react-native-nitro-modules');\n",
  }));
  assert.equal(problems.length, 2);
});

test('comment markers inside strings do not hide a loading import', () => {
  const problems = checkOptionalPeers(pkg({
    'src/a.ts': "const s = 'a // b'; import x from 'react-native-nitro-modules';\n",
    'src/b.ts': "const glob = 'src/**/*.ts';\nimport { y } from 'react-native-iap';\nconst end = '*/';\n",
  }));
  assert.equal(problems.length, 2);
});

test('a template-literal require fails', () => {
  assert.equal(checkOptionalPeers(pkg({ 'src/a.ts': 'const m = require(`react-native-iap`);\n' })).length, 1);
});

test('a paywall package marked not optional fails', () => {
  const [p] = checkOptionalPeers(pkg(withPkg((j) => { j.peerDependenciesMeta['react-native-iap'].optional = false; })));
  assert.match(p, /react-native-iap must be marked optional/);
});

test('missing optional metadata fails', () => {
  assert.equal(checkOptionalPeers(pkg(withPkg((j) => { delete j.peerDependenciesMeta; }))).length, 2);
});

test('a paywall package missing from peerDependencies fails', () => {
  const [p] = checkOptionalPeers(pkg(withPkg((j) => { delete j.peerDependencies['react-native-nitro-modules']; })));
  assert.match(p, /react-native-nitro-modules must be listed in peerDependencies/);
});

test('a paywall package in regular dependencies fails', () => {
  const [p] = checkOptionalPeers(pkg(withPkg((j) => { j.dependencies['react-native-iap'] = '^17.0.1'; })));
  assert.match(p, /react-native-iap must not be in dependencies/);
});

test('BILLING in the SDK manifest fails', () => {
  const [p] = checkOptionalPeers(pkg({ 'android/src/main/AndroidManifest.xml': '<uses-permission android:name="com.android.vending.BILLING" />\n' }));
  assert.match(p, /AndroidManifest\.xml declares com\.android\.vending\.BILLING/);
});

test('a native dependency on Nitro fails', () => {
  const [p] = checkOptionalPeers(pkg({ 'Coproduct.podspec': "s.dependency 'NitroModules'\n" }));
  assert.match(p, /Coproduct\.podspec:1 mentions/);
});

test('the real package passes', () => {
  const real = join(dirname(fileURLToPath(import.meta.url)), '../../../sdks/react-native/coproduct');
  assert.deepEqual(checkOptionalPeers(real), []);
});
