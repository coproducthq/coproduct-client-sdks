import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { decideMode } from './release-mode.mjs';

const BOT = '345134390';
const SHA = 'a'.repeat(40);

const base = {
  actorId: BOT,
  refType: 'tag',
  refName: 'flutter-v1.3.0',
  resolvedSha: SHA,
  runSha: SHA,
  tagCommitSubject: 'chore(main): release flutter 1.3.0',
  identityOk: true,
  manifestVersion: '1.3.0',
};
const decide = (overrides = {}) => decideMode({ ...base, ...overrides });

test('releases when every condition is met', () => {
  const result = decide();
  assert.equal(result.mode, 'release');
  assert.equal(result.version, '1.3.0');
});

test('runs checks only for a person and names the actor', () => {
  const result = decide({ actorId: '12345' });
  assert.equal(result.mode, 'checks');
  assert.equal(result.version, undefined);
  assert.match(result.reason, /12345/);
});

test('runs checks only for a branch and says it is not a tag', () => {
  const result = decide({ refType: 'branch', refName: 'main' });
  assert.equal(result.mode, 'checks');
  assert.match(result.reason, /not a tag/);
});

test('runs checks only for a branch even when its name looks like a tag', () => {
  assert.equal(decide({ refType: 'branch', refName: 'flutter-v1.3.0' }).mode, 'checks');
});

test('runs checks only for another SDK tag', () => {
  const result = decide({ refName: 'react-native-v1.3.0' });
  assert.equal(result.mode, 'checks');
  assert.match(result.reason, /flutter-vX\.Y\.Z/);
});

test('runs checks only for a prerelease tag', () => {
  assert.equal(decide({ refName: 'flutter-v1.3.0-rc.1' }).mode, 'checks');
});

test('runs checks only for tags that merely contain the pattern', () => {
  for (const refName of ['xflutter-v1.3.0', 'flutter-v1x3x0']) {
    assert.equal(decide({ refName }).mode, 'checks', refName);
  }
});

test('runs checks only when the tag does not resolve to the run commit', () => {
  assert.equal(decide({ resolvedSha: 'b'.repeat(40) }).mode, 'checks');
});

test('runs checks only for a commit that is not a release commit', () => {
  assert.equal(decide({ tagCommitSubject: 'fix(flutter): repair polling' }).mode, 'checks');
});

test('accepts the squash suffix on the release subject', () => {
  assert.equal(decide({ tagCommitSubject: 'chore(main): release flutter 1.3.0 (#40)' }).mode, 'release');
});

test('rejects text after the version in the subject', () => {
  assert.equal(decide({ tagCommitSubject: 'chore(main): release flutter 1.3.0-extra' }).mode, 'checks');
});

test('rejects malformed squash suffixes on the subject', () => {
  for (const tagCommitSubject of [
    'chore(main): release flutter 1.3.0 (#40) extra',
    'chore(main): release flutter 1.3.0 (#abc)',
  ]) {
    assert.equal(decide({ tagCommitSubject }).mode, 'checks', tagCommitSubject);
  }
});

test('rejects the React Native release subject', () => {
  assert.equal(decide({ tagCommitSubject: 'chore(main): release react-native 1.3.0' }).mode, 'checks');
});

test('rejects a subject that names a different version than the tag', () => {
  assert.equal(decide({ tagCommitSubject: 'chore(main): release flutter 1.2.0' }).mode, 'checks');
});

test('runs checks only when the identity check fails', () => {
  const result = decide({ identityOk: false });
  assert.equal(result.mode, 'checks');
  assert.match(result.reason, /identity/);
});

test('runs checks only when the manifest names a different version than the tag', () => {
  const result = decide({ manifestVersion: '1.2.0' });
  assert.equal(result.mode, 'checks');
  assert.equal(result.version, undefined);
  assert.match(result.reason, /manifest/);
  assert.match(result.reason, /1\.2\.0/);
  assert.match(result.reason, /1\.3\.0/);
});

test('runs checks only when the manifest version is missing', () => {
  for (const manifestVersion of [undefined, null, '', 1.3]) {
    const result = decide({ manifestVersion });
    assert.equal(result.mode, 'checks', String(manifestVersion));
    assert.match(result.reason, /manifest/);
  }
});

test('runs checks only for a ref name carrying a newline', () => {
  assert.equal(decide({ refName: 'flutter-v1.3.0\nmode=release' }).mode, 'checks');
});

const FLUTTER = 'sdks/flutter/coproduct';
const RN = 'sdks/react-native/coproduct';
const CLI = join(dirname(fileURLToPath(import.meta.url)), 'release-mode.mjs');

