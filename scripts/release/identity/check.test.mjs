import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { checkIdentity, CONFIG, MANIFEST } from './check.mjs';

const RN = 'sdks/react-native/coproduct';
const RN_CONFIG = {
  'release-type': 'node',
  component: 'react-native',
  'extra-files': [{ type: 'generic', path: 'src/index.tsx' }],
};

function fixture({
  version = '1.0.2',
  pkgVersion = version,
  userAgentLine = `const USER_AGENT = 'coproduct-rn/${version}'; // x-release-please-version`,
} = {}) {
  const root = mkdtempSync(join(tmpdir(), 'identity-'));
  const write = (path, text) => {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), text);
  };
  write(CONFIG, JSON.stringify({ packages: { [RN]: RN_CONFIG } }));
  write(MANIFEST, JSON.stringify({ [RN]: version }));
  write(`${RN}/package.json`, JSON.stringify({ name: 'x', version: pkgVersion }));
  write(`${RN}/src/index.tsx`, `import x from 'y';\n${userAgentLine}\n`);
  return { root, write };
}

const problems = (root, options = {}) => checkIdentity({ root, ...options }).problems;

function git(root, ...args) {
  return execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.com', ...args], {
    cwd: root,
    encoding: 'utf8',
  }).trim();
}

test('passes when every version line agrees with the manifest', () => {
  const { root } = fixture();
  assert.deepEqual(problems(root), []);
});

test('fails on a -dev User-Agent and names the line', () => {
  const { root } = fixture({
    userAgentLine: "const USER_AGENT = 'coproduct-rn/0.0.1-dev'; // x-release-please-version",
  });
  const [problem] = problems(root);
  assert.match(problem, /src\/index\.tsx:2 has 0\.0\.1-dev, but the manifest has 1\.0\.2/);
  assert.match(problem, /Never edit version lines by hand/);
});

test('fails when package.json disagrees with the manifest', () => {
  const { root } = fixture({ pkgVersion: '1.0.3' });
  assert.match(problems(root)[0], /package\.json has 1\.0\.3, but the manifest has 1\.0\.2/);
});

test('reports a deleted marker as configuration damage', () => {
  const { root } = fixture({ userAgentLine: "const USER_AGENT = 'coproduct-rn/1.0.2';" });
  assert.match(problems(root)[0], /no x-release-please-version marker\. This is configuration damage/);
});

test('reports a missing extra-file as configuration damage', () => {
  const { root, write } = fixture();
  write(CONFIG, JSON.stringify({
    packages: { [RN]: { ...RN_CONFIG, 'extra-files': [{ type: 'generic', path: 'src/version.ts' }] } },
  }));
  assert.match(problems(root)[0], /src\/version\.ts is listed .* but does not exist\. This is configuration damage/);
});

test('rejects a prerelease version even when every line agrees', () => {
  const { root } = fixture({ version: '1.1.0-dev' });
  assert.match(problems(root)[0], /names 1\.1\.0-dev, which is not a release version/);
});

test('allows refactoring a marked line when the value is unchanged', () => {
  const { root } = fixture({
    userAgentLine: 'export const USER_AGENT = `coproduct-rn/1.0.2`; // x-release-please-version',
  });
  assert.deepEqual(problems(root), []);
});

test('ignores an SDK that is not in the release config', () => {
  const { root } = fixture();
  assert.deepEqual(checkIdentity({ root, only: 'flutter' }), { checked: [], problems: [] });
});

test('only a release PR may change the manifest', () => {
  const { root, write } = fixture();
  git(root, 'init', '-q', '-b', 'main');
  git(root, 'add', '-A');
  git(root, 'commit', '-q', '-m', 'base');
  const base = git(root, 'rev-parse', 'HEAD');
  write(MANIFEST, JSON.stringify({ [RN]: '1.0.3' }));
  write(`${RN}/package.json`, JSON.stringify({ name: 'x', version: '1.0.3' }));
  write(`${RN}/src/index.tsx`, "import x from 'y';\nconst USER_AGENT = 'coproduct-rn/1.0.3'; // x-release-please-version\n");

  assert.match(
    problems(root, { base, branch: 'fix/something' })[0],
    /moves the manifest from 1\.0\.2 to 1\.0\.3\. Only release PRs change versions/
  );
  assert.deepEqual(
    problems(root, { base, branch: 'release-please--branches--main--components--react-native' }),
    []
  );
});

test('tolerates a base that has no manifest yet', () => {
  const { root } = fixture();
  git(root, 'init', '-q', '-b', 'main');
  git(root, 'commit', '-q', '--allow-empty', '-m', 'empty');
  const base = git(root, 'rev-parse', 'HEAD');
  assert.deepEqual(problems(root, { base, branch: 'chore/release-bootstrap' }), []);
});
