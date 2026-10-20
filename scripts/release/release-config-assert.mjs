#!/usr/bin/env node
// Reads a release-please dry run and checks that each proposed release PR
// updates every file a bump must touch
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

export function assertDryRun(output, config, manifestPath) {
  const opened = output.match(/Would open (\d+) pull requests/);
  if (!opened) return ['could not read the dry run: no "Would open" line. Read the release-please output above.'];
  if (opened[1] === '0') return [];

  const updated = new Set(
    [...output.matchAll(/^\s+(\S+):\s+\[class /gm)].map((m) => m[1])
  );
  const problems = [];
  for (const [path, pkg] of Object.entries(config.packages ?? {})) {
    const sdk = pkg.component ?? path;
    if (!new RegExp(`^title: .*release ${sdk} `, 'm').test(output)) continue;
    const expected = [join(path, 'CHANGELOG.md'), manifestPath];
    if (pkg['release-type'] === 'node') expected.push(join(path, 'package.json'));
    for (const extra of pkg['extra-files'] ?? []) {
      expected.push(join(path, typeof extra === 'string' ? extra : extra.path));
    }
    for (const file of expected) {
      if (!updated.has(file)) {
        problems.push(`${sdk}: the release PR would not update ${file}. Fix the path in .github/release-please-config.json.`);
      }
    }
  }
  return problems;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [outputFile, configFile, manifestPath] = process.argv.slice(2);
  const output = readFileSync(outputFile, 'utf8');
  const problems = assertDryRun(output, JSON.parse(readFileSync(configFile, 'utf8')), manifestPath);
  if (problems.length > 0) {
    console.error('Release config failed:');
    for (const problem of problems) console.error(`- ${problem}`);
    process.exit(1);
  }
  console.log(
    /Would open 0 pull requests/.test(output)
      ? 'Release config: loaded. Nothing is releasable on this branch, so no bump was checked.'
      : 'Release config: every proposed release PR updates its full file set'
  );
}
