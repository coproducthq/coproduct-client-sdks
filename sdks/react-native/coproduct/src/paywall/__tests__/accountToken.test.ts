import { accountToken } from '../accountToken';

describe('accountToken', () => {
  it("matches the server's version 5 UUID for a known app user id", () => {
    expect(accountToken('user-123')).toBe(
      'f5765ad4-640f-516d-be70-79ed3a75f5e7'
    );
  });

  it('is stable for one app user id and differs between app user ids', () => {
    expect(accountToken('user-123')).toBe(accountToken('user-123'));
    expect(accountToken('user-124')).not.toBe(accountToken('user-123'));
  });

  it('yields a version 5, RFC 4122 variant UUID for ids longer than one SHA-1 block', () => {
    expect(accountToken('\u7528\u6237-'.repeat(40))).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    );
  });
});
