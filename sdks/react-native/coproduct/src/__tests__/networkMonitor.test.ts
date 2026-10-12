const listeners: Array<(state: { type: string }) => void> = [];

jest.mock('@react-native-community/netinfo', () => ({
  __esModule: true,
  default: {
    addEventListener: jest.fn((listener: (state: { type: string }) => void) => {
      listeners.push(listener);
      return jest.fn(() => {
        const index = listeners.indexOf(listener);
        if (index >= 0) listeners.splice(index, 1);
      });
    }),
  },
}));

import { NetworkMonitor } from '../networkMonitor';

describe('NetworkMonitor', () => {
  beforeEach(() => {
    listeners.length = 0;
  });

  it('publishes a mapped network type on change', () => {
    const onChange = jest.fn();
    const monitor = new NetworkMonitor(onChange);

    monitor.start();
    listeners[0]?.({ type: 'wifi' });

    expect(onChange).toHaveBeenCalledWith('wifi');
    monitor.stop();
  });

  it('omits unrecognized types rather than inventing a value', () => {
    const onChange = jest.fn();
    const monitor = new NetworkMonitor(onChange);

    monitor.start();
    listeners[0]?.({ type: 'unknown' });

    expect(onChange).not.toHaveBeenCalled();
    monitor.stop();
  });

  it('stops listening after stop()', () => {
    const onChange = jest.fn();
    const monitor = new NetworkMonitor(onChange);

    monitor.start();
    monitor.stop();

    expect(listeners).toHaveLength(0);
  });
});
