#!/usr/bin/env node
// Keeps react-native-iap and react-native-nitro-modules optional, so an app
// that only reads flags builds without them and gets no BILLING permission.
// The SDK may name them in type-only imports, and load react-native-iap
// lazily from the paywall bridge. Nothing else may load them, and the native
// build files must not depend on either
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const PEER = "(react-native-iap|react-native-nitro-modules)(?:/[^'\"]*)?";
const STATIC = new RegExp(`\\b(import|export)\\s+(type\\s+)?([^;'"]*?)\\bfrom\\s*['"]${PEER}['"]`, 'g');
const BARE = new RegExp(`\\bimport\\s*['"]${PEER}['"]`, 'g');
const CALL = new RegExp(`\\b(require|import)\\s*\\(\\s*['"]${PEER}['"]`, 'g');
const LAZY_FILE = 'src/paywall/iapPaywallBridge.ts';
const NATIVE = /nitro|react-native-iap|RNIap/i;
const SKIP = new Set(['__tests__', '__mocks__', '__fixtures__', 'build', 'generated', '.gradle', '.cxx', 'node_modules', 'CoproductFFI.xcframework', 'jniLibs']);

function files(dir, keep, out = []) {
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      if (!SKIP.has(name)) files(path, keep, out);
    } else if (keep(name)) {
      out.push(path);
    }
  }
  return out;
}

// Comments mention the packages by name, and are not code
const stripComments = (text) => text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

export function checkOptionalPeers(pkgDir) {
  const problems = [];
  const rel = (path) => relative(pkgDir, path);

  for (const path of files(join(pkgDir, 'src'), (n) => /\.(ts|tsx|js)$/.test(n))) {
    const file = rel(path);
    const code = stripComments(readFileSync(path, 'utf8'));
    for (const m of code.matchAll(STATIC)) {
      if (!m[2]) problems.push(`${file} loads ${m[4]} at import time. Use "import type", or load it lazily in ${LAZY_FILE}.`);
    }
    for (const m of code.matchAll(BARE)) problems.push(`${file} loads ${m[1]} at import time with a bare import.`);
    for (const m of code.matchAll(CALL)) {
      const allowed = m[1] === 'require' && m[2] === 'react-native-iap' && file === LAZY_FILE;
      if (!allowed) problems.push(`${file} loads ${m[2]} with ${m[1]}(). Only ${LAZY_FILE} may, and only react-native-iap.`);
    }
  }

  const manifest = join(pkgDir, 'android/src/main/AndroidManifest.xml');
  if (existsSync(manifest) && readFileSync(manifest, 'utf8').includes('com.android.vending.BILLING')) {
    problems.push('android/src/main/AndroidManifest.xml declares com.android.vending.BILLING. Only react-native-iap may add it, for apps that install it.');
  }

  const nativeFiles = [
    ...['Coproduct.podspec', 'android/build.gradle', 'android/CMakeLists.txt', 'react-native.config.js'].map((p) => join(pkgDir, p)).filter(existsSync),
    ...files(join(pkgDir, 'cpp'), () => true),
    ...files(join(pkgDir, 'ios'), () => true),
    ...files(join(pkgDir, 'android'), (n) => !['build.gradle', 'CMakeLists.txt', 'AndroidManifest.xml'].includes(n) && !/\.(so|jar|png)$/.test(n)),
  ];
  for (const path of nativeFiles) {
    readFileSync(path, 'utf8').split('\n').forEach((line, i) => {
      if (NATIVE.test(line)) problems.push(`${rel(path)}:${i + 1} mentions Nitro or IAP. The native build must not depend on the optional paywall packages.`);
    });
  }
  return problems;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const root = join(dirname(fileURLToPath(import.meta.url)), '../../..');
  const pkgDir = process.argv[2] ?? join(root, 'sdks/react-native/coproduct');
  const problems = checkOptionalPeers(pkgDir);
  if (problems.length > 0) {
    console.error('Optional paywall packages failed:');
    for (const problem of problems) console.error(`- ${problem}`);
    process.exit(1);
  }
  console.log('Optional paywall packages: react-native-iap and react-native-nitro-modules stay optional');
}
