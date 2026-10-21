import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { finalizeAction } from './finalize.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const ABSENT = ['absent', 'absent', 'absent'];

const needsWith = (overrides = {}) => ({
  resolve: { result: 'success' },
  mode: { result: 'success' },
  pack: { result: 'failure' },
  publish: { result: 'skipped' },
  ...overrides,
});

const act = (overrides = {}) =>
  finalizeAction({ mode: 'release', needs: needsWith(), npmChecks: ABSENT, ...overrides });

test('marks the release when a build failed, publish was skipped, and npm lacks the version', () => {
  assert.equal(act(), 'mark-not-published');
});

test('marks the release when a build job was abandoned', () => {
  const needs = needsWith({ pack: { result: 'success' }, 'native-ios': { result: 'abandoned' } });
  assert.equal(act({ needs }), 'mark-not-published');
});

test('marks the release when a build job was cancelled', () => {
  const needs = needsWith({ pack: { result: 'success' }, 'build-ios': { result: 'cancelled' } });
  assert.equal(act({ needs }), 'mark-not-published');
});

test('does nothing when any npm check found the version', () => {
  assert.equal(act({ npmChecks: ['absent', 'present', 'absent'] }), 'none');
});

test('does nothing when any npm check was uncertain', () => {
  assert.equal(act({ npmChecks: ['absent', 'absent', 'error'] }), 'none');
});

test('does nothing without exactly three checks', () => {
  assert.equal(act({ npmChecks: ['absent', 'absent'] }), 'none');
  assert.equal(act({ npmChecks: [] }), 'none');
});

test('does nothing when publish succeeded and docs failed', () => {
  const needs = needsWith({ pack: { result: 'success' }, publish: { result: 'success' }, docs: { result: 'failure' } });
  assert.equal(act({ needs }), 'none');
});

test('does nothing in checks mode', () => {
  assert.equal(act({ mode: 'checks' }), 'none');
});

test('does nothing when publish failed, as after a rejected approval', () => {
  assert.equal(act({ needs: needsWith({ publish: { result: 'failure' } }) }), 'none');
});

test('does nothing when no build job failed', () => {
  assert.equal(act({ needs: needsWith({ pack: { result: 'success' } }) }), 'none');
});

test('does nothing when the publish job is missing from needs', () => {
  const needs = needsWith();
  delete needs.publish;
  assert.equal(act({ needs }), 'none');
});

// CLI tests put a fake npm first on PATH
const fakeDir = mkdtempSync(join(tmpdir(), 'fake-npm-'));
writeFileSync(
  join(fakeDir, 'npm'),
  `#!/bin/sh
case "$FAKE_MODE" in
  manifest) echo '{"name":"x"}'; exit 0 ;;
  fail) echo 'npm error code ETIMEDOUT' >&2; exit 1 ;;
esac
echo '{"error":{"code":"E404"}}'
exit 1
`,
);
chmodSync(join(fakeDir, 'npm'), 0o755);

function cli(env) {
  return spawnSync('node', [join(here, 'finalize.mjs')], {
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${fakeDir}:${process.env.PATH}`,
      FINALIZE_CHECK_MS: '10',
      MODE: 'release',
      NEEDS: JSON.stringify(needsWith()),
      PKG: 'pkg',
      VERSION: '1.1.0',
      FAKE_MODE: 'e404',
      ...env,
    },
  });
}

const actions = (r) => r.stdout.split('\n').filter((line) => line.startsWith('action='));

test('cli prints mark-not-published when every check is a 404', () => {
  const r = cli({});
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(actions(r), ['action=mark-not-published']);
});

test('cli prints none when the version is on npm', () => {
  const r = cli({ FAKE_MODE: 'manifest' });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(actions(r), ['action=none']);
});

test('cli prints none with a warning when npm is uncertain', () => {
  const r = cli({ FAKE_MODE: 'fail' });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(actions(r), ['action=none']);
  assert.match(r.stderr, /warning/i);
});

test('cli prints none for a missing, unparseable, or non-object NEEDS', () => {
  for (const NEEDS of ['', 'not json', 'null', '[]', '"x"']) {
    const r = cli({ NEEDS });
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(actions(r), ['action=none'], `NEEDS=${NEEDS}`);
  }
});

test('cli prints none without running npm outside release mode', () => {
  const r = cli({ MODE: 'checks', FAKE_MODE: 'fail' });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(actions(r), ['action=none']);
});

test('cli prints none when PKG or VERSION is missing', () => {
  const r = cli({ PKG: '' });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(actions(r), ['action=none']);
});
