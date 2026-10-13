jest.mock('react-native-permissions', () =>
  // factory runs before this file's own imports.
  require('react-native-permissions/mock')
);

import { request, RESULTS } from 'react-native-permissions/mock';
import { defaultRequestPermission } from '../permissions';

describe('defaultRequestPermission', () => {
  afterEach(() => {
    jest.clearAllMocks();
  });

  it('resolves camera through the platform-specific permission constant', async () => {
    const response = await defaultRequestPermission('camera');
    expect(response.status).toBe(RESULTS.GRANTED);
  });

  it('resolves notifications via requestNotifications, not the generic request call', async () => {
    const response = await defaultRequestPermission('notifications');
    expect(response.status).toBe(RESULTS.GRANTED);
  });

  it('resolves microphone, location, and photos', async () => {
    expect((await defaultRequestPermission('microphone')).status).toBe(
      RESULTS.GRANTED
    );
    expect((await defaultRequestPermission('location')).status).toBe(
      RESULTS.GRANTED
    );
    expect((await defaultRequestPermission('photos')).status).toBe(
      RESULTS.GRANTED
    );
  });

  it('returns status:error for an unrecognized permission name', async () => {
    const response = await defaultRequestPermission('bluetooth');
    expect(response.status).toBe('error');
    expect(response.message).toContain('Unknown permission "bluetooth"');
  });

  it('propagates a non-granted result from the underlying request call', async () => {
    (request as jest.Mock).mockResolvedValueOnce(RESULTS.DENIED);
    const response = await defaultRequestPermission('camera');
    expect(response.status).toBe(RESULTS.DENIED);
  });
});
