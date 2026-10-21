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
  refName: 'react-native-v1.1.0',
  resolvedSha: SHA,
  runSha: SHA,
  tagCommitSubject: 'chore(main): release react-native 1.1.0',
  identityOk: true,
};
const decide = (overrides = {}) => decideMode({ ...base, ...overrides });

test('releases when every condition is met', () => {
  const result = decide();
  assert.equal(result.mode, 'release');
  assert.equal(result.version, '1.1.0');
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

test('runs checks only for a prerelease tag', () => {
  assert.equal(decide({ refName: 'react-native-v1.1.0-rc.1' }).mode, 'checks');
});

test('runs checks only for another SDK tag', () => {
  assert.equal(decide({ refName: 'flutter-v1.1.0' }).mode, 'checks');
});

test('runs checks only when the tag does not resolve to the run commit', () => {
  assert.equal(decide({ resolvedSha: 'b'.repeat(40) }).mode, 'checks');
});

test('runs checks only for a commit that is not a release commit', () => {
  assert.equal(decide({ tagCommitSubject: 'fix(rn): repair polling' }).mode, 'checks');
});

test('accepts the squash suffix on the release subject', () => {
  assert.equal(decide({ tagCommitSubject: 'chore(main): release react-native 1.1.0 (#23)' }).mode, 'release');
});

test('rejects text after the version in the subject', () => {
  assert.equal(decide({ tagCommitSubject: 'chore(main): release react-native 1.1.0-extra' }).mode, 'checks');
});

test('rejects a subject that names a different version than the tag', () => {
  assert.equal(decide({ tagCommitSubject: 'chore(main): release react-native 1.0.3' }).mode, 'checks');
});

test('runs checks only when the identity check fails', () => {
  const result = decide({ identityOk: false });
  assert.equal(result.mode, 'checks');
  assert.match(result.reason, /identity/);
});

const RN = 'sdks/react-native/coproduct';
const CLI = join(dirname(fileURLToPath(import.meta.url)), 'release-mode.mjs');

function repo({ userAgentVersion }) {
  const root = mkdtempSync(join(tmpdir(), 'release-mode-'));
  const write = (path, text) => {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), text);
  };
  write('.github/release-please-config.json', JSON.stringify({
    packages: {
      [RN]: {
        'release-type': 'node',
        component: 'react-native',
        'extra-files': [{ type: 'generic', path: 'src/index.tsx' }],
      },
    },
  }));
  write('.github/.release-please-manifest.json', JSON.stringify({ [RN]: '1.1.0' }));
  write(`${RN}/package.json`, JSON.stringify({ name: 'x', version: '1.1.0' }));
  write(
    `${RN}/src/index.tsx`,
    `import x from 'y';\nconst USER_AGENT = 'coproduct-rn/${userAgentVersion}'; // x-release-please-version\n`
  );
  const git = (...args) =>
    execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.com', ...args], {
      cwd: root,
      encoding: 'utf8',
    }).trim();
  git('init', '-q');
  git('add', '-A');
  git('commit', '-q', '-m', 'chore(main): release react-native 1.1.0');
  return { root, sha: git('rev-parse', 'HEAD') };
}

function runCli({ root, sha }) {
  return execFileSync('node', [CLI], {
    cwd: root,
    encoding: 'utf8',
    env: {
      ...process.env,
      ACTOR_ID: BOT,
      REF_TYPE: 'tag',
      REF_NAME: 'react-native-v1.1.0',
      RESOLVED_SHA: sha,
      RUN_SHA: sha,
    },
  });
}

test('CLI prints release outputs for a consistent release commit', () => {
  const out = runCli(repo({ userAgentVersion: '1.1.0' }));
  assert.match(out, /^mode=release$/m);
  assert.match(out, /^version=1\.1\.0$/m);
});

test('CLI prints checks when the User-Agent line disagrees', () => {
  const out = runCli(repo({ userAgentVersion: '1.0.3' }));
  assert.match(out, /^mode=checks$/m);
  assert.doesNotMatch(out, /^version=/m);
});

test('rejects malformed squash suffixes on the subject', () => {
  for (const tagCommitSubject of [
    'chore(main): release react-native 1.1.0 (#23) extra',
    'chore(main): release react-native 1.1.0 (#abc)',
  ]) {
    assert.equal(decide({ tagCommitSubject }).mode, 'checks', tagCommitSubject);
  }
});

test('runs checks only for a branch even when its name looks like a tag', () => {
  assert.equal(decide({ refType: 'branch', refName: 'react-native-v1.1.0' }).mode, 'checks');
});

test('runs checks only for tags that merely contain the pattern', () => {
  for (const refName of ['xreact-native-v1.1.0', 'react-native-v1x1x0']) {
    assert.equal(decide({ refName }).mode, 'checks', refName);
  }
});

test('runs checks only for a ref name carrying a newline', () => {
  assert.equal(decide({ refName: 'react-native-v1.1.0\nmode=release' }).mode, 'checks');
});

function cliEnv(overrides = {}) {
  return {
    ...process.env,
    ACTOR_ID: BOT,
    REF_TYPE: 'tag',
    REF_NAME: 'react-native-v1.1.0',
    RESOLVED_SHA: SHA,
    RUN_SHA: SHA,
    ...overrides,
  };
}

test('CLI prints checks outside a git repository', () => {
  const dir = mkdtempSync(join(tmpdir(), 'release-mode-nogit-'));
  const out = execFileSync('node', [CLI], { cwd: dir, encoding: 'utf8', env: cliEnv({ GIT_CEILING_DIRECTORIES: tmpdir() }) });
  assert.match(out, /^mode=checks$/m);
  assert.match(out, /^reason=/m);
});

test('CLI prints exactly one mode line for a hostile ref name', () => {
  const { root, sha } = repo({ userAgentVersion: '1.1.0' });
  const out = execFileSync('node', [CLI], {
    cwd: root,
    encoding: 'utf8',
    env: cliEnv({ REF_NAME: 'react-native-v1.1.0\nmode=release', RESOLVED_SHA: sha, RUN_SHA: sha }),
  });
  assert.equal(out.match(/^mode=/gm).length, 1);
  assert.match(out, /^mode=checks$/m);
});

test('CLI runs when invoked through a symlink', () => {
  const { root, sha } = repo({ userAgentVersion: '1.1.0' });
  const link = join(mkdtempSync(join(tmpdir(), 'release-mode-link-')), 'rm.mjs');
  symlinkSync(CLI, link);
  const out = execFileSync('node', [link], { cwd: root, encoding: 'utf8', env: cliEnv({ RESOLVED_SHA: sha, RUN_SHA: sha }) });
  assert.match(out, /^mode=release$/m);
});
