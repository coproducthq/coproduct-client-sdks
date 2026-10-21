#!/usr/bin/env node
// Decides what the summary job does to the draft release once the run is
// over. A wrong mark puts a false public label on a release, so every
// uncertainty resolves to doing nothing
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { npmPresence } from './registry.mjs';

const BUILD_JOBS = [
  'resolve',
  'mode',
  'native-ios',
  'native-android',
  'pack',
  'build-ios',
  'build-android',
  'no-iap-android',
];
const CHECKS = 3;

/**
 * Returns 'mark-not-published' or 'none'. npmChecks holds one of
 * 'absent', 'present', or 'error' per registry check
 */
export function finalizeAction({ mode, needs, npmChecks }) {
  if (mode !== 'release') return 'none';
  if (needs?.publish?.result !== 'skipped') return 'none';
  const buildBroke = BUILD_JOBS.some((job) => ['failure', 'cancelled'].includes(needs?.[job]?.result));
  if (!buildBroke) return 'none';
  if (!Array.isArray(npmChecks) || npmChecks.length !== CHECKS) return 'none';
  return npmChecks.every((check) => check === 'absent') ? 'mark-not-published' : 'none';
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const checkMs = () => Number(process.env.FINALIZE_CHECK_MS ?? 20000);

// Values can carry newlines, and each output line is read as key=value
const clean = (text) => String(text).replace(/[\x00-\x1f\x7f]/g, ' ');

function parseNeeds(raw) {
  try {
    const needs = JSON.parse(raw ?? '');
    return needs !== null && typeof needs === 'object' && !Array.isArray(needs) ? needs : null;
  } catch {
    return null;
  }
}

async function decide(env) {
  const needs = parseNeeds(env.NEEDS);
  if (!needs) {
    console.error('warning: NEEDS is missing or unparseable, so nothing will be marked');
    return 'none';
  }
  // Settle the cheap conditions first so npm is only asked when it matters
  const preliminary = finalizeAction({ mode: env.MODE, needs, npmChecks: Array(CHECKS).fill('absent') });
  if (preliminary === 'none') return 'none';
  if (!env.PKG || !env.VERSION) {
    console.error('warning: PKG or VERSION is missing, so nothing will be marked');
    return 'none';
  }
  const npmChecks = [];
  for (let i = 0; i < CHECKS; i++) {
    if (i > 0) await sleep(checkMs());
    npmChecks.push(npmPresence(`${env.PKG}@${env.VERSION}`));
  }
  if (npmChecks.includes('error')) {
    console.error('warning: npm gave an uncertain answer, so nothing will be marked');
  }
  return finalizeAction({ mode: env.MODE, needs, npmChecks });
}

async function main() {
  let action = 'none';
  try {
    action = await decide(process.env);
  } catch (error) {
    console.error(`warning: ${clean(error?.message)}, so nothing will be marked`);
  }
  console.log(`action=${action}`);
}

function isMain() {
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isMain()) await main();
