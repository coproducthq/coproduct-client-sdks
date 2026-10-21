import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createServer } from 'node:http';
import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { npmPresence, provenanceCommit, publishDecision } from './registry.mjs';

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
  *dist-tags.latest*)
    if [ "$FAKE_LATEST" = "empty" ]; then exit 0; fi
    echo '"1.0.0"'; exit 0 ;;
esac
n=$(cat "$FAKE_COUNT" 2>/dev/null || echo 0)
n=$((n + 1))
echo $n > "$FAKE_COUNT"
if [ "$FAKE_MODE" = "fail" ] || { [ "$FAKE_MODE" = "flaky" ] && [ "$n" -le 2 ]; }; then
  echo 'npm error code ETIMEDOUT' >&2
  exit 1
fi
case "$FAKE_MODE" in
  e500) echo '{"error":{"code":"E500"}}'; exit 1 ;;
  empty) exit 0 ;;
  manifest)
    echo "{\\"dist\\":{\\"tarball\\":\\"$FAKE_TARBALL\\",\\"attestations\\":{\\"url\\":\\"$FAKE_ATT\\"}}}"
    exit 0 ;;
esac
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

// A local server stands in for the registry's tarball and attestation hosts
async function withServer(handler, fn) {
  const server = createServer(handler);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    return await fn(`http://127.0.0.1:${server.address().port}`);
  } finally {
    server.close();
  }
}

// spawnSync would block the event loop the server needs, so this is async
function cliAsync(mode, args, extra) {
  writeFileSync(counter, '0');
  return new Promise((resolve) => {
    const child = spawn('node', [join(here, 'registry.mjs'), ...args], {
      env: {
        ...process.env,
        PATH: `${fakeDir}:${process.env.PATH}`,
        FAKE_MODE: mode,
        FAKE_COUNT: counter,
        REGISTRY_RETRY_MS: '10',
        ...extra,
      },
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => (stdout += d));
    child.stderr.on('data', (d) => (stderr += d));
    child.on('close', (status) => resolve({ status, stdout, stderr }));
  });
}

test('cli never reports absence when the manifest exists but the tarball 404s', async () => {
  await withServer(
    (req, res) => {
      res.statusCode = 404;
      res.end();
    },
    async (base) => {
      const r = await cliAsync('manifest', ['state', 'pkg', '1.1.0', 'abc'], {
        FAKE_TARBALL: `${base}/pkg.tgz`,
        FAKE_ATT: `${base}/att`,
      });
      assert.notEqual(r.status, 0);
      assert.doesNotMatch(r.stdout, /state=/);
    },
  );
});

test('cli treats empty npm output as an error, not absence', () => {
  const r = cli('empty');
  assert.notEqual(r.status, 0);
  assert.doesNotMatch(r.stdout, /state=/);
  assert.equal(readFileSync(counter, 'utf8').trim(), '5');
});

test('cli treats empty latest output as an error, not a new package', () => {
  const r = cli('e404', ['state', 'pkg', '1.1.0', 'abc'], { FAKE_LATEST: 'empty' });
  assert.notEqual(r.status, 0);
  assert.doesNotMatch(r.stdout, /state=/);
});

test('cli retries a server error from npm instead of counting it as absent', () => {
  const r = cli('e500');
  assert.notEqual(r.status, 0);
  assert.doesNotMatch(r.stdout, /state=/);
  assert.equal(readFileSync(counter, 'utf8').trim(), '5');
});

const slsaless = {
  attestations: fixture.attestations.filter((a) => !a.predicateType.includes('slsa')),
};

async function confirmAgainst(body, commit) {
  let result;
  await withServer(
    (req, res) => {
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify(body));
    },
    async (base) => {
      result = await cliAsync('manifest', ['confirm', 'pkg', '1.1.0', commit], {
        FAKE_TARBALL: `${base}/pkg.tgz`,
        FAKE_ATT: `${base}/att`,
        REGISTRY_CONFIRM_MS: '5000',
        REGISTRY_RETRY_MS: '2000',
      });
    },
  );
  return result;
}

test('cli confirm fails at once on a different commit', async () => {
  const started = Date.now();
  const r = await confirmAgainst(fixture, 'f'.repeat(40));
  assert.equal(r.status, 1);
  assert.match(r.stderr, /provenance names 7d2900e/);
  assert.match(r.stderr, /bad-version runbook in DEVELOPMENT\.md/);
  assert.ok(Date.now() - started < 1500);
});

test('cli confirm fails at once on missing SLSA provenance', async () => {
  const started = Date.now();
  const r = await confirmAgainst(slsaless, COMMIT);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /published without provenance/);
  assert.match(r.stderr, /bad-version runbook in DEVELOPMENT\.md/);
  assert.ok(Date.now() - started < 1500);
});

test('cli confirm succeeds when the commit matches', async () => {
  const r = await confirmAgainst(fixture, COMMIT);
  assert.equal(r.status, 0, r.stderr);
});

test('cli confirm points at the runbook when provenance names no commit', async () => {
  const payload = { predicate: { buildDefinition: { resolvedDependencies: [{ digest: {} }] } } };
  const body = {
    attestations: [
      {
        predicateType: 'https://slsa.dev/provenance/v1',
        bundle: { dsseEnvelope: { payload: Buffer.from(JSON.stringify(payload)).toString('base64') } },
      },
    ],
  };
  const r = await confirmAgainst(body, COMMIT);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /names no source commit/);
  assert.match(r.stderr, /bad-version runbook in DEVELOPMENT\.md/);
});

// npmPresence runs the fake npm through the inherited PATH
function presence(mode) {
  const saved = { PATH: process.env.PATH, FAKE_MODE: process.env.FAKE_MODE, FAKE_COUNT: process.env.FAKE_COUNT };
  writeFileSync(counter, '0');
  process.env.PATH = `${fakeDir}:${saved.PATH}`;
  process.env.FAKE_MODE = mode;
  process.env.FAKE_COUNT = counter;
  try {
    return npmPresence('pkg@1.1.0');
  } finally {
    for (const [key, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

test('npmPresence reports absent only for a real 404', () => {
  assert.equal(presence('e404'), 'absent');
});

test('npmPresence reports present when the manifest exists', () => {
  assert.equal(presence('manifest'), 'present');
});

test('npmPresence reports error for a server error, a failure, and empty output', () => {
  assert.equal(presence('e500'), 'error');
  assert.equal(presence('fail'), 'error');
  assert.equal(presence('empty'), 'error');
});
