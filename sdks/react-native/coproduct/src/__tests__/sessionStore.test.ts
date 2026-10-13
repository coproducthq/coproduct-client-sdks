jest.mock('react-native-fs', () => ({
  DocumentDirectoryPath: '/mock-documents',
  exists: jest.fn(),
  readFile: jest.fn(),
  writeFile: jest.fn(),
}));

import RNFS from 'react-native-fs';
import {
  readSessionAttributes,
  resetProcessGuardForTesting,
} from '../sessionStore';

describe('readSessionAttributes', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    resetProcessGuardForTesting();
  });

  it('sets first_seen_at once on first launch and session_count to 1', async () => {
    (RNFS.exists as jest.Mock).mockResolvedValue(false);
    (RNFS.writeFile as jest.Mock).mockResolvedValue(undefined);

    const result = await readSessionAttributes(1_700_000_000_000);

    expect(result.first_seen_at).toBe(1_700_000_000);
    expect(result.session_count).toBe(1);
    expect(RNFS.writeFile).toHaveBeenCalledWith(
      '/mock-documents/coproduct-session.json',
      JSON.stringify({ firstSeenAt: 1_700_000_000, sessionCount: 1 }),
      'utf8'
    );
  });

  it('preserves first_seen_at from an existing file', async () => {
    (RNFS.exists as jest.Mock).mockResolvedValue(true);
    (RNFS.readFile as jest.Mock).mockResolvedValue(
      JSON.stringify({ firstSeenAt: 1_600_000_000, sessionCount: 4 })
    );
    (RNFS.writeFile as jest.Mock).mockResolvedValue(undefined);

    const result = await readSessionAttributes(1_700_000_000_000);

    expect(result.first_seen_at).toBe(1_600_000_000);
    expect(result.session_count).toBe(5);
  });

  it('increments session_count at most once per process', async () => {
    (RNFS.exists as jest.Mock).mockResolvedValue(true);

    // Track the state in the mock to simulate what gets written
    let sessionState = { firstSeenAt: 1_600_000_000, sessionCount: 4 };
    (RNFS.readFile as jest.Mock).mockImplementation(() =>
      Promise.resolve(JSON.stringify(sessionState))
    );
    (RNFS.writeFile as jest.Mock).mockImplementation((_path, data) => {
      sessionState = JSON.parse(data);
      return Promise.resolve(undefined);
    });

    const first = await readSessionAttributes(1_700_000_000_000);
    const second = await readSessionAttributes(1_700_000_000_000);

    expect(first.session_count).toBe(5);
    expect(second.session_count).toBe(5);
  });

  it('falls back to a fresh session when the file read fails', async () => {
    (RNFS.exists as jest.Mock).mockRejectedValue(new Error('disk error'));
    (RNFS.writeFile as jest.Mock).mockResolvedValue(undefined);
    const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {});

    const result = await readSessionAttributes(1_700_000_000_000);

    expect(result.first_seen_at).toBe(1_700_000_000);
    expect(result.session_count).toBe(1);
    expect(errorSpy).toHaveBeenCalled();
    errorSpy.mockRestore();
  });
});
