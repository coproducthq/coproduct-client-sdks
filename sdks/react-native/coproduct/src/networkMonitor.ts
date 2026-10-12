import NetInfo, { type NetInfoState } from '@react-native-community/netinfo';

// Live network_type classification. Absent until the first reading, then
// republishes on every change, mirroring NetworkMonitor.swift's
// live-fact-not-polled contract. Unrecognized types are omitted rather than
// invented, matching deviceContext.ts's device_type contract.
export class NetworkMonitor {
  private unsubscribe: (() => void) | null = null;

  constructor(private readonly onChange: (networkType: string) => void) {}

  start(): void {
    this.unsubscribe = NetInfo.addEventListener((state: NetInfoState) => {
      const networkType = mapNetworkType(state.type);
      if (networkType) {
        this.onChange(networkType);
      }
    });
  }

  stop(): void {
    this.unsubscribe?.();
    this.unsubscribe = null;
  }
}

function mapNetworkType(type: string): string | undefined {
  switch (type) {
    case 'wifi':
      return 'wifi';
    case 'cellular':
      return 'cellular';
    case 'ethernet':
      return 'ethernet';
    default:
      return undefined;
  }
}
