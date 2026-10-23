import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { finalizeAction } from './finalize.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const fixture = JSON.parse(readFileSync(join(here, 'fixtures', 'pub-coproduct.json'), 'utf8'));
const ABSENT = ['absent', 'absent', 'absent'];

const needsWith = (overrides = {}) => ({
  resolve: { result: 'success' },
  mode: { result: 'success' },
  pipeline: { result: 'failure' },
  'verify-package': { result: 'skipped' },
  publish: { result: 'skipped' },
  ...overrides,
});

const act = (overrides = {}) =>
  finalizeAction({ mode: 'release', needs: needsWith(), pubChecks: ABSENT, ...overrides });

test('marks the release when the pipeline failed, publish was skipped, and pub.dev lacks the version', () => {
  assert.equal(act(), 'mark-not-published');
});

test('marks the release when verify-package failed', () => {
  const needs = needsWith({ pipeline: { result: 'success' }, 'verify-package': { result: 'failure' } });
  assert.equal(act({ needs }), 'mark-not-published');
});

test('marks the release when a build job was abandoned or cancelled', () => {
  for (const [job, result] of [['resolve', 'abandoned'], ['mode', 'cancelled'], ['pipeline', 'cancelled']]) {
    const needs = needsWith({ pipeline: { result: 'success' }, [job]: { result } });
    assert.equal(act({ needs }), 'mark-not-published', `${job} ${result}`);
  }
});

test('ignores jobs that are not Flutter build jobs', () => {
  const needs = needsWith({ pipeline: { result: 'success' }, pack: { result: 'failure' }, 'native-ios': { result: 'failure' } });
  assert.equal(act({ needs }), 'none');
});

test('does nothing when any pub.dev check found the version', () => {
  assert.equal(act({ pubChecks: ['absent', 'present', 'absent'] }), 'none');
});

test('does nothing when any pub.dev check was uncertain', () => {
  assert.equal(act({ pubChecks: ['absent', 'absent', 'error'] }), 'none');
});

test('does nothing without exactly three checks', () => {
  assert.equal(act({ pubChecks: ['absent', 'absent'] }), 'none');
  assert.equal(act({ pubChecks: ['absent', 'absent', 'absent', 'absent'] }), 'none');
  assert.equal(act({ pubChecks: [] }), 'none');
  assert.equal(act({ pubChecks: undefined }), 'none');
});

test('does nothing when publish succeeded and docs failed', () => {
  const needs = needsWith({ pipeline: { result: 'success' }, publish: { result: 'success' }, 'release-docs': { result: 'failure' } });
  assert.equal(act({ needs }), 'none');
});

test('does nothing in checks mode', () => {
  assert.equal(act({ mode: 'checks' }), 'none');
});

test('does nothing when publish failed, as after a rejected approval', () => {
  assert.equal(act({ needs: needsWith({ publish: { result: 'failure' } }) }), 'none');
});

test('does nothing when no build job failed', () => {
  assert.equal(act({ needs: needsWith({ pipeline: { result: 'success' } }) }), 'none');
});

test('does nothing when the publish job is missing from needs', () => {
  const needs = needsWith();
  delete needs.publish;
  assert.equal(act({ needs }), 'none');
});

const without = { ...fixture, versions: fixture.versions.filter((v) => v.version !== '1.2.0') };

// Serves one scripted answer per request to the package API
async function withPub(answers, fn) {
  const seen = [];
  const server = createServer((req, res) => {
    seen.push({ url: req.url, at: Date.now() });
    const { status = 200, body } = answers[Math.min(seen.length, answers.length) - 1];
    res.statusCode = status;
    res.setHeader('content-type', 'application/json');
    res.end(typeof body === 'string' ? body : JSON.stringify(body));
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    return await fn(`http://127.0.0.1:${server.address().port}`, seen);
  } finally {
    server.close();
  }
}

// spawnSync would block the event loop the server needs, so this is async
function cli(base, env = {}) {
  return new Promise((resolve) => {
    const child = spawn('node', [join(here, 'finalize.mjs')], {
      env: {
        ...process.env,
        PUB_BASE_URL: base,
        FINALIZE_CHECK_MS: '50',
        MODE: 'release',
        NEEDS: JSON.stringify(needsWith()),
        PKG: 'coproduct',
        VERSION: '1.2.0',
        ...env,
      },
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => (stdout += d));
    child.stderr.on('data', (d) => (stderr += d));
    child.on('close', (status) => resolve({ status, stdout, stderr }));
  });
}

const actions = (r) => r.stdout.split('\n').filter((line) => line.startsWith('action='));
const ABSENT_ANSWER = { body: without };

test('cli prints mark-not-published after three spaced absent answers', async () => {
  await withPub([ABSENT_ANSWER], async (base, seen) => {
    const r = await cli(base);
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(actions(r), ['action=mark-not-published']);
    assert.equal(seen.length, 3);
    assert.ok(seen.every((s) => s.url === '/api/packages/coproduct'));
    assert.ok(seen[1].at - seen[0].at >= 40, 'the second check waits');
    assert.ok(seen[2].at - seen[1].at >= 40, 'the third check waits');
  });
});

test('cli prints mark-not-published when pub.dev does not know the package', async () => {
  await withPub([{ status: 404, body: '{}' }], async (base) => {
    const r = await cli(base);
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(actions(r), ['action=mark-not-published']);
  });
});

test('cli prints none when one answer finds the version', async () => {
  await withPub([ABSENT_ANSWER, { body: fixture }, ABSENT_ANSWER], async (base, seen) => {
    const r = await cli(base);
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(actions(r), ['action=none']);
    assert.equal(seen.length, 3);
  });
});

test('cli prints none with a warning when one answer is an HTTP error', async () => {
  await withPub([ABSENT_ANSWER, ABSENT_ANSWER, { status: 500, body: '' }], async (base, seen) => {
    const r = await cli(base);
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(actions(r), ['action=none']);
    assert.match(r.stderr, /warning/i);
    assert.equal(seen.length, 3);
  });
});

test('cli prints none for a missing, unparseable, or non-object NEEDS', async () => {
  await withPub([ABSENT_ANSWER], async (base) => {
    for (const NEEDS of ['', 'not json', 'null', '[]', '"x"']) {
      const r = await cli(base, { NEEDS });
      assert.equal(r.status, 0, r.stderr);
      assert.deepEqual(actions(r), ['action=none'], `NEEDS=${NEEDS}`);
    }
  });
});

test('cli prints none without asking pub.dev outside release mode', async () => {
  await withPub([ABSENT_ANSWER], async (base, seen) => {
    const r = await cli(base, { MODE: 'checks' });
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(actions(r), ['action=none']);
    assert.equal(seen.length, 0);
  });
});

test('cli prints none when PKG or VERSION is missing', async () => {
  await withPub([ABSENT_ANSWER], async (base) => {
    for (const env of [{ PKG: '' }, { VERSION: '' }]) {
      const r = await cli(base, env);
      assert.equal(r.status, 0, r.stderr);
      assert.deepEqual(actions(r), ['action=none']);
    }
  });
});
