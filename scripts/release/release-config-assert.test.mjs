import { test } from 'node:test';
import assert from 'node:assert/strict';
import { assertDryRun } from './release-config-assert.mjs';

const config = {
  packages: {
    'sdks/react-native/coproduct': {
      'release-type': 'node',
      component: 'react-native',
      'extra-files': [{ type: 'generic', path: 'src/index.tsx' }],
    },
  },
};
const manifestPath = '.github/.release-please-manifest.json';
const updates = (lines) => `Would open 1 pull requests
fork: false
title: chore(main): release react-native 1.0.3
branch: release-please--branches--main--components--react-native
updates: 8
${lines.map((l) => `  ${l}:  [class X extends DefaultUpdater]`).join('\n')}
`;
const full = [
  'sdks/react-native/coproduct/CHANGELOG.md',
  'sdks/react-native/coproduct/package.json',
  'sdks/react-native/coproduct/src/index.tsx',
  manifestPath,
];

test('passes when the release PR updates every expected file', () => {
  assert.deepEqual(assertDryRun(updates(full), config, manifestPath), []);
});

test('fails when an extra-file is not updated', () => {
  const problems = assertDryRun(updates(full.filter((f) => !f.endsWith('index.tsx'))), config, manifestPath);
  assert.match(problems[0], /react-native: the release PR would not update sdks\/react-native\/coproduct\/src\/index\.tsx/);
});

test('fails when the manifest is not updated', () => {
  const problems = assertDryRun(updates(full.filter((f) => f !== manifestPath)), config, manifestPath);
  assert.match(problems[0], /\.release-please-manifest\.json/);
});

test('passes with a note when nothing is releasable', () => {
  assert.deepEqual(assertDryRun('Would open 0 pull requests\n', config, manifestPath), []);
});

test('fails when release-please proposes no PR list at all', () => {
  assert.match(assertDryRun('something unexpected\n', config, manifestPath)[0], /could not read the dry run/);
});

test('a dart package must update pubspec.yaml', () => {
  const dartConfig = {
    packages: {
      'sdks/flutter/coproduct': {
        'release-type': 'dart',
        component: 'flutter',
        'extra-files': [{ type: 'generic', path: 'README.md' }],
      },
    },
  };
  const out = (lines) =>
    updates(lines).replace('release react-native 1.0.3', 'release flutter 1.2.1');
  const files = [
    'sdks/flutter/coproduct/CHANGELOG.md',
    'sdks/flutter/coproduct/pubspec.yaml',
    'sdks/flutter/coproduct/README.md',
    manifestPath,
  ];
  assert.deepEqual(assertDryRun(out(files), dartConfig, manifestPath), []);
  const problems = assertDryRun(out(files.filter((f) => !f.endsWith('pubspec.yaml'))), dartConfig, manifestPath);
  assert.match(problems[0], /flutter: the release PR would not update sdks\/flutter\/coproduct\/pubspec\.yaml/);
});
