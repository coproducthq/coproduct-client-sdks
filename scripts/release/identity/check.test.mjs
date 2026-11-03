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
  assert.deepEqual(checkIdentity({ root, only: 'ios' }), { checked: [], problems: [] });
});

const FL = 'sdks/flutter/coproduct';
const FL_CONFIG = {
  'release-type': 'dart',
  component: 'flutter',
  'extra-files': [
    { type: 'generic', path: 'lib/src/sdk_version.dart' },
    { type: 'generic', path: 'ios/coproduct.podspec' },
    { type: 'generic', path: 'README.md' },
  ],
};
const README_START = '<!-- x-release-please-start-version -->';
const README_END = '<!-- x-release-please-end -->';

function flutterFixture({
  version = '1.2.0',
  pubspec = version,
  dart = version,
  podspec = version,
  block = ['```yaml', 'dependencies:', `  coproduct: ^${version}`, '```'],
  start = README_START,
  end = README_END,
} = {}) {
  const { root, write } = fixture();
  write(CONFIG, JSON.stringify({ packages: { [RN]: RN_CONFIG, [FL]: FL_CONFIG } }));
  write(MANIFEST, JSON.stringify({ [RN]: '1.0.2', [FL]: version }));
  write(`${FL}/pubspec.yaml`, `name: coproduct\nversion: ${pubspec}\n`);
  write(`${FL}/lib/src/sdk_version.dart`, `const _v = '${dart}'; // x-release-please-version\n`);
  write(`${FL}/ios/coproduct.podspec`, `  s.version          = '${podspec}' # x-release-please-version\n`);
  write(`${FL}/README.md`, ['# Coproduct', start, ...block, end, ''].filter((l) => l !== null).join('\n'));
  return { root, write };
}

const flutterProblems = (options) => problems(flutterFixture(options).root, { only: 'flutter' });

test('checks Flutter when it is in the release config', () => {
  const { root } = flutterFixture();
  assert.deepEqual(checkIdentity({ root, only: 'flutter' }), {
    checked: [{ sdk: 'flutter', version: '1.2.0' }],
    problems: [],
  });
});

test('names pubspec.yaml when its version disagrees with the manifest', () => {
  assert.match(flutterProblems({ pubspec: '1.2.1' })[0], /pubspec\.yaml has 1\.2\.1, but the manifest has 1\.2\.0/);
});

test('names the Dart version file when its marked line disagrees', () => {
  assert.match(flutterProblems({ dart: '1.1.0' })[0], /sdk_version\.dart:1 has 1\.1\.0, but the manifest has 1\.2\.0/);
});

test('names the podspec when its marked line disagrees', () => {
  assert.match(flutterProblems({ podspec: '1.1.0' })[0], /coproduct\.podspec:1 has 1\.1\.0, but the manifest has 1\.2\.0/);
});

test('names the README when its version block disagrees', () => {
  const [problem] = flutterProblems({
    block: ['```yaml', 'dependencies:', '  coproduct: ^1.1.0', '```'],
  });
  assert.match(problem, /README\.md:\d+ has 1\.1\.0, but the manifest has 1\.2\.0/);
});

test('names the README when its version block has no end marker', () => {
  assert.match(flutterProblems({ end: null })[0], /README\.md.*start-version.*x-release-please-end/);
});

test('names the README when its version block has two start markers', () => {
  const [problem] = flutterProblems({ block: [README_START, '  coproduct: ^1.2.0'] });
  assert.match(problem, /README\.md.*exactly one/);
});

test('names the README when its version block has no version line', () => {
  const [problem] = flutterProblems({ block: ['```yaml', 'dependencies:', '```'] });
  assert.match(problem, /README\.md.*exactly one version/);
});

test('names the README when its version block has two version lines', () => {
  const [problem] = flutterProblems({ block: ['  coproduct: ^1.2.0', '  other: 1.2.0'] });
  assert.match(problem, /README\.md.*exactly one version/);
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