// The repo also holds a React Native package whose version line disagrees
// with the manifest, so a release here proves the identity check reads only
// Flutter's lines

function repo({ pubspecVersion = '1.3.0', manifestVersion = '1.3.0', manifest = true } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'flutter-release-mode-'));
  const write = (path, text) => {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), text);
  };
  write('.github/release-please-config.json', JSON.stringify({
    packages: {
      [RN]: { 'release-type': 'node', component: 'react-native' },
      [FLUTTER]: {
        'release-type': 'dart',
        component: 'flutter',
        'extra-files': [{ type: 'generic', path: 'lib/src/sdk_version.dart' }],
      },
    },
  }));
  if (manifest) {
    write('.github/.release-please-manifest.json', JSON.stringify({ [RN]: '1.0.3', [FLUTTER]: manifestVersion }));
  }
  write(`${RN}/package.json`, JSON.stringify({ name: 'x', version: '9.9.9' }));
  write(`${FLUTTER}/pubspec.yaml`, `name: coproduct\nversion: ${pubspecVersion}\n`);
  write(
    `${FLUTTER}/lib/src/sdk_version.dart`,
    `const sdkVersion = '${manifestVersion}'; // x-release-please-version\n`
  );
  const git = (...args) =>
    execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.com', ...args], {
      cwd: root,
      encoding: 'utf8',
    }).trim();
  git('init', '-q');
  git('add', '-A');
  git('commit', '-q', '-m', 'chore(main): release flutter 1.3.0');
  return { root, sha: git('rev-parse', 'HEAD') };
}

function cliEnv(overrides = {}) {
  return {
    ...process.env,
    ACTOR_ID: BOT,
    REF_TYPE: 'tag',
    REF_NAME: 'flutter-v1.3.0',
    RESOLVED_SHA: SHA,
    RUN_SHA: SHA,
    ...overrides,
  };
}

function runCli({ root, sha }, overrides = {}) {
  return execFileSync('node', [CLI], {
    cwd: root,
    encoding: 'utf8',
    env: cliEnv({ RESOLVED_SHA: sha, RUN_SHA: sha, ...overrides }),
  });
}

test('CLI prints release outputs for a consistent release commit', () => {
  const out = runCli(repo());
  assert.match(out, /^mode=release$/m);
  assert.match(out, /^version=1\.3\.0$/m);
  assert.match(out, /^reason=/m);
});

test('CLI prints checks when the pubspec disagrees with the manifest', () => {
  const out = runCli(repo({ pubspecVersion: '1.2.0' }));
  assert.match(out, /^mode=checks$/m);
  assert.doesNotMatch(out, /^version=/m);
  assert.match(out, /^reason=.*identity/m);
});

test('CLI prints checks when every version line agrees on a version other than the tag', () => {
  const out = runCli(repo({ pubspecVersion: '1.2.0', manifestVersion: '1.2.0' }));
  assert.match(out, /^mode=checks$/m);
  assert.doesNotMatch(out, /^version=/m);
  assert.match(out, /^reason=.*manifest.*1\.2\.0/m);
});

test('CLI prints checks when the manifest is missing', () => {
  const out = runCli(repo({ manifest: false }));
  assert.match(out, /^mode=checks$/m);
  assert.match(out, /^reason=.*manifest/m);
});

test('CLI prints checks outside a git repository', () => {
  const dir = mkdtempSync(join(tmpdir(), 'flutter-release-mode-nogit-'));
  const out = execFileSync('node', [CLI], {
    cwd: dir,
    encoding: 'utf8',
    env: cliEnv({ GIT_CEILING_DIRECTORIES: tmpdir() }),
  });
  assert.match(out, /^mode=checks$/m);
  assert.match(out, /^reason=/m);
});

test('CLI sanitizes a control character in the ref and prints exactly one mode line', () => {
  const out = runCli(repo(), { REF_NAME: 'flutter-v1.3.0\nmode=release' });
  assert.equal(out.match(/^mode=/gm).length, 1);
  assert.match(out, /^mode=checks$/m);
  const reasons = out.match(/^reason=.*$/gm);
  assert.equal(reasons.length, 1);
  assert.match(reasons[0], /flutter-v1\.3\.0 mode=release/);
});

test('CLI runs when invoked through a symlink', () => {
  const { root, sha } = repo();
  const link = join(mkdtempSync(join(tmpdir(), 'flutter-release-mode-link-')), 'rm.mjs');
  symlinkSync(CLI, link);
  const out = execFileSync('node', [link], {
    cwd: root,
    encoding: 'utf8',
    env: cliEnv({ RESOLVED_SHA: sha, RUN_SHA: sha }),
  });
  assert.match(out, /^mode=release$/m);
});
