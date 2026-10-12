const listeners: Array<
  (state: { type: string; isConnected: boolean | null }) => void
> = [];

jest.mock('@react-native-community/netinfo', () => ({
  __esModule: true,
  default: {
    addEventListener: jest.fn(
      (listener: (state: { type: string; isConnected: boolean | null }) => void) => {
        listeners.push(listener);
        return jest.fn(() => {
          const index = listeners.indexOf(listener);
          if (index >= 0) listeners.splice(index, 1);
        });
      }
    ),
  },
  NetInfoStateType: {
    unknown: 'unknown',
    none: 'none',
    cellular: 'cellular',
    wifi: 'wifi',
    bluetooth: 'bluetooth',
    ethernet: 'ethernet',
    wimax: 'wimax',
    vpn: 'vpn',
    other: 'other',
  },
}));

import { NetworkMonitor } from '../networkMonitor';

describe('NetworkMonitor', () => {
  beforeEach(() => {
    listeners.length = 0;
  });

  it('emits "none" when type is none', () => {
    const onChange = jest.fn();
    const monitor = new NetworkMonitor(onChange);

    monitor.start();
    listeners[0]?.({ type: 'none', isConnected: false });

    expect(onChange).toHaveBeenCalledWith('none');
    monitor.stop();
  });

  it('emits "none" when isConnected is false regardless of type', () => {
    const onChange = jest.fn();
    const monitor = new NetworkMonitor(onChange);

    monitor.start();
    listeners[0]?.({ type: 'wifi', isConnected: false });

    expect(onChange).toHaveBeenCalledWith('none');
    monitor.stop();
  });

  it('emits "wifi" for a connected wifi state', () => {
    const onChange = jest.fn();
    const monitor = new NetworkMonitor(onChange);

    monitor.start();
    listeners[0]?.({ type: 'wifi', isConnected: true });

    expect(onChange).toHaveBeenCalledWith('wifi');
    monitor.stop();
  });

  it('emits "cellular" for a connected cellular state', () => {
    const onChange = jest.fn();
    const monitor = new NetworkMonitor(onChange);

    monitor.start();
    listeners[0]?.({ type: 'cellular', isConnected: true });

    expect(onChange).toHaveBeenCalledWith('cellular');
    monitor.stop();
  });

  it('emits "ethernet" for a connected ethernet state', () => {
    const onChange = jest.fn();
    const monitor = new NetworkMonitor(onChange);

    monitor.start();
    listeners[0]?.({ type: 'ethernet', isConnected: true });

    expect(onChange).toHaveBeenCalledWith('ethernet');
    monitor.stop();
  });

  it('emits "other" for an unrecognized but connected type, rather than nothing', () => {
    const onChange = jest.fn();
    const monitor = new NetworkMonitor(onChange);

    monitor.start();
    listeners[0]?.({ type: 'bluetooth', isConnected: true });

    expect(onChange).toHaveBeenCalledWith('other');
    monitor.stop();
  });

  it('dedupes consecutive identical classifications', () => {
    const onChange = jest.fn();
    const monitor = new NetworkMonitor(onChange);

    monitor.start();
    listeners[0]?.({ type: 'wifi', isConnected: true });
    listeners[0]?.({ type: 'wifi', isConnected: true });

    expect(onChange).toHaveBeenCalledTimes(1);
    monitor.stop();
  });

  it('emits again when the classification changes', () => {
    const onChange = jest.fn();
    const monitor = new NetworkMonitor(onChange);

    monitor.start();
    listeners[0]?.({ type: 'wifi', isConnected: true });
    listeners[0]?.({ type: 'cellular', isConnected: true });

    expect(onChange).toHaveBeenCalledTimes(2);
    expect(onChange).toHaveBeenNthCalledWith(1, 'wifi');
    expect(onChange).toHaveBeenNthCalledWith(2, 'cellular');
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
