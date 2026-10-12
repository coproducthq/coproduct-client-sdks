import RNFS from 'react-native-fs';
import type { AttributeValue } from './attributeValue';

const SESSION_FILE_NAME = 'coproduct-session.json';

type SessionFile = {
  firstSeenAt: number;
  sessionCount: number;
};

// One session is one OS process lifetime, so the increment guard is
// process-global rather than per instance: a shutdown plus re-initialize in
// the same process must not count a new session.
let incrementedThisProcess = false;

// Persists first_seen_at/session_count as a small JSON file via the SDK's
// existing react-native-fs dependency, rather than adding a key-value storage
// package for one tiny value. Mirrors SessionStore.swift's UserDefaults
// contract: first_seen_at is set once ever (epoch integer seconds UTC),
// session_count increments at most once per process.
export async function readSessionAttributes(
  now: number = Date.now()
): Promise<Record<string, AttributeValue>> {
  const path = `${RNFS.DocumentDirectoryPath}/${SESSION_FILE_NAME}`;
  let existing: SessionFile | null = null;

  try {
    if (await RNFS.exists(path)) {
      const raw = await RNFS.readFile(path, 'utf8');
      existing = JSON.parse(raw) as SessionFile;
    }
  } catch (error) {
    console.error('[coproduct] failed to read session store', error);
  }

  const firstSeenAt = existing?.firstSeenAt ?? Math.floor(now / 1000);
  let sessionCount = existing?.sessionCount ?? 0;
  if (!incrementedThisProcess) {
    sessionCount += 1;
    incrementedThisProcess = true;
  }

  try {
    const next: SessionFile = { firstSeenAt, sessionCount };
    await RNFS.writeFile(path, JSON.stringify(next), 'utf8');
  } catch (error) {
    console.error('[coproduct] failed to persist session store', error);
  }

  return { first_seen_at: firstSeenAt, session_count: sessionCount };
}

export function resetProcessGuardForTesting(): void {
  incrementedThisProcess = false;
}
