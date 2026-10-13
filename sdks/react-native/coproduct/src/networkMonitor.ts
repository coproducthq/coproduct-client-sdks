import NetInfo, { NetInfoStateType } from '@react-native-community/netinfo';
import type { NetInfoState } from '@react-native-community/netinfo';

// Live network_type classification. Absent until the first reading, then
// republishes on every change, mirroring NetworkMonitor.swift's
// live-fact-not-polled contract. Always emits a value ("none" when
// disconnected, "other" for unrecognized-but-connected types) and
// deduplicates consecutive identical classifications, matching
// NetworkTypeClassifier/deliver() in NetworkMonitor.swift.
export class NetworkMonitor {
  private unsubscribe: (() => void) | null = null;
  private lastReported: string | undefined = undefined;

  constructor(private readonly onChange: (networkType: string) => void) {}

  start(): void {
    this.unsubscribe = NetInfo.addEventListener((state: NetInfoState) => {
      const networkType = classifyNetworkType(state);
      if (networkType !== this.lastReported) {
        this.lastReported = networkType;
        this.onChange(networkType);
      }
    });
  }

  stop(): void {
    this.unsubscribe?.();
    this.unsubscribe = null;
  }
}

function classifyNetworkType(state: NetInfoState): string {
  if (state.isConnected === false || state.type === NetInfoStateType.none) {
    return 'none';
  }
  if (state.type === NetInfoStateType.wifi) {
    return 'wifi';
  }
  if (state.type === NetInfoStateType.cellular) {
    return 'cellular';
  }
  if (state.type === NetInfoStateType.ethernet) {
    return 'ethernet';
  }
  return 'other';
}
