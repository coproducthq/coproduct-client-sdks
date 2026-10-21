#!/usr/bin/env node
// Decides whether a publish run may release or may only run the checks.
// Only the release automation's own tag, on a release commit whose version
// lines agree, may release. Everything else gets the checks and no publish
import { execFileSync, spawnSync } from 'node:child_process';
import { appendFileSync, realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RELEASE_ACTOR_ID = '345134390';
const TAG = /^react-native-v(\d+\.\d+\.\d+)$/;

/**
 * Returns { mode, version?, reason }. The reason names the first unmet
 * condition, or says why the run may release
 */
export function decideMode({
  actorId,
  refType,
  refName,
  resolvedSha,
  runSha,
  tagCommitSubject,
  identityOk,
}) {
  const checks = (reason) => ({ mode: 'checks', reason });

  if (actorId !== RELEASE_ACTOR_ID) {
    return checks(`the actor ${actorId} is not the release automation, so this run only checks`);
  }
  if (refType !== 'tag') return checks('not a tag, so this run only checks');
  const version = TAG.exec(refName ?? '')?.[1];
  if (!version) {
    return checks(`${refName} is not a react-native-vX.Y.Z tag, so this run only checks`);
  }
  if (resolvedSha !== runSha) {
    return checks(`the tag resolves to ${resolvedSha}, but this run is on ${runSha}, so it only checks`);
  }
  const subject = `chore(main): release react-native ${version}`;
  const isReleaseCommit =
    tagCommitSubject === subject ||
    (tagCommitSubject?.startsWith(`${subject} (#`) && /^ \(#\d+\)$/.test(tagCommitSubject.slice(subject.length)));
  if (!isReleaseCommit) {
    return checks(`the tagged commit is not the release commit for ${version}, so this run only checks`);
  }
  if (identityOk !== true) {
    return checks('the version identity check failed on the tagged commit, so this run only checks');
  }
  return { mode: 'release', version, reason: `release automation tagged ${version} on its release commit` };
}

// Values from the environment can carry newlines, and each output line is
// read as a key=value pair, so control characters never reach stdout
const clean = (text) => String(text).replace(/[\x00-\x1f\x7f]/g, ' ');

function readSubject() {
  try {
    return execFileSync('git', ['log', '-1', '--format=%s'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch {
    return undefined;
  }
}

function decideFromEnvironment() {
  const env = process.env;
  const identity = join(dirname(fileURLToPath(import.meta.url)), '..', 'identity', 'check.mjs');
  const identityOk =
    spawnSync('node', [identity, 'react-native'], { stdio: ['ignore', 2, 2] }).status === 0;
  return decideMode({
    actorId: env.ACTOR_ID,
    refType: env.REF_TYPE,
    refName: env.REF_NAME,
    resolvedSha: env.RESOLVED_SHA,
    runSha: env.RUN_SHA,
    tagCommitSubject: readSubject(),
    identityOk,
  });
}

// Any failure to decide means the run only checks, so it can never release
function main() {
  let decision;
  try {
    decision = decideFromEnvironment();
  } catch (error) {
    decision = { mode: 'checks', reason: `the mode could not be decided (${error.message}), so this run only checks` };
  }
  const { mode, version, reason } = decision;
  console.log(`mode=${mode}`);
  if (version) console.log(`version=${version}`);
  console.log(`reason=${clean(reason)}`);
  if (process.env.GITHUB_STEP_SUMMARY) {
    try {
      appendFileSync(process.env.GITHUB_STEP_SUMMARY, `Run mode: ${mode}. ${clean(reason)}\n`);
    } catch {
      // The summary is a convenience, and the outputs above are what the workflow reads
    }
  }
}

function isMain() {
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isMain()) main();
