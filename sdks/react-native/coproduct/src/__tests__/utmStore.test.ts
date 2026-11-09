jest.mock('react-native-fs', () => ({
  DocumentDirectoryPath: '/mock-documents',
  exists: jest.fn(),
  readFile: jest.fn(),
  writeFile: jest.fn(),
}));

jest.mock('../generated/coproduct_ffi_uniffi', () => ({
  parseUtmParameters: jest.fn(),
}));

import RNFS from 'react-native-fs';
import { parseUtmParameters } from '../generated/coproduct_ffi_uniffi';
import { captureUtm, readUtmAttributes } from '../utmStore';

// In-memory file backing the RNFS mock, keyed to the same path utmStore.ts
// computes, so successive captureUtm/readUtmAttributes calls within a test
// see each other's writes exactly like the real file system would
function useInMemoryFile(): void {
  let stored: string | null = null;

  (RNFS.exists as jest.Mock).mockImplementation(() =>
    Promise.resolve(stored !== null)
  );
  (RNFS.readFile as jest.Mock).mockImplementation(() =>
    Promise.resolve(stored ?? '')
  );
  (RNFS.writeFile as jest.Mock).mockImplementation((_path, data) => {
    stored = data;
    return Promise.resolve(undefined);
  });
}

describe('captureUtm', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    useInMemoryFile();
  });

  it('sets first-touch and last-touch for each parsed key on first capture', async () => {
    (parseUtmParameters as jest.Mock).mockReturnValue(
      new Map(
        Object.entries({
          utm_source: 'google',
          utm_medium: 'cpc',
        })
      )
    );

    const attrs = await captureUtm(
      'https://example.com?utm_source=google&utm_medium=cpc'
    );

    expect(attrs).toEqual({
      utm_source: 'google',
      utm_medium: 'cpc',
      utm_source_last: 'google',
      utm_medium_last: 'cpc',
    });
  });

  it('overwrites last-touch but freezes first-touch on a later capture with different values', async () => {
    (parseUtmParameters as jest.Mock).mockReturnValue(
      new Map(Object.entries({ utm_source: 'google' }))
    );
    await captureUtm('https://example.com?utm_source=google');

    (parseUtmParameters as jest.Mock).mockReturnValue(
      new Map(Object.entries({ utm_source: 'facebook' }))
    );
    const attrs = await captureUtm('https://example.com?utm_source=facebook');

    expect(attrs.utm_source).toBe('google');
    expect(attrs.utm_source_last).toBe('facebook');
  });

  it('keeps first-touch for a key absent from a later capture, and last-touch reflects only the latest capture keys', async () => {
    (parseUtmParameters as jest.Mock).mockReturnValue(
      new Map(
        Object.entries({
          utm_source: 'google',
          utm_medium: 'cpc',
        })
      )
    );
    await captureUtm('https://example.com?utm_source=google&utm_medium=cpc');

    (parseUtmParameters as jest.Mock).mockReturnValue(
      new Map(Object.entries({ utm_medium: 'email' }))
    );
    const attrs = await captureUtm('https://example.com?utm_medium=email');

    expect(attrs.utm_source).toBe('google');
    expect(attrs.utm_source_last).toBeUndefined();
    expect(attrs.utm_medium).toBe('cpc');
    expect(attrs.utm_medium_last).toBe('email');
  });

  it('makes no changes and returns the current stored attributes when parse is empty', async () => {
    (parseUtmParameters as jest.Mock).mockReturnValue(
      new Map(Object.entries({ utm_source: 'google' }))
    );
    await captureUtm('https://example.com?utm_source=google');
    (RNFS.writeFile as jest.Mock).mockClear();

    (parseUtmParameters as jest.Mock).mockReturnValue(new Map());
    const attrs = await captureUtm('https://example.com/no-utm');

    expect(attrs).toEqual({
      utm_source: 'google',
      utm_source_last: 'google',
    });
    expect(RNFS.writeFile).not.toHaveBeenCalled();
  });

  it('omits empty values from the flattened result', async () => {
    (parseUtmParameters as jest.Mock).mockReturnValue(
      new Map(
        Object.entries({
          utm_source: 'google',
          utm_medium: '',
        })
      )
    );

    const attrs = await captureUtm(
      'https://example.com?utm_source=google&utm_medium='
    );

    expect(attrs).toEqual({
      utm_source: 'google',
      utm_source_last: 'google',
    });
  });
});

describe('readUtmAttributes', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    useInMemoryFile();
  });

  it('returns an empty object when nothing has been captured', async () => {
    const attrs = await readUtmAttributes();
    expect(attrs).toEqual({});
  });

  it('returns the persisted flattened set without mutating it', async () => {
    (parseUtmParameters as jest.Mock).mockReturnValue(
      new Map(
        Object.entries({
          utm_source: 'google',
          utm_campaign: 'spring',
        })
      )
    );
    await captureUtm(
      'https://example.com?utm_source=google&utm_campaign=spring'
    );
    (RNFS.writeFile as jest.Mock).mockClear();

    const attrs = await readUtmAttributes();

    expect(attrs).toEqual({
      utm_source: 'google',
      utm_campaign: 'spring',
      utm_source_last: 'google',
      utm_campaign_last: 'spring',
    });
    expect(RNFS.writeFile).not.toHaveBeenCalled();
  });
});
