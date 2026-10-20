#!/usr/bin/env node
// Checks the packed React Native tarball itself, after yarn pack: every file an
// app needs is present, nothing internal ships, and every version stamp agrees.
// prepack checks the native binaries before packing. This checks what was
// actually packed
import { execFileSync } from 'node:child_process';
import { statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const FW = 'package/ios/CoproductFFI.xcframework';
const SLICES = { device: `${FW}/ios-arm64/CoproductFFI.framework`, simulator: `${FW}/ios-arm64_x86_64-simulator/CoproductFFI.framework` };
const ABIS = ['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64'];
export const LIMIT = 6_000_000;

export const REQUIRED = [
  'package/package.json',
  'package/Coproduct.podspec',
  'package/android/CMakeLists.txt',
  'package/ios/CoproductFFI.xcframework/Info.plist',
  'package/lib/module/index.js',
  'package/lib/typescript/src/index.d.ts',
  ...Object.values(SLICES).flatMap((s) => [`${s}/CoproductFFI`, `${s}/Info.plist`, `${s}/PrivacyInfo.xcprivacy`]),
  ...ABIS.map((abi) => `package/android/src/main/jniLibs/${abi}/libcoproduct_ffi_uniffi.so`),
];
const FORBIDDEN = [
  /^package\/CORE_RELEASE_TRIGGER$/,
  /^package\/(example|scripts|build)\//,
  /(^|\/)(__tests__|__fixtures__|__mocks__|node_modules)\//,
];

export function checkPack({ entries, files, size, version }) {
  const problems = [];
  const present = new Set(entries);
  for (const path of REQUIRED) if (!present.has(path)) problems.push(`missing ${path}`);
  for (const entry of entries) if (FORBIDDEN.some((re) => re.test(entry))) problems.push(`must not ship ${entry}`);
  const pkgVersion = JSON.parse(files['package/package.json'] ?? '{}').version;
  if (pkgVersion !== version) problems.push(`package.json version is ${pkgVersion}, expected ${version}`);
  for (const [name, slice] of Object.entries(SLICES)) {
    const found = (files[`${slice}/Info.plist`] ?? '').match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]*)<\/string>/)?.[1];
    if (found !== version) problems.push(`${name} framework CFBundleShortVersionString is ${found}, expected ${version}`);
  }
  if (size > LIMIT) problems.push(`the package is ${size} bytes, over the ${LIMIT} byte limit`);
  return problems;
}

function main([tgz, version]) {
  const tar = (...args) => execFileSync('tar', args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  const entries = tar('-tzf', tgz).split('\n').filter((e) => e && !e.endsWith('/'));
  const files = {};
  for (const path of ['package/package.json', `${SLICES.device}/Info.plist`, `${SLICES.simulator}/Info.plist`]) {
    if (entries.includes(path)) files[path] = tar('-xzOf', tgz, path);
  }
  const problems = checkPack({ entries, files, size: statSync(tgz).size, version });
  if (problems.length > 0) {
    console.error('Package check failed:');
    for (const problem of problems) console.error(`- ${problem}`);
    console.error('Fix: rebuild the native libraries and repack. Never edit the tarball.');
    process.exit(1);
  }
  console.log(`Package check: ${entries.length} files, ${statSync(tgz).size} bytes, version ${version}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
