import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { chmodSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';
import { parseSeal, pubPresence, pubState } from './registry.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const fixture = JSON.parse(readFileSync(join(here, 'fixtures', 'pub-coproduct.json'), 'utf8'));
const clone = (value) => JSON.parse(JSON.stringify(value));
const sha = (bytes) => createHash('sha256').update(bytes).digest('hex');

const A = 'a'.repeat(64);
const B = 'b'.repeat(64);
const C = 'c'.repeat(64);

const seal = new Map([
  ['lib/coproduct.dart', { sha256: A, mode: 0o644 }],
  ['ios/Frameworks/CoproductFFI', { sha256: B, mode: 0o755 }],
]);
const archive = () =>
  new Map([
    ['lib/coproduct.dart', { sha256: A, mode: 0o644 }],
    ['ios/Frameworks/CoproductFFI', { sha256: B, mode: 0o755 }],
  ]);

const state = (overrides = {}) =>
  pubState({ pkgJson: fixture, version: '1.2.0', seal, archive: archive(), ...overrides });

test('the fixture is the captured pub.dev answer for the package', () => {
  assert.equal(fixture.name, 'coproduct');
  assert.equal(fixture.latest.version, '1.2.0');
  assert.ok(fixture.versions.some((v) => v.version === '1.2.0' && v.archive_url && v.archive_sha256));
});

test('publishes when the version is absent and latest is lower', () => {
  assert.equal(state({ version: '1.3.0', archive: null }), 'publish');
});

test('publishes when the version is absent and latest is equal', () => {
  const pkgJson = clone(fixture);
  pkgJson.versions = pkgJson.versions.filter((v) => v.version !== '1.2.0');
  assert.equal(state({ pkgJson, archive: null }), 'publish');
});

test('publishes when the package is new to pub.dev', () => {
  assert.equal(state({ pkgJson: null, version: '1.0.0', archive: null }), 'publish');
});

test('compares versions numerically, not as text', () => {
  const pkgJson = clone(fixture);
  pkgJson.latest.version = '1.9.0';
  assert.equal(state({ pkgJson, version: '1.10.0', archive: null }), 'publish');
  pkgJson.latest.version = '1.10.0';
  assert.equal(state({ pkgJson, version: '1.9.0', archive: null }), 'stale');
});

test('is stale when the version is absent and latest is higher', () => {
  assert.equal(state({ version: '1.1.9', archive: null }), 'stale');
});

test('is already published when every file, hash, and mode agrees', () => {
  assert.equal(state(), 'already-published');
});

test('is a mismatch when a hash differs', () => {
  const different = archive();
  different.set('lib/coproduct.dart', { sha256: C, mode: 0o644 });
  assert.equal(state({ archive: different }), 'mismatch');
});

test('is a mismatch when an executable arrives at 644', () => {
  const different = archive();
  different.set('ios/Frameworks/CoproductFFI', { sha256: B, mode: 0o644 });
  assert.equal(state({ archive: different }), 'mismatch');
});

test('is a mismatch when a plain file arrives executable', () => {
  const different = archive();
  different.set('lib/coproduct.dart', { sha256: A, mode: 0o755 });
  assert.equal(state({ archive: different }), 'mismatch');
});

test('compares modes the way pub writes them', () => {
  const sealed = new Map([
    ['lib/coproduct.dart', { sha256: A, mode: 0o600 }],
    ['ios/Frameworks/CoproductFFI', { sha256: B, mode: 0o711 }],
  ]);
  assert.equal(state({ seal: sealed }), 'already-published');
  sealed.set('ios/Frameworks/CoproductFFI', { sha256: B, mode: 0o700 });
  assert.equal(state({ seal: sealed }), 'mismatch');
});

test('is a mismatch when the archive holds an extra file', () => {
  const different = archive();
  different.set('lib/extra.dart', { sha256: C, mode: 0o644 });
  assert.equal(state({ archive: different }), 'mismatch');
});

test('is a mismatch when the archive lacks a sealed file', () => {
  const different = archive();
  different.delete('lib/coproduct.dart');
  assert.equal(state({ archive: different }), 'mismatch');
});

test('is retracted when pub.dev holds the version retracted', () => {
  const pkgJson = clone(fixture);
  pkgJson.versions.find((v) => v.version === '1.2.0').retracted = true;
  assert.equal(state({ pkgJson, archive: null }), 'retracted');
});

test('refuses versions it cannot order', () => {
  const pkgJson = clone(fixture);
  pkgJson.latest.version = '2.0.0-beta.1';
  assert.throws(() => state({ pkgJson, version: '1.3.0', archive: null }), /cannot compare/);
  assert.throws(() => state({ version: 'next', archive: null }), /cannot compare/);
});

test('refuses a present version without its archive', () => {
  assert.throws(() => state({ archive: null }));
});

const sealLine = (hash, size, mode, path) => `${hash}  ${size}  ${mode}  ${path}`;

test('parseSeal reads hash and mode by path', () => {
  const parsed = parseSeal(`${sealLine(A, 10, '644', 'lib/a.dart')}\n${sealLine(B, 20, '755', 'bin/x')}\n`);
  assert.deepEqual([...parsed.keys()], ['lib/a.dart', 'bin/x']);
  assert.deepEqual(parsed.get('lib/a.dart'), { sha256: A, mode: 0o644 });
  assert.deepEqual(parsed.get('bin/x'), { sha256: B, mode: 0o755 });
});

test('parseSeal keeps a path that contains two spaces', () => {
  const parsed = parseSeal(sealLine(A, 10, '644', 'doc/two  spaces.md'));
  assert.deepEqual([...parsed.keys()], ['doc/two  spaces.md']);
});

test('parseSeal refuses malformed lines, duplicates, and an empty seal', () => {
  for (const text of [
    '',
    'nonsense',
    sealLine('xyz', 10, '644', 'a'),
    sealLine(A, 'ten', '644', 'a'),
    sealLine(A, 10, '6x4', 'a'),
    sealLine(A, 10, '644', ''),
    `${sealLine(A, 10, '644', 'a')}\n${sealLine(B, 10, '644', 'a')}`,
  ]) {
    assert.throws(() => parseSeal(text), JSON.stringify(text));
  }
});

// A minimal ustar writer, so every test archive is byte-for-byte what the
// test says and needs no particular tar on the machine
function tarEntry({ name, type = '0', mode = 0o644, body = Buffer.alloc(0), linkname = '' }) {
  const header = Buffer.alloc(512);
  const put = (text, offset, length) => header.write(text, offset, length, 'utf8');
  const octal = (value, length) => `${value.toString(8).padStart(length - 1, '0')}\0`;
  put(name, 0, 100);
  put(octal(mode, 8), 100, 8);
  put(octal(0, 8), 108, 8);
  put(octal(0, 8), 116, 8);
  put(octal(type === '0' ? body.length : 0, 12), 124, 12);
  put(octal(0, 12), 136, 12);
  put('        ', 148, 8);
  put(type, 156, 1);
  put(linkname, 157, 100);
  put('ustar\0', 257, 6);
  put('00', 263, 2);
  put('pub', 265, 32);
  put('pub', 297, 32);
  let sum = 0;
  for (const byte of header) sum += byte;
  put(`${sum.toString(8).padStart(6, '0')}\0 `, 148, 8);
  const padding = Buffer.alloc((512 - (body.length % 512)) % 512);
  return Buffer.concat([header, type === '0' ? body : Buffer.alloc(0), type === '0' ? padding : Buffer.alloc(0)]);
}

const makeArchive = (entries) => gzipSync(Buffer.concat([...entries.map(tarEntry), Buffer.alloc(1024)]));

const FILES = [
  { name: 'pubspec.yaml', body: Buffer.from('name: coproduct\nversion: 1.2.0\n'), mode: 0o644 },
  { name: 'lib/coproduct.dart', body: Buffer.from('library coproduct;\n'), mode: 0o644 },
  { name: 'ios/Frameworks/CoproductFFI', body: Buffer.from('binary'), mode: 0o755 },
];
const GOOD_ENTRIES = [
  { name: 'lib', type: '5', mode: 0o755 },
  { name: 'ios', type: '5', mode: 0o755 },
  { name: 'ios/Frameworks', type: '5', mode: 0o755 },
  ...FILES,
];
const sealFor = (files) =>
  files.map((f) => sealLine(sha(f.body), f.body.length, f.mode.toString(8), f.name)).join('\n') + '\n';

const work = mkdtempSync(join(tmpdir(), 'flutter-registry-'));
const goodSeal = join(work, 'seal.txt');
writeFileSync(goodSeal, sealFor(FILES));

// A tar first on PATH logs every call and runs the real one, so a test can
// see whether extraction ever ran
const realTar = execFileSync('sh', ['-c', 'command -v tar'], { encoding: 'utf8' }).trim();
const fakeDir = mkdtempSync(join(tmpdir(), 'flutter-registry-tar-'));
const tarLog = join(fakeDir, 'log');
writeFileSync(join(fakeDir, 'tar'), `#!/bin/sh\necho "$*" >> "${tarLog}"\nexec "${realTar}" "$@"\n`);
chmodSync(join(fakeDir, 'tar'), 0o755);

function pkgJsonFor(base, versions) {
  return {
    name: 'coproduct',
    latest: { version: versions.at(-1).version },
    versions: versions.map(({ version, bytes, retracted, archiveSha }) => ({
      version,
      archive_url: `${base}/api/archives/coproduct-${version}.tar.gz`,
      archive_sha256: archiveSha ?? sha(bytes),
      pubspec: { name: 'coproduct', version },
      published: '2026-10-21T00:00:00.000Z',
      ...(retracted ? { retracted: true } : {}),
    })),
  };
}

// Serves a package answer and its archives. answer is called per request to
// the package API, so a test can vary it across calls
async function withPub({ answer, archives = {} }, fn) {
  const counts = { api: 0, archive: 0 };
  const server = createServer((req, res) => {
    const base = `http://127.0.0.1:${server.address().port}`;
    const archiveMatch = /^\/api\/archives\/coproduct-(.+)\.tar\.gz$/.exec(req.url);
    if (archiveMatch) {
      counts.archive++;
      const bytes = archives[archiveMatch[1]];
      res.statusCode = bytes ? 200 : 404;
      res.end(bytes ?? '');
      return;
    }
    if (req.url === '/api/packages/coproduct') {
      counts.api++;
      const { status = 200, body } = answer(base, counts.api);
      res.statusCode = status;
      res.setHeader('content-type', 'application/json');
      res.end(typeof body === 'string' ? body : JSON.stringify(body));
      return;
    }
    res.statusCode = 404;
    res.end();
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    return await fn(`http://127.0.0.1:${server.address().port}`, counts);
  } finally {
    server.close();
  }
}

// spawnSync would block the event loop the server needs, so this is async
function cli(base, args, extra = {}) {
  writeFileSync(tarLog, '');
  return new Promise((resolve) => {
    const started = Date.now();
    const child = spawn('node', [join(here, 'registry.mjs'), ...args], {
      env: {
        ...process.env,
        PATH: `${fakeDir}:${process.env.PATH}`,
        PUB_BASE_URL: base,
        REGISTRY_RETRY_MS: '10',
        ...extra,
      },
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => (stdout += d));
    child.stderr.on('data', (d) => (stderr += d));
    child.on('close', (status) => resolve({ status, stdout, stderr, ms: Date.now() - started }));
  });
}

const extractions = () => readFileSync(tarLog, 'utf8').split('\n').filter((line) => /^-x/.test(line));
const STATE = (version = '1.2.0', sealPath = goodSeal) => ['state', 'coproduct', version, sealPath];

test('cli prints already-published when the served archive matches the seal', async () => {
  const bytes = makeArchive(GOOD_ENTRIES);
  await withPub(
    { answer: (base) => ({ body: pkgJsonFor(base, [{ version: '1.2.0', bytes }]) }), archives: { '1.2.0': bytes } },
    async (base) => {
      const r = await cli(base, STATE());
      assert.equal(r.status, 0, r.stderr);
      assert.deepEqual(r.stdout.trim().split('\n'), ['state=already-published']);
      assert.equal(extractions().length, 1);
    },
  );
});

test('cli prints mismatch when a served file differs from the seal', async () => {
  const bytes = makeArchive(GOOD_ENTRIES);
  const altered = FILES.map((f) => (f.name === 'lib/coproduct.dart' ? { ...f, body: Buffer.from('other\n') } : f));
  const sealPath = join(work, 'altered-seal.txt');
  writeFileSync(sealPath, sealFor(altered));
  await withPub(
    { answer: (base) => ({ body: pkgJsonFor(base, [{ version: '1.2.0', bytes }]) }), archives: { '1.2.0': bytes } },
    async (base) => {
      const r = await cli(base, STATE('1.2.0', sealPath));
      assert.equal(r.status, 0, r.stderr);
      assert.deepEqual(r.stdout.trim().split('\n'), ['state=mismatch']);
    },
  );
});

test('cli prints publish and stale for an absent version without downloading', async () => {
  const bytes = makeArchive(GOOD_ENTRIES);
  await withPub(
    { answer: (base) => ({ body: pkgJsonFor(base, [{ version: '1.2.0', bytes }]) }), archives: { '1.2.0': bytes } },
    async (base, counts) => {
      const publish = await cli(base, STATE('1.3.0'));
      assert.equal(publish.status, 0, publish.stderr);
      assert.deepEqual(publish.stdout.trim().split('\n'), ['state=publish']);
      const stale = await cli(base, STATE('1.1.9'));
      assert.equal(stale.status, 0, stale.stderr);
      assert.deepEqual(stale.stdout.trim().split('\n'), ['state=stale']);
      assert.equal(counts.archive, 0);
    },
  );
});

test('cli prints publish when pub.dev does not know the package', async () => {
  await withPub({ answer: () => ({ status: 404, body: '{"error":{"code":"NotFound"}}' }) }, async (base) => {
    const r = await cli(base, STATE());
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(r.stdout.trim().split('\n'), ['state=publish']);
  });
});

test('cli prints retracted for a retracted version without downloading', async () => {
  const bytes = makeArchive(GOOD_ENTRIES);
  await withPub(
    {
      answer: (base) => ({ body: pkgJsonFor(base, [{ version: '1.2.0', bytes, retracted: true }]) }),
      archives: { '1.2.0': bytes },
    },
    async (base, counts) => {
      const r = await cli(base, STATE());
      assert.equal(r.status, 0, r.stderr);
      assert.deepEqual(r.stdout.trim().split('\n'), ['state=retracted']);
      assert.equal(counts.archive, 0);
    },
  );
});

test('cli retries a server error and then prints no state', async () => {
  await withPub({ answer: () => ({ status: 500, body: 'oops' }) }, async (base, counts) => {
    const r = await cli(base, STATE());
    assert.notEqual(r.status, 0);
    assert.doesNotMatch(r.stdout, /state=/);
    assert.equal(counts.api, 5);
  });
});

test('cli recovers from a transient server error', async () => {
  const bytes = makeArchive(GOOD_ENTRIES);
  await withPub(
    {
      answer: (base, n) => (n <= 2 ? { status: 503, body: '' } : { body: pkgJsonFor(base, [{ version: '1.2.0', bytes }]) }),
      archives: { '1.2.0': bytes },
    },
    async (base) => {
      const r = await cli(base, STATE());
      assert.equal(r.status, 0, r.stderr);
      assert.deepEqual(r.stdout.trim().split('\n'), ['state=already-published']);
    },
  );
});

test('cli prints no state for an answer that is not JSON', async () => {
  await withPub({ answer: () => ({ body: '<html>maintenance</html>' }) }, async (base) => {
    const r = await cli(base, STATE());
    assert.notEqual(r.status, 0);
    assert.doesNotMatch(r.stdout, /state=/);
  });
});

test('cli prints no state for JSON that is not a package answer', async () => {
  for (const body of ['null', '[]', '{"name":"coproduct"}', '{"name":"coproduct","versions":{}}']) {
    await withPub({ answer: () => ({ body }) }, async (base) => {
      const r = await cli(base, STATE());
      assert.notEqual(r.status, 0, body);
      assert.doesNotMatch(r.stdout, /state=/, body);
    });
  }
});

test('cli prints no state when a present version archive cannot be fetched', async () => {
  const bytes = makeArchive(GOOD_ENTRIES);
  await withPub(
    { answer: (base) => ({ body: pkgJsonFor(base, [{ version: '1.2.0', bytes }]) }), archives: {} },
    async (base) => {
      const r = await cli(base, STATE());
      assert.notEqual(r.status, 0);
      assert.doesNotMatch(r.stdout, /state=/);
    },
  );
});

test('cli prints no state when the archive disagrees with its published hash', async () => {
  const bytes = makeArchive(GOOD_ENTRIES);
  await withPub(
    {
      answer: (base) => ({ body: pkgJsonFor(base, [{ version: '1.2.0', bytes, archiveSha: 'd'.repeat(64) }]) }),
      archives: { '1.2.0': bytes },
    },
    async (base) => {
      const r = await cli(base, STATE());
      assert.notEqual(r.status, 0);
      assert.doesNotMatch(r.stdout, /state=/);
      assert.equal(extractions().length, 0);
    },
  );
});

async function refuses(entries, pattern) {
  const bytes = makeArchive(entries);
  await withPub(
    { answer: (base) => ({ body: pkgJsonFor(base, [{ version: '1.2.0', bytes }]) }), archives: { '1.2.0': bytes } },
    async (base) => {
      const r = await cli(base, STATE());
      assert.notEqual(r.status, 0);
      assert.doesNotMatch(r.stdout, /state=/);
      assert.match(r.stderr, pattern);
      assert.deepEqual(extractions(), []);
      assert.ok(readFileSync(tarLog, 'utf8').includes('-t'), 'the headers were listed');
    },
  );
}

test('cli refuses an archive holding a symlink and extracts nothing', async () => {
  await refuses([...GOOD_ENTRIES, { name: 'lib/link', type: '2', linkname: '/etc/passwd' }], /lib\/link: symlink/);
});

test('cli refuses an archive holding a parent reference and extracts nothing', async () => {
  await refuses([...GOOD_ENTRIES, { name: '../x', body: Buffer.from('x') }], /\.\.\/x: parent directory reference/);
});

test('cli refuses hard links, absolute paths, and duplicate entries', async () => {
  await refuses([...GOOD_ENTRIES, { name: 'lib/hard', type: '1', linkname: 'pubspec.yaml' }], /hard link/);
  await refuses([...GOOD_ENTRIES, { name: '/tmp/abs', body: Buffer.from('x') }], /absolute path/);
  await refuses([...GOOD_ENTRIES, FILES[1]], /duplicate path/);
});

test('cli refuses a name with a control character', async () => {
  await refuses([...GOOD_ENTRIES, { name: 'lib/a\nb', body: Buffer.from('x') }], /escaped name/);
});

const CONFIRM = ['confirm', 'coproduct', '1.2.0', goodSeal];

test('cli confirm prints the confirmed version when the archive matches', async () => {
  const bytes = makeArchive(GOOD_ENTRIES);
  await withPub(
    { answer: (base) => ({ body: pkgJsonFor(base, [{ version: '1.2.0', bytes }]) }), archives: { '1.2.0': bytes } },
    async (base) => {
      const r = await cli(base, CONFIRM, { REGISTRY_CONFIRM_MS: '5000' });
      assert.equal(r.status, 0, r.stderr);
      assert.deepEqual(r.stdout.trim().split('\n'), ['confirmed=1.2.0']);
    },
  );
});

test('cli confirm waits for the version to appear', async () => {
  const bytes = makeArchive(GOOD_ENTRIES);
  const old = makeArchive(GOOD_ENTRIES);
  await withPub(
    {
      answer: (base, n) => ({
        body: pkgJsonFor(base, n <= 2 ? [{ version: '1.1.0', bytes: old }] : [{ version: '1.1.0', bytes: old }, { version: '1.2.0', bytes }]),
      }),
      archives: { '1.2.0': bytes },
    },
    async (base, counts) => {
      const r = await cli(base, CONFIRM, { REGISTRY_CONFIRM_MS: '5000' });
      assert.equal(r.status, 0, r.stderr);
      assert.deepEqual(r.stdout.trim().split('\n'), ['confirmed=1.2.0']);
      assert.equal(counts.api, 3);
    },
  );
});

test('cli confirm fails at once on a mismatching archive and names the runbook', async () => {
  const bytes = makeArchive(GOOD_ENTRIES.map((e) => (e.name === 'lib/coproduct.dart' ? { ...e, body: Buffer.from('tampered\n') } : e)));
  await withPub(
    { answer: (base) => ({ body: pkgJsonFor(base, [{ version: '1.2.0', bytes }]) }), archives: { '1.2.0': bytes } },
    async (base) => {
      const r = await cli(base, CONFIRM, { REGISTRY_CONFIRM_MS: '3000', REGISTRY_RETRY_MS: '1000' });
      assert.equal(r.status, 1);
      assert.doesNotMatch(r.stdout, /confirmed=/);
      assert.match(r.stderr, /mismatch/);
      assert.match(r.stderr, /bad-version runbook in DEVELOPMENT\.md/);
      assert.ok(r.ms < 2500, `took ${r.ms} ms`);
    },
  );
});

test('cli confirm fails at once on a retracted version and names the runbook', async () => {
  const bytes = makeArchive(GOOD_ENTRIES);
  await withPub(
    {
      answer: (base) => ({ body: pkgJsonFor(base, [{ version: '1.2.0', bytes, retracted: true }]) }),
      archives: { '1.2.0': bytes },
    },
    async (base) => {
      const r = await cli(base, CONFIRM, { REGISTRY_CONFIRM_MS: '3000', REGISTRY_RETRY_MS: '1000' });
      assert.equal(r.status, 1);
      assert.match(r.stderr, /retracted/);
      assert.match(r.stderr, /bad-version runbook in DEVELOPMENT\.md/);
      assert.ok(r.ms < 2500, `took ${r.ms} ms`);
    },
  );
});

test('cli confirm gives up at its deadline while the version stays absent', async () => {
  const old = makeArchive(GOOD_ENTRIES);
  await withPub(
    { answer: (base) => ({ body: pkgJsonFor(base, [{ version: '1.1.0', bytes: old }]) }) },
    async (base) => {
      const r = await cli(base, CONFIRM, { REGISTRY_CONFIRM_MS: '200' });
      assert.equal(r.status, 1);
      assert.doesNotMatch(r.stdout, /confirmed=/);
      assert.match(r.stderr, /not.*in time/);
    },
  );
});

test('cli latest prints pub latest version and nothing else', async () => {
  await withPub({ answer: () => ({ body: fixture }) }, async (base) => {
    const r = await cli(base, ['latest', 'coproduct']);
    assert.equal(r.status, 0, r.stderr);
    assert.equal(r.stdout, '1.2.0\n');
  });
});

test('cli latest fails for an unknown package or an uncertain answer', async () => {
  for (const answer of [() => ({ status: 404, body: '{}' }), () => ({ status: 500, body: '' }), () => ({ body: 'nope' })]) {
    await withPub({ answer }, async (base) => {
      const r = await cli(base, ['latest', 'coproduct']);
      assert.notEqual(r.status, 0);
      assert.equal(r.stdout, '');
    });
  }
});

test('cli rejects unknown usage', async () => {
  for (const args of [['bogus'], ['state', 'coproduct', '1.2.0'], ['latest']]) {
    const r = await cli('http://127.0.0.1:9', args);
    assert.notEqual(r.status, 0, args.join(' '));
    assert.equal(r.stdout, '', args.join(' '));
  }
});

test('cli prints no state for a seal it cannot read', async () => {
  const bytes = makeArchive(GOOD_ENTRIES);
  const broken = join(work, 'broken-seal.txt');
  writeFileSync(broken, 'not a seal\n');
  await withPub(
    { answer: (base) => ({ body: pkgJsonFor(base, [{ version: '1.2.0', bytes }]) }), archives: { '1.2.0': bytes } },
    async (base) => {
      for (const sealPath of [broken, join(work, 'missing-seal.txt')]) {
        const r = await cli(base, STATE('1.2.0', sealPath));
        assert.notEqual(r.status, 0, sealPath);
        assert.doesNotMatch(r.stdout, /state=/);
      }
    },
  );
});

test('cli leaves no extraction directory behind', async () => {
  const bytes = makeArchive(GOOD_ENTRIES);
  const scratch = mkdtempSync(join(tmpdir(), 'flutter-registry-scratch-'));
  await withPub(
    { answer: (base) => ({ body: pkgJsonFor(base, [{ version: '1.2.0', bytes }]) }), archives: { '1.2.0': bytes } },
    async (base) => {
      const r = await cli(base, STATE(), { TMPDIR: scratch });
      assert.equal(r.status, 0, r.stderr);
      assert.deepEqual(readdirSync(scratch), []);
    },
  );
});

async function presenceAgainst(answer) {
  return withPub({ answer }, async (base) => {
    const saved = process.env.PUB_BASE_URL;
    process.env.PUB_BASE_URL = base;
    try {
      return await pubPresence('coproduct', '1.2.0');
    } finally {
      if (saved === undefined) delete process.env.PUB_BASE_URL;
      else process.env.PUB_BASE_URL = saved;
    }
  });
}

test('pubPresence reports present when pub.dev lists the version', async () => {
  assert.equal(await presenceAgainst(() => ({ body: fixture })), 'present');
});

test('pubPresence reports absent when the version or the package is missing', async () => {
  const without = clone(fixture);
  without.versions = without.versions.filter((v) => v.version !== '1.2.0');
  assert.equal(await presenceAgainst(() => ({ body: without })), 'absent');
  assert.equal(await presenceAgainst(() => ({ status: 404, body: '{}' })), 'absent');
});

test('pubPresence reports error for a server error or an unreadable answer', async () => {
  assert.equal(await presenceAgainst(() => ({ status: 500, body: '' })), 'error');
  assert.equal(await presenceAgainst(() => ({ body: 'not json' })), 'error');
  assert.equal(await presenceAgainst(() => ({ body: '{"name":"coproduct"}' })), 'error');
});
