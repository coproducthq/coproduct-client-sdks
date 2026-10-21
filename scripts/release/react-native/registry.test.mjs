import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { provenanceCommit, publishDecision } from './registry.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const fixture = JSON.parse(
  readFileSync(join(here, 'fixtures', 'provenance-sigstore-sign-5.0.0.json'), 'utf8'),
);
const COMMIT = '7d2900eca1c22b3f87c13987c8d4b7c9a29b733a';

const decide = (overrides = {}) =>
  publishDecision({
    registryTarballSha: null,
    artifactSha: 'aaa',
    version: '1.1.0',
    latest: '1.0.3',
    ...overrides,
  });

test('publishes when the version is absent and latest is lower', () => {
  assert.equal(decide(), 'publish');
});

test('publishes when the version is absent and latest is equal or the package is new', () => {
  assert.equal(decide({ latest: '1.1.0' }), 'publish');
  assert.equal(decide({ latest: null }), 'publish');
});

test('compares versions numerically, not as text', () => {
  assert.equal(decide({ version: '1.10.0', latest: '1.9.0' }), 'publish');
  assert.equal(decide({ version: '1.9.0', latest: '1.10.0' }), 'stale');
});

test('is stale when the version is absent and latest is higher', () => {
  assert.equal(decide({ latest: '1.2.0' }), 'stale');
});

test('is already published when the registry holds the same bytes', () => {
  assert.equal(decide({ registryTarballSha: 'aaa' }), 'already-published');
  assert.equal(decide({ registryTarballSha: 'aaa', latest: '2.0.0' }), 'already-published');
});

test('is a mismatch when the registry holds different bytes', () => {
  assert.equal(decide({ registryTarballSha: 'bbb' }), 'mismatch');
});

test('refuses a latest it cannot order', () => {
  assert.throws(() => decide({ latest: '2.0.0-beta.1' }), /cannot compare/);
  assert.throws(() => decide({ version: 'next' }), /cannot compare/);
});

test('reads the commit from the SLSA provenance', () => {
  assert.equal(provenanceCommit(fixture), COMMIT);
});

function withPayload(payload) {
  return {
    attestations: [
      {
        predicateType: 'https://slsa.dev/provenance/v1',
        bundle: {
          dsseEnvelope: { payload: Buffer.from(JSON.stringify(payload)).toString('base64') },
        },
      },
    ],
  };
}

test('throws when there is no SLSA attestation', () => {
  const publishOnly = {
    attestations: fixture.attestations.filter((a) => !a.predicateType.includes('slsa')),
  };
  assert.throws(() => provenanceCommit(publishOnly), /no SLSA provenance/);
  assert.throws(() => provenanceCommit({}), /no SLSA provenance/);
});

test('throws when the provenance names no resolved dependency', () => {
  const payload = { predicate: { buildDefinition: { resolvedDependencies: [] } } };
  assert.throws(() => provenanceCommit(withPayload(payload)));
});

test('throws when the first dependency has no commit', () => {
  const payload = { predicate: { buildDefinition: { resolvedDependencies: [{ digest: {} }] } } };
  assert.throws(() => provenanceCommit(withPayload(payload)));
});

// CLI tests put a fake npm first on PATH, driven by environment variables
const fakeDir = mkdtempSync(join(tmpdir(), 'fake-npm-'));
const counter = join(fakeDir, 'count');
writeFileSync(
  join(fakeDir, 'npm'),
  `#!/bin/sh
case "$*" in
  *dist-tags.latest*) echo '"1.0.0"'; exit 0 ;;
esac
n=$(cat "$FAKE_COUNT" 2>/dev/null || echo 0)
n=$((n + 1))
echo $n > "$FAKE_COUNT"
if [ "$FAKE_MODE" = "fail" ] || { [ "$FAKE_MODE" = "flaky" ] && [ "$n" -le 2 ]; }; then
  echo 'npm error code ETIMEDOUT' >&2
  exit 1
fi
echo '{"error":{"code":"E404","summary":"not found"}}'
exit 1
`,
);
chmodSync(join(fakeDir, 'npm'), 0o755);

function cli(mode, args = ['state', 'pkg', '1.1.0', 'abc'], extra = {}) {
  writeFileSync(counter, '0');
  return spawnSync('node', [join(here, 'registry.mjs'), ...args], {
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${fakeDir}:${process.env.PATH}`,
      FAKE_MODE: mode,
      FAKE_COUNT: counter,
      REGISTRY_RETRY_MS: '10',
      ...extra,
    },
  });
}

test('cli prints state=publish once on a 404 without retrying', () => {
  const r = cli('e404');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.stdout.trim().split('\n'), ['state=publish']);
  assert.equal(readFileSync(counter, 'utf8').trim(), '1');
});

test('cli retries a transient error and then prints the state', () => {
  const r = cli('flaky');
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.stdout.trim().split('\n'), ['state=publish']);
  assert.equal(readFileSync(counter, 'utf8').trim(), '3');
});

test('cli exits non-zero with no state when the registry stays unreachable', () => {
  const r = cli('fail');
  assert.notEqual(r.status, 0);
  assert.doesNotMatch(r.stdout, /state=/);
  assert.equal(readFileSync(counter, 'utf8').trim(), '5');
});

test('cli confirm gives up at its deadline while the version stays absent', () => {
  const r = cli('e404', ['confirm', 'pkg', '1.1.0', COMMIT], {
    REGISTRY_CONFIRM_MS: '100',
  });
  assert.notEqual(r.status, 0);
  assert.match(r.stderr, /not.*(visible|published)/i);
});

test('cli rejects unknown usage', () => {
  const r = cli('e404', ['bogus']);
  assert.notEqual(r.status, 0);
  assert.doesNotMatch(r.stdout, /state=/);
});
