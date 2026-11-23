import type { AttributeValue } from './attributeValue';
import { readDocumentJson, writeDocumentJson } from './documentStore';
import { parseUtmParameters } from './generated/coproduct_ffi_uniffi';

const UTM_FILE_NAME = 'coproduct-utm.json';

type UtmFile = {
  firstTouch: Record<string, string>;
  lastTouch: Record<string, string>;
};

// Persists first-touch and last-touch UTM attribution as a small JSON file
// in the documents directory, like sessionStore.ts (see documentStore.ts)
async function readUtmFile(): Promise<UtmFile> {
  return (
    (await readDocumentJson<UtmFile>(UTM_FILE_NAME, 'utm')) ?? {
      firstTouch: {},
      lastTouch: {},
    }
  );
}

async function writeUtmFile(file: UtmFile): Promise<void> {
  await writeDocumentJson(UTM_FILE_NAME, file, 'utm');
}

// Maps a bare UTM key to its last-touch attribute name, e.g.
// utm_source -> utm_source_last
function lastTouchKey(key: string): string {
  return `${key}_last`;
}

// Flattens stored first-touch and last-touch maps into the attribute shape
// the auto-populated layer expects: the bare key for first-touch and the
// `_last`-suffixed key for last-touch. Empty values are omitted so is_set
// stays meaningful on the core side
function flatten(file: UtmFile): Record<string, AttributeValue> {
  const attributes: Record<string, AttributeValue> = {};

  for (const [key, value] of Object.entries(file.firstTouch)) {
    if (value) attributes[key] = value;
  }
  for (const [key, value] of Object.entries(file.lastTouch)) {
    if (value) attributes[lastTouchKey(key)] = value;
  }

  return attributes;
}

/**
 * Parses UTM parameters from a URL and merges them into the persisted
 * attribution record. Last-touch is overwritten on every capture, while
 * first-touch is captured once and frozen thereafter. Returns the flattened
 * attribute map (first-touch keys plus `_last`-suffixed last-touch keys)
 * suitable for folding into auto-populated attributes, including when the
 * parsed URL carries no UTM parameters, in which case the current stored
 * attributes are returned unchanged
 */
export async function captureUtm(
  url: string,
  _now: number = Date.now()
): Promise<Record<string, AttributeValue>> {
  let parsed: Map<string, string> = new Map();

  try {
    parsed = parseUtmParameters(url);
  } catch (error) {
    console.error('[coproduct] failed to parse utm parameters', error);
  }

  const existing = await readUtmFile();

  const parsedEntries = Array.from(parsed.entries()).filter(
    ([, value]) => value
  );
  if (parsedEntries.length === 0) {
    return flatten(existing);
  }

  const firstTouch = { ...existing.firstTouch };
  const lastTouch: Record<string, string> = {};

  for (const [key, value] of parsedEntries) {
    lastTouch[key] = value;
    if (!(key in firstTouch)) {
      firstTouch[key] = value;
    }
  }

  const merged: UtmFile = {
    firstTouch,
    lastTouch: { ...existing.lastTouch, ...lastTouch },
  };

  await writeUtmFile(merged);

  // The returned last-touch reflects only this capture's keys, per the
  // attribution contract, even though the persisted file keeps the latest
  // value for every key ever seen
  return flatten({ firstTouch, lastTouch });
}

/**
 * Reads the persisted UTM attribution without capturing a new URL, returning
 * the flattened attribute map (first-touch plus `_last`-suffixed last-touch).
 * Returns an empty object when nothing has been captured yet. Used by
 * initialize's auto-populated attribute fold so attribution survives a
 * process restart
 */
export async function readUtmAttributes(): Promise<
  Record<string, AttributeValue>
> {
  const file = await readUtmFile();
  return flatten(file);
}
