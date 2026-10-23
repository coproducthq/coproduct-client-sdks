#!/usr/bin/env node
// Keep in step with scripts/release/react-native/registry.mjs, the template
// this module ports to pub.dev
//
// Decides whether a version still needs publishing, and confirms afterwards
// that pub.dev serves exactly the sealed files. Whenever pub.dev's answer is
// uncertain, no state is printed
//
// Usage:
//   registry.mjs state <pkg> <version> <sealPath>
//   registry.mjs confirm <pkg> <version> <sealPath>
//   registry.mjs latest <pkg>
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const PLAIN = /^(\d+)\.(\d+)\.(\d+)$/;
const RUNBOOK = 'Follow the bad-version runbook in DEVELOPMENT.md';
const SEAL_LINE = /^([0-9a-f]{64})  (\d+)  ([0-7]{3,4})  (.+)$/;
const HEX64 = /^[0-9a-f]{64}$/;

const parts = (version) => PLAIN.exec(version ?? '')?.slice(1).map(Number);

// Returns a positive number when a is higher than b. Only plain X.Y.Z
// versions are ordered, because a wrong guess here could skip a real release
function compareVersions(a, b) {
  const left = parts(a);
  const right = parts(b);
  if (!left || !right) throw new Error(`cannot compare versions ${a} and ${b}`);
  for (let i = 0; i < 3; i++) {
    if (left[i] !== right[i]) return left[i] - right[i];
  }
  return 0;
}

/**
 * Parses seal.txt into a Map from path to { sha256, mode }. Each line is
 * sha256, size, mode, and path, split on the first three double spaces, so a
 * path may itself contain double spaces. Anything else throws
 */
export function parseSeal(text) {
  const seal = new Map();
  for (const line of String(text).split('\n')) {
    if (line === '') continue;
    const match = SEAL_LINE.exec(line);
    if (!match) throw new Error(`the seal holds a malformed line: ${JSON.stringify(line)}`);
    const [, sha256, , mode, path] = match;
    if (seal.has(path)) throw new Error(`the seal lists ${path} twice`);
    seal.set(path, { sha256, mode: Number.parseInt(mode, 8) });
  }
  if (seal.size === 0) throw new Error('the seal lists no files');
  return seal;
}

// Returns the versions entry, or undefined when the version is absent. An
// answer without a versions list is not a package answer, so it throws
function findVersion(pkgJson, version) {
  if (pkgJson === null) return undefined;
  if (!Array.isArray(pkgJson?.versions)) throw new Error('the pub.dev answer lists no versions');
  return pkgJson.versions.find((entry) => entry?.version === version);
}

/**
 * Returns 'publish', 'already-published', 'mismatch', 'stale', or
 * 'retracted'. pkgJson is null when pub.dev does not know the package.
 * archive maps each regular file pub.dev serves to { sha256, mode }, and is
 * needed only when the version is present and not retracted
 */
export function pubState({ pkgJson, version, seal, archive }) {
  // Comparing a version with itself rejects one that is not plain X.Y.Z
  compareVersions(version, version);
  const entry = findVersion(pkgJson, version);
  if (entry !== undefined) {
    if (entry.retracted === true) return 'retracted';
    if (!(archive instanceof Map)) throw new Error(`${version} is on pub.dev, but its archive was not read`);
    if (archive.size !== seal.size) return 'mismatch';
    for (const [path, sealed] of seal) {
      const served = archive.get(path);
      // pub writes every file as 644 plus the execute bits it was given
      const expectedMode = 0o644 | (sealed.mode & 0o111);
      if (!served || served.sha256 !== sealed.sha256 || served.mode !== expectedMode) return 'mismatch';
    }
    return 'already-published';
  }
  const latest = pkgJson?.latest?.version ?? null;
  if (latest !== null && compareVersions(latest, version) > 0) return 'stale';
  return 'publish';
}

class Absent extends Error {}

// An archive with unsafe entries stays unsafe, so it is never retried
class Refused extends Error {}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const retryMs = () => Number(process.env.REGISTRY_RETRY_MS ?? 10000);
const baseUrl = () => (process.env.PUB_BASE_URL ?? 'https://pub.dev').replace(/\/+$/, '');

async function withRetries(attempts, fn) {
  for (let i = 1; ; i++) {
    try {
      return await fn();
    } catch (error) {
      if (error instanceof Absent || error instanceof Refused || i >= attempts) throw error;
      console.error(`attempt ${i} of ${attempts} failed (${error.message}), retrying`);
      await sleep(retryMs());
    }
  }
}

