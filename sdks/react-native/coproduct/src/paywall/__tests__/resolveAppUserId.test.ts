jest.mock('react-native-webview', () => ({ WebView: () => null }));

import { setSharedAnonymousIdSource } from '../../anonymousId';
import {
  MISSING_APP_USER_ID_MESSAGE,
  resolveAppUserId,
} from '../CoproductPaywall';

describe('resolveAppUserId', () => {
  beforeEach(() => jest.spyOn(console, 'error').mockImplementation(() => {}));
  afterEach(() => {
    setSharedAnonymousIdSource(undefined);
    jest.restoreAllMocks();
  });

  it('uses the SDK anonymous id when appUserId is omitted', () => {
    setSharedAnonymousIdSource(() => 'anon-1');
    const onLoadError = jest.fn();

    expect(resolveAppUserId(undefined, onLoadError)).toBe('anon-1');
    expect(onLoadError).not.toHaveBeenCalled();
  });

  it('uses an explicit appUserId over the anonymous id', () => {
    setSharedAnonymousIdSource(() => 'anon-1');

    expect(resolveAppUserId('user-1', jest.fn())).toBe('user-1');
  });

  it('uses an explicit appUserId when the SDK is not initialized', () => {
    const onLoadError = jest.fn();

    expect(resolveAppUserId('user-1', onLoadError)).toBe('user-1');
    expect(onLoadError).not.toHaveBeenCalled();
  });

  it('reports through onLoadError when no id is available', () => {
    const onLoadError = jest.fn();

    expect(resolveAppUserId(undefined, onLoadError)).toBeUndefined();
    expect(onLoadError).toHaveBeenCalledWith({
      message: MISSING_APP_USER_ID_MESSAGE,
    });
    expect(console.error).toHaveBeenCalledWith(MISSING_APP_USER_ID_MESSAGE);
  });

  it('does not throw when no id is available and no onLoadError is passed', () => {
    expect(resolveAppUserId(undefined, undefined)).toBeUndefined();
  });
});
