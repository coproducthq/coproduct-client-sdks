#!/usr/bin/env node
// Keeps react-native-iap and react-native-nitro-modules optional, so an app
// that only reads flags builds without them and gets no BILLING permission.
// The SDK may name them in type-only imports, and load react-native-iap
// lazily from the paywall bridge. Nothing else may load them, and the native
// build files must not depend on either
import { createRequire } from 'node:module';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

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

const PEERS = new Set(['react-native-iap', 'react-native-nitro-modules']);
const peerOf = (specifier) => [...PEERS].find((p) => specifier === p || specifier.startsWith(`${p}/`));

// TypeScript's own parser, from the SDK's dev dependencies, so comments,
// strings, regex literals, and JSX can never hide or invent an import
const ts = createRequire(join(dirname(fileURLToPath(import.meta.url)), '../../../sdks/react-native/coproduct/package.json'))('typescript');

// Each place the file loads a paywall package at runtime: { peer, how }
function runtimeLoads(path, text) {
  const kind = path.endsWith('.tsx') ? ts.ScriptKind.TSX : path.endsWith('.js') ? ts.ScriptKind.JS : ts.ScriptKind.TS;
  const source = ts.createSourceFile(path, text, ts.ScriptTarget.Latest, false, kind);
  const loads = [];
  const literal = (node) => node && (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) ? node.text : undefined;
  const visit = (node) => {
    if (ts.isImportDeclaration(node) && !node.importClause?.isTypeOnly) {
      const peer = peerOf(literal(node.moduleSpecifier) ?? '');
      if (peer) loads.push({ peer, how: node.importClause ? 'import' : 'bare import' });
    } else if (ts.isExportDeclaration(node) && !node.isTypeOnly && node.moduleSpecifier) {
      const peer = peerOf(literal(node.moduleSpecifier) ?? '');
      if (peer) loads.push({ peer, how: 'export' });
    } else if (ts.isImportEqualsDeclaration(node) && !node.isTypeOnly && ts.isExternalModuleReference(node.moduleReference)) {
      const peer = peerOf(literal(node.moduleReference.expression) ?? '');
      if (peer) loads.push({ peer, how: 'import-equals' });
    } else if (ts.isCallExpression(node)) {
      const callee = node.expression.kind === ts.SyntaxKind.ImportKeyword ? 'import' : ts.isIdentifier(node.expression) && node.expression.text === 'require' ? 'require' : undefined;
      const peer = callee && peerOf(literal(node.arguments[0]) ?? '');
      if (peer) loads.push({ peer, how: `${callee}()` });
    }
    ts.forEachChild(node, visit);
  };
  visit(source);
  return loads;
}

export function checkOptionalPeers(pkgDir) {
  const problems = [];
  const rel = (path) => relative(pkgDir, path);

  for (const path of files(join(pkgDir, 'src'), (n) => /\.(ts|tsx|js)$/.test(n))) {
    const file = rel(path);
    for (const { peer, how } of runtimeLoads(path, readFileSync(path, 'utf8'))) {
      if (how === 'require()' && peer === 'react-native-iap' && file === LAZY_FILE) continue;
      problems.push(`${file} loads ${peer} at import time with ${how}. Use "import type", or load react-native-iap lazily in ${LAZY_FILE}.`);
    }
  }

  // npm installs a peer automatically unless its metadata marks it optional
  const pkgJson = JSON.parse(readFileSync(join(pkgDir, 'package.json'), 'utf8'));
  for (const name of ['react-native-iap', 'react-native-nitro-modules']) {
    if (!pkgJson.peerDependencies?.[name]) problems.push(`${name} must be listed in peerDependencies.`);
    if (pkgJson.peerDependenciesMeta?.[name]?.optional !== true) problems.push(`${name} must be marked optional in peerDependenciesMeta, or npm installs it in every app.`);
    if (pkgJson.dependencies?.[name]) problems.push(`${name} must not be in dependencies, or every app installs it.`);
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