async function fetchBytes(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(30000) });
  if (!response.ok) throw new Error(`fetching ${url} returned ${response.status}`);
  return Buffer.from(await response.arrayBuffer());
}

// Returns the package answer. Only a 404 means pub.dev does not know the
// package, and it throws Absent. Every other failure is a plain Error
async function fetchPackage(pkg) {
  const url = `${baseUrl()}/api/packages/${encodeURIComponent(pkg)}`;
  const response = await fetch(url, { signal: AbortSignal.timeout(30000) });
  if (response.status === 404) throw new Absent(`${pkg} is not on pub.dev`);
  if (!response.ok) throw new Error(`fetching ${url} returned ${response.status}`);
  const text = await response.text();
  let pkgJson;
  try {
    pkgJson = JSON.parse(text);
  } catch {
    throw new Error(`${url} did not return JSON`);
  }
  if (pkgJson === null || typeof pkgJson !== 'object' || !Array.isArray(pkgJson.versions)) {
    throw new Error(`${url} did not return a package answer`);
  }
  return pkgJson;
}

// Returns the package answer, or null when pub.dev does not know the package
async function readPackage(pkg) {
  try {
    return await fetchPackage(pkg);
  } catch (error) {
    if (error instanceof Absent) return null;
    throw error;
  }
}

/**
 * Returns 'absent' only when pub.dev answers that the package or version is
 * missing, 'present' when it lists the version, and 'error' for anything
 * else, because silence is not absence
 */
export async function pubPresence(pkg, version) {
  try {
    return findVersion(await fetchPackage(pkg), version) === undefined ? 'absent' : 'present';
  } catch (error) {
    return error instanceof Absent ? 'absent' : 'error';
  }
}

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

function listing(args) {
  return execFileSync('tar', args, {
    encoding: 'utf8',
    env: { ...process.env, LC_ALL: 'C' },
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 64 * 1024 * 1024,
  })
    .split('\n')
    .filter((line, i, lines) => !(line === '' && i === lines.length - 1));
}

// Lists every header and returns the regular files' names, or throws naming
// each unsafe entry. The rules match handoff.sh: the verbose listing gives
// each entry's type and the plain listing its name, both in the C locale,
// where tar prints any control or non-ASCII byte as a backslash escape, so a
// name holding a backslash is refused because it is not the stored name
function checkEntries(tarPath) {
  const verbose = listing(['-tvzf', tarPath]);
  const names = listing(['-tzf', tarPath]);
  console.error(`headers in ${tarPath}:`);
  for (const line of verbose) console.error(line);
  if (verbose.length !== names.length) {
    throw new Error(`the verbose and plain listings of ${tarPath} disagree on the entry count`);
  }
  const problems = [];
  const files = [];
  const seen = new Set();
  for (let i = 0; i < names.length; i++) {
    const type = verbose[i].slice(0, 1);
    let name = names[i];
    if (type === 'd') name = name.replace(/\/$/, '');
    const kinds = { l: 'symlink', h: 'hard link', c: 'device', b: 'device', p: 'fifo' };
    if (type === '-') files.push(name);
    else if (type !== 'd') problems.push(`${name}: ${kinds[type] ?? `unsupported entry type ${type}`}`);
    if (name === '') {
      problems.push('(empty name): empty name');
      continue;
    }
    if (name.startsWith('/')) problems.push(`${name}: absolute path`);
    else if (`/${name}/`.includes('/../')) problems.push(`${name}: parent directory reference`);
    else if (`/${name}/`.includes('/./') || name.includes('//')) problems.push(`${name}: non-canonical path`);
    if (name.includes('\\')) problems.push(`${name}: escaped name`);
    if (seen.has(name)) problems.push(`${name}: duplicate path`);
    seen.add(name);
  }
  if (problems.length > 0) {
    throw new Refused(`refusing ${tarPath}, which holds unsafe entries:\n  ${problems.join('\n  ')}`);
  }
  return files;
}

