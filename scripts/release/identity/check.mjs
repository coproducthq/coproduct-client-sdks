#!/usr/bin/env node
// Checks that every version line release-please manages agrees with the
// release manifest. The manifest is the single source of truth, and only
// release PRs change it
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const CONFIG = '.github/release-please-config.json';
export const MANIFEST = '.github/.release-please-manifest.json';
const MARKER = 'x-release-please-version';
const RELEASE_BRANCH = /^release-please--branches--/;
const STABLE = /^\d+\.\d+\.\d+$/;
const ANY_VERSION = /\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?/;
const NEVER_EDIT = 'Never edit version lines by hand: the release PR updates them.';

function readBaseManifest(root, base) {
  try {
    return JSON.parse(
      execFileSync('git', ['show', `${base}:${MANIFEST}`], {
        cwd: root,
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
      })
    );
  } catch {
    // The base has no manifest, as on the change that adds it
    return {};
  }
}

/**
 * Compares each configured SDK's version lines with the manifest. With a base
 * ref, also refuses a manifest change on any branch that is not a release PR
 */
export function checkIdentity({ root, only, base, branch }) {
  const read = (path) => readFileSync(join(root, path), 'utf8');
  const config = JSON.parse(read(CONFIG));
  const manifest = JSON.parse(read(MANIFEST));
  const baseManifest =
    base && !RELEASE_BRANCH.test(branch ?? '') ? readBaseManifest(root, base) : null;
  const checked = [];
  const problems = [];

  for (const [path, pkg] of Object.entries(config.packages ?? {})) {
    const sdk = pkg.component ?? path;
    if (only && sdk !== only) continue;
    const version = manifest[path];
    if (version === undefined) {
      problems.push(`${sdk}: ${MANIFEST} has no entry for ${path}. Add it with the SDK's latest published version.`);
      continue;
    }
    checked.push({ sdk, version });

    if (!STABLE.test(version)) {
      problems.push(`${sdk}: the manifest names ${version}, which is not a release version. Versions are x.y.z with no suffix such as -dev.`);
    }
    if (pkg['release-type'] === 'node') {
      const actual = JSON.parse(read(join(path, 'package.json'))).version;
      if (actual !== version) {
        problems.push(`${sdk}: ${path}/package.json has ${actual}, but the manifest has ${version}. Set it back to ${version}. ${NEVER_EDIT}`);
      }
    }
    for (const extra of pkg['extra-files'] ?? []) {
      const file = join(path, typeof extra === 'string' ? extra : extra.path);
      if (!existsSync(join(root, file))) {
        problems.push(`${sdk}: ${file} is listed in ${CONFIG} but does not exist. This is configuration damage: when a version line moves, update extra-files to match.`);
        continue;
      }
      const marked = read(file)
        .split('\n')
        .flatMap((text, i) => (text.includes(MARKER) ? [{ text, line: i + 1 }] : []));
      if (marked.length === 0) {
        problems.push(`${sdk}: ${file} has no ${MARKER} marker. This is configuration damage: release-please would stop updating the line. Restore the marker comment on its version line.`);
        continue;
      }
      for (const { text, line } of marked) {
        const found = text.match(ANY_VERSION)?.[0];
        if (found !== version) {
          problems.push(`${sdk}: ${file}:${line} has ${found ?? 'no version'}, but the manifest has ${version}. Set it back to ${version}. ${NEVER_EDIT}`);
        }
      }
    }
    const before = baseManifest?.[path];
    if (before !== undefined && before !== version) {
      problems.push(`${sdk}: this change moves the manifest from ${before} to ${version}. Only release PRs change versions, so revert ${MANIFEST}. ${NEVER_EDIT}`);
    }
  }
  return { checked, problems };
}

function main(argv) {
  let only;
  let base;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--base') base = argv[++i];
    else only = argv[i];
  }
  const root = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
  const branch =
    process.env.GITHUB_HEAD_REF ||
    execFileSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
  const { checked, problems } = checkIdentity({ root, only, base, branch });

  if (problems.length > 0) {
    console.error('Version identity failed:');
    for (const problem of problems) console.error(`- ${problem}`);
    process.exit(1);
  }
  if (checked.length === 0) {
    console.log(`Version identity: ${only ?? 'no SDK'} is not on the release pipeline, so there is nothing to check`);
    return;
  }
  for (const { sdk, version } of checked) console.log(`Version identity: ${sdk} agrees at ${version}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main(process.argv.slice(2));
