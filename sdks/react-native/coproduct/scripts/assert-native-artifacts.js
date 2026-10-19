#!/usr/bin/env node
// Refuse to pack the SDK without valid native libraries. They are gitignored
// build output, so a fresh clone has none, and a pack from it would publish a
// package that no app can build. The podspec and CMake name these paths, so
// they are the ones checked. Headers are parsed here rather than with lipo or
// plutil, so a pack on Linux runs the same checks
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const xcframework = 'ios/CoproductFFI.xcframework';
const problems = [];

function read(rel) {
  try {
    const bytes = fs.readFileSync(path.join(root, rel));
    if (bytes.length === 0) problems.push(`${rel} is empty`);
    return bytes;
  } catch {
    problems.push(`${rel} is missing`);
    return null;
  }
}

// Mach-O CPU types for arm64 and x86_64
const MACHO_CPU = { arm64: 0x0100000c, x86_64: 0x01000007 };

// A fat header lists each slice's CPU type first in an entry of 20 bytes, or
// 32 bytes in the 64-bit variant
function machoArchs(bytes) {
  const magic = bytes.readUInt32BE(0);
  if (magic === 0xcafebabe || magic === 0xcafebabf) {
    const count = bytes.readUInt32BE(4);
    const size = magic === 0xcafebabe ? 20 : 32;
    return Array.from({ length: count }, (_, i) => bytes.readUInt32BE(8 + i * size));
  }
  if (bytes.readUInt32LE(0) === 0xfeedfacf) return [bytes.readUInt32LE(4)];
  return [];
}

function checkFramework(slice, archs) {
  const dir = `${xcframework}/${slice}/CoproductFFI.framework`;
  const binary = read(`${dir}/CoproductFFI`);
  if (binary) {
    const found = machoArchs(binary).sort();
    const wanted = archs.map((a) => MACHO_CPU[a]).sort();
    if (found.join() !== wanted.join()) {
      problems.push(`${dir}/CoproductFFI is not a Mach-O library built for ${archs.join(' and ')}`);
    }
  }
  const plist = read(`${dir}/Info.plist`);
  if (plist && !/<key>CFBundleExecutable<\/key>\s*<string>CoproductFFI<\/string>/.test(plist.toString())) {
    problems.push(`${dir}/Info.plist does not name CoproductFFI as its executable`);
  }
  const privacy = read(`${dir}/PrivacyInfo.xcprivacy`);
  if (privacy && !privacy.toString().includes('NSPrivacyAccessedAPITypes')) {
    problems.push(`${dir}/PrivacyInfo.xcprivacy declares no accessed API types`);
  }
}

// ELF e_machine values for each Android ABI
const ELF_MACHINE = { 'arm64-v8a': 183, 'armeabi-v7a': 40, 'x86': 3, 'x86_64': 62 };

const SONAME = 'libcoproduct_ffi_uniffi.so';
const PAGE_16K = 0x4000;
const PT_LOAD = 1;
const PT_DYNAMIC = 2;
const DT_STRTAB = 5;
const DT_SONAME = 14;

// The program headers of a little-endian ELF file, 32 or 64 bit
function elfSegments(bytes) {
  const is64 = bytes[4] === 2;
  const word = (offset) => (is64 ? Number(bytes.readBigUInt64LE(offset)) : bytes.readUInt32LE(offset));
  const phoff = word(is64 ? 32 : 28);
  const phentsize = bytes.readUInt16LE(is64 ? 54 : 42);
  const phnum = bytes.readUInt16LE(is64 ? 56 : 44);
  return Array.from({ length: phnum }, (_, i) => {
    const at = phoff + i * phentsize;
    return is64
      ? { type: bytes.readUInt32LE(at), offset: word(at + 8), vaddr: word(at + 16), align: word(at + 48), is64 }
      : { type: bytes.readUInt32LE(at), offset: word(at + 4), vaddr: word(at + 8), align: word(at + 28), is64 };
  });
}

// The DT_SONAME string, found through the dynamic section's string table
function elfSoname(bytes, segments) {
  const dynamic = segments.find((s) => s.type === PT_DYNAMIC);
  if (!dynamic) return null;
  const size = dynamic.is64 ? 16 : 8;
  const word = (offset) => (dynamic.is64 ? Number(bytes.readBigUInt64LE(offset)) : bytes.readUInt32LE(offset));
  let strtab = null;
  let soname = null;
  for (let at = dynamic.offset; at + size <= bytes.length; at += size) {
    const tag = word(at);
    if (tag === 0) break;
    if (tag === DT_STRTAB) strtab = word(at + size / 2);
    if (tag === DT_SONAME) soname = word(at + size / 2);
  }
  if (strtab == null || soname == null) return null;
  const load = segments.filter((s) => s.type === PT_LOAD && s.vaddr <= strtab).pop();
  if (!load) return null;
  const start = strtab - load.vaddr + load.offset + soname;
  return bytes.toString('latin1', start, bytes.indexOf(0, start));
}

// The SDK's own library records this one by SONAME, and Google Play requires
// 16 KB page alignment of every native library
function checkAndroid(abi) {
  const rel = `android/src/main/jniLibs/${abi}/libcoproduct_ffi_uniffi.so`;
  const bytes = read(rel);
  if (!bytes) return;
  const isElf = bytes.length > 64 && bytes.toString('latin1', 0, 4) === '\x7fELF';
  if (!isElf || bytes.readUInt16LE(18) !== ELF_MACHINE[abi]) {
    problems.push(`${rel} is not an ELF library for ${abi}`);
    return;
  }
  const segments = elfSegments(bytes);
  const loads = segments.filter((s) => s.type === PT_LOAD);
  if (loads.length === 0 || loads.some((s) => s.align < PAGE_16K)) {
    problems.push(`${rel} is not aligned to 16 KB pages`);
  }
  if (elfSoname(bytes, segments) !== SONAME) {
    problems.push(`${rel} does not carry the SONAME ${SONAME}`);
  }
}

read(`${xcframework}/Info.plist`);
checkFramework('ios-arm64', ['arm64']);
checkFramework('ios-arm64_x86_64-simulator', ['arm64', 'x86_64']);
Object.keys(ELF_MACHINE).forEach(checkAndroid);

if (problems.length > 0) {
  console.error('ERROR: the native libraries are missing or invalid, so the package would not build in every app:');
  for (const problem of problems) console.error(`  ${problem}`);
  console.error('Build them with scripts/package/rn-build-native.sh from the repository root.');
  process.exit(1);
}
