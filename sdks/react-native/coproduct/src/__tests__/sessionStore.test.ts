jest.mock('../NativeCoproductStorage', () => ({
  __esModule: true,
  default: {
    readDocumentFile: jest.fn(),
    writeDocumentFile: jest.fn(),
  },
}));

import NativeCoproductStorage from '../NativeCoproductStorage';
import {
  readSessionAttributes,
  resetProcessGuardForTesting,
} from '../sessionStore';

const native = NativeCoproductStorage as unknown as {
  readDocumentFile: jest.Mock;
  writeDocumentFile: jest.Mock;
};

describe('readSessionAttributes', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    resetProcessGuardForTesting();
  });

  it('sets first_seen_at once on first launch and session_count to 1', async () => {
    native.readDocumentFile.mockReturnValue(null);
    native.writeDocumentFile.mockReturnValue(true);

    const result = await readSessionAttributes(1_700_000_000_000);

    expect(result.first_seen_at).toBe(1_700_000_000);
    expect(result.session_count).toBe(1);
    expect(native.readDocumentFile).toHaveBeenCalledWith(
      'coproduct-session.json'
    );
    expect(native.writeDocumentFile).toHaveBeenCalledWith(
      'coproduct-session.json',
      JSON.stringify({ firstSeenAt: 1_700_000_000, sessionCount: 1 })
    );
  });

  it('preserves first_seen_at from an existing file', async () => {
    native.readDocumentFile.mockReturnValue(
      JSON.stringify({ firstSeenAt: 1_600_000_000, sessionCount: 4 })
    );
    native.writeDocumentFile.mockReturnValue(true);

    const result = await readSessionAttributes(1_700_000_000_000);

    expect(result.first_seen_at).toBe(1_600_000_000);
    expect(result.session_count).toBe(5);
  });

  it('increments session_count at most once per process', async () => {
    // Track the state in the mock to simulate what gets written
    let sessionState = JSON.stringify({
      firstSeenAt: 1_600_000_000,
      sessionCount: 4,
    });
    native.readDocumentFile.mockImplementation(() => sessionState);
    native.writeDocumentFile.mockImplementation(
      (_name: string, data: string) => {
        sessionState = data;
        return true;
      }
    );

    const first = await readSessionAttributes(1_700_000_000_000);
    const second = await readSessionAttributes(1_700_000_000_000);

    expect(first.session_count).toBe(5);
    expect(second.session_count).toBe(5);
  });

  it('falls back to a fresh session when the file read fails', async () => {
    native.readDocumentFile.mockImplementation(() => {
      throw new Error('disk error');
    });
    native.writeDocumentFile.mockReturnValue(true);
    const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {});

    const result = await readSessionAttributes(1_700_000_000_000);

    expect(result.first_seen_at).toBe(1_700_000_000);
    expect(result.session_count).toBe(1);
    expect(errorSpy).toHaveBeenCalled();
    errorSpy.mockRestore();
  });

  it('falls back to a fresh session when the file holds invalid JSON', async () => {
    native.readDocumentFile.mockReturnValue('{not json');
    native.writeDocumentFile.mockReturnValue(true);
    const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {});

    const result = await readSessionAttributes(1_700_000_000_000);

    expect(result.session_count).toBe(1);
    expect(errorSpy).toHaveBeenCalled();
    errorSpy.mockRestore();
  });

  it('logs and still returns the attributes when the write fails', async () => {
    native.readDocumentFile.mockReturnValue(null);
    native.writeDocumentFile.mockReturnValue(false);
    const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {});

    const result = await readSessionAttributes(1_700_000_000_000);

    expect(result.session_count).toBe(1);
    expect(errorSpy).toHaveBeenCalledWith(
      '[coproduct] failed to persist session store'
    );
    errorSpy.mockRestore();
  });
});