// Returns every path under dir, or throws for anything that is neither a
// regular file nor a directory
function walk(dir, prefix = '') {
  const found = [];
  for (const name of readdirSync(join(dir, prefix))) {
    const rel = prefix === '' ? name : `${prefix}/${name}`;
    const stat = lstatSync(join(dir, rel));
    if (stat.isDirectory()) found.push(...walk(dir, rel));
    else if (stat.isFile()) found.push(rel);
    else throw new Error(`extraction produced ${rel}, which is not a file or directory`);
  }
  return found;
}

// Downloads the version's archive, checks it against pub.dev's own hash and
// its headers, and only then extracts it. Returns Map(path -> { sha256, mode })
async function readArchive(entry) {
  if (typeof entry.archive_url !== 'string' || !HEX64.test(entry.archive_sha256 ?? '')) {
    throw new Error(`pub.dev names no archive and hash for ${entry.version}`);
  }
  const bytes = await fetchBytes(entry.archive_url);
  if (sha256(bytes) !== entry.archive_sha256) {
    throw new Error(`the archive for ${entry.version} does not match pub.dev's own hash`);
  }
  const work = mkdtempSync(join(tmpdir(), 'coproduct-pub-archive-'));
  try {
    const tarPath = join(work, 'archive.tar.gz');
    const dir = join(work, 'files');
    writeFileSync(tarPath, bytes);
    const files = checkEntries(tarPath);
    mkdirSync(dir);
    execFileSync('tar', ['-xpzf', tarPath, '-C', dir], { stdio: ['ignore', 'ignore', 'pipe'] });
    const extracted = walk(dir).sort();
    if (JSON.stringify(extracted) !== JSON.stringify([...files].sort())) {
      throw new Error('the extracted files differ from the archive listing');
    }
    const archive = new Map();
    for (const path of files) {
      const full = join(dir, path);
      archive.set(path, { sha256: sha256(readFileSync(full)), mode: lstatSync(full).mode & 0o7777 });
    }
    return archive;
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

async function stateOnce(pkg, version, seal, attempts) {
  const pkgJson = await withRetries(attempts, () => readPackage(pkg));
  const entry = findVersion(pkgJson, version);
  const archive =
    entry !== undefined && entry.retracted !== true ? await withRetries(attempts, () => readArchive(entry)) : null;
  return pubState({ pkgJson, version, seal, archive });
}

const readSeal = (sealPath) => parseSeal(readFileSync(sealPath, 'utf8'));

async function confirm(pkg, version, seal) {
  const deadline = Date.now() + Number(process.env.REGISTRY_CONFIRM_MS ?? 600000);
  for (;;) {
    let result;
    let reason;
    try {
      result = await stateOnce(pkg, version, seal, 1);
      reason = `pub.dev answers ${result}`;
    } catch (error) {
      if (error instanceof Refused) throw new Error(`${error.message}\n${RUNBOOK}`);
      reason = error.message;
    }
    if (result === 'already-published') return;
    if (result === 'mismatch') {
      throw new Error(`pub.dev serves ${pkg} ${version}, but its files are a mismatch with the seal. ${RUNBOOK}`);
    }
    if (result === 'retracted') {
      throw new Error(`pub.dev holds ${pkg} ${version} retracted. ${RUNBOOK}`);
    }
    if (Date.now() >= deadline) {
      throw new Error(`${pkg} ${version} was not served with the sealed files in time (${reason})`);
    }
    await sleep(retryMs());
  }
}

// Errors can quote pub.dev's answers, so control characters other than the
// newlines this module writes never reach the terminal
const clean = (text) => String(text).replace(/[\x00-\x09\x0b-\x1f\x7f]/g, ' ');

async function main(argv) {
  const [command, pkg, version, sealPath] = argv;
  if (command === 'latest' && pkg && argv.length === 2) {
    const pkgJson = await withRetries(5, () => fetchPackage(pkg));
    const latest = pkgJson?.latest?.version;
    compareVersions(latest, latest);
    console.log(latest);
    return;
  }
  if (!['state', 'confirm'].includes(command) || !pkg || !version || !sealPath || argv.length !== 4) {
    throw new Error('usage: registry.mjs state|confirm <pkg> <version> <sealPath>, or registry.mjs latest <pkg>');
  }
  const seal = readSeal(sealPath);
  if (command === 'state') {
    const result = await stateOnce(pkg, version, seal, 5);
    console.log(`state=${result}`);
  } else {
    await confirm(pkg, version, seal);
    console.log(`confirmed=${version}`);
  }
}

function isMain() {
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isMain()) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(clean(error.message));
    process.exit(1);
  });
}
