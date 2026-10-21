#!/usr/bin/env node
// Decides whether a version still needs publishing, and confirms afterwards
// that the registry holds a build whose provenance names the tagged commit.
// Whenever the registry's answer is uncertain, no state is printed
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const SLSA = 'https://slsa.dev/provenance/v1';
const PLAIN = /^(\d+)\.(\d+)\.(\d+)$/;
const RUNBOOK = 'Follow the bad-version runbook in DEVELOPMENT.md';

const parts = (version) => PLAIN.exec(version ?? '')?.slice(1).map(Number);

// Returns a positive number when a is higher than b. Only plain X.Y.Z
// versions are ordered, because a wrong guess here could skip a real release
function compareVersions(a, b) {
  const left = parts(a);
  const right = parts(b);
  if (!left || !right) throw new Error(`cannot compare versions ${a} and ${b}`);
  for (let i = 0; i < 3; i++) {
    if (left[i] !== right[i]) return left[i] - right[i];
  }
  return 0;
}

/**
 * Returns 'publish', 'already-published', 'mismatch', or 'stale'.
 * registryTarballSha is null when the version is absent from the registry
 */
export function publishDecision({ registryTarballSha, artifactSha, version, latest }) {
  if (registryTarballSha !== null) {
    return registryTarballSha === artifactSha ? 'already-published' : 'mismatch';
  }
  // Comparing a version with itself rejects one that is not plain X.Y.Z
  compareVersions(version, version);
  if (latest !== null && compareVersions(latest, version) > 0) return 'stale';
  return 'publish';
}

/** Returns the git commit named by the SLSA provenance, or throws */
export function provenanceCommit(attestationsJson) {
  const attestation = attestationsJson?.attestations?.find((a) => a.predicateType === SLSA);
  const payload = attestation?.bundle?.dsseEnvelope?.payload;
  if (!payload) throw new Error('no SLSA provenance');
  const statement = JSON.parse(Buffer.from(payload, 'base64').toString('utf8'));
  const commit = statement?.predicate?.buildDefinition?.resolvedDependencies?.[0]?.digest?.gitCommit;
  if (typeof commit !== 'string' || commit === '') {
    throw new Error('the SLSA provenance names no source commit');
  }
  return commit;
}

class Absent extends Error {}

// Runs npm view. Returns the parsed value, throws Absent for a 404, and any
// other failure throws a plain Error so callers can retry it
function npmView(spec, field) {
  const args = ['view', spec, ...(field ? [field] : []), '--json'];
  let stdout;
  try {
    stdout = execFileSync('npm', args, {
      encoding: 'utf8',
      timeout: 30000,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (error) {
    const out = `${error.stdout ?? ''}`;
    let code;
    try {
      code = JSON.parse(out)?.error?.code;
    } catch {
      code = /\bE404\b/.test(`${out}${error.stderr ?? ''}`) ? 'E404' : undefined;
    }
    if (code === 'E404') throw new Absent(`${spec} is not in the registry`);
    throw new Error(`npm view ${spec} failed: ${code ?? error.message}`);
  }
  if (stdout.trim() === '') throw new Absent(`${spec} has no ${field ?? 'data'}`);
  return JSON.parse(stdout);
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const retryMs = () => Number(process.env.REGISTRY_RETRY_MS ?? 10000);

async function withRetries(attempts, fn) {
  for (let i = 1; ; i++) {
    try {
      return await fn();
    } catch (error) {
      if (error instanceof Absent || i >= attempts) throw error;
      console.error(`attempt ${i} of ${attempts} failed (${error.message}), retrying`);
      await sleep(retryMs());
    }
  }
}

async function fetchBytes(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(30000) });
  if (response.status === 404) throw new Absent(`${url} is not there yet`);
  if (!response.ok) throw new Error(`fetching ${url} returned ${response.status}`);
  return Buffer.from(await response.arrayBuffer());
}

async function tarballSha(manifest) {
  const url = manifest?.dist?.tarball;
  if (!url) throw new Error('the registry manifest names no tarball');
  return createHash('sha256').update(await fetchBytes(url)).digest('hex');
}

async function state(pkg, version, artifactSha) {
  const registryTarballSha = await withRetries(5, async () => {
    try {
      return await tarballSha(npmView(`${pkg}@${version}`));
    } catch (error) {
      if (error instanceof Absent) return null;
      throw error;
    }
  });
  const latest = await withRetries(5, async () => {
    try {
      return npmView(pkg, 'dist-tags.latest');
    } catch (error) {
      if (error instanceof Absent) return null;
      throw error;
    }
  });
  return publishDecision({ registryTarballSha, artifactSha, version, latest });
}

async function confirm(pkg, version, expectedCommit) {
  const deadline = Date.now() + Number(process.env.REGISTRY_CONFIRM_MS ?? 600000);
  for (;;) {
    try {
      const manifest = npmView(`${pkg}@${version}`);
      const url = manifest?.dist?.attestations?.url;
      if (!url) throw new Absent(`${pkg}@${version} lists no attestations yet`);
      const attestations = JSON.parse((await fetchBytes(url)).toString('utf8'));
      let commit;
      try {
        commit = provenanceCommit(attestations);
      } catch (error) {
        if (error.message !== 'no SLSA provenance') throw error;
        throw new Error(`${pkg}@${version} published without provenance. ${RUNBOOK}`);
      }
      if (commit !== expectedCommit) {
        throw new Error(`provenance names ${commit}, not the tag's ${expectedCommit}. ${RUNBOOK}`);
      }
      return;
    } catch (error) {
      const waiting = error instanceof Absent || /^(npm view|fetching)/.test(error.message);
      if (!waiting) throw error;
      if (Date.now() >= deadline) {
        throw new Error(`${pkg}@${version} was not visible with provenance in time (${error.message})`);
      }
      await sleep(retryMs());
    }
  }
}

// Values can carry newlines, and each output line is read as key=value
const clean = (text) => String(text).replace(/[\x00-\x1f\x7f]/g, ' ');

async function main(argv) {
  const [command, pkg, version, third] = argv;
  if (!pkg || !version || !third || !['state', 'confirm'].includes(command)) {
    throw new Error('usage: registry.mjs state|confirm <pkg> <version> <artifactSha|expectedCommit>');
  }
  if (command === 'state') {
    const result = await state(pkg, version, third);
    console.log(`state=${result}`);
  } else {
    await confirm(pkg, version, third);
    console.log(`confirmed=${version}`);
  }
}

function isMain() {
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isMain()) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(clean(error.message));
    process.exit(1);
  });
}
