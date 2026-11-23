import type { AttributeValue } from './attributeValue';
import { readDocumentJson, writeDocumentJson } from './documentStore';

const SESSION_FILE_NAME = 'coproduct-session.json';

type SessionFile = {
  firstSeenAt: number;
  sessionCount: number;
};

// One session is one OS process lifetime, so the increment guard is
// process-global rather than per instance: a shutdown plus re-initialize in
// the same process must not count a new session.
let incrementedThisProcess = false;

// Persists first_seen_at/session_count as a small JSON file in the documents
// directory (see documentStore.ts). Mirrors SessionStore.swift's UserDefaults
// contract: first_seen_at is set once ever (epoch integer seconds UTC),
// session_count increments at most once per process.
export async function readSessionAttributes(
  now: number = Date.now()
): Promise<Record<string, AttributeValue>> {
  const existing = await readDocumentJson<SessionFile>(
    SESSION_FILE_NAME,
    'session'
  );

  const firstSeenAt = existing?.firstSeenAt ?? Math.floor(now / 1000);
  let sessionCount = existing?.sessionCount ?? 0;
  if (!incrementedThisProcess) {
    sessionCount += 1;
    incrementedThisProcess = true;
  }

  const next: SessionFile = { firstSeenAt, sessionCount };
  await writeDocumentJson(SESSION_FILE_NAME, next, 'session');

  return { first_seen_at: firstSeenAt, session_count: sessionCount };
}

export function resetProcessGuardForTesting(): void {
  incrementedThisProcess = false;
}
