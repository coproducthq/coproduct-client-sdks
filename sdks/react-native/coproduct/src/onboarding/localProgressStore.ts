import AsyncStorage from '@react-native-async-storage/async-storage';

export interface FlowProgress {
  version: number;
  screenId: string;
  answers: Record<string, string[]>;
}

function key(flowId: string): string {
  return `coproduct_onboarding_progress_${flowId}`;
}

// Persists onboarding progress to local device storage, keyed by flowId, so
// an app crash or restart resumes on the last known screen rather than
// restarting from startScreenId. Mirrors
// sdks/flutter/coproduct/lib/src/onboarding/local_progress_store.dart,
// which uses SharedPreferences for the same purpose; this uses
// @react-native-async-storage/async-storage.
export class LocalProgressStore {
  async save(args: {
    flowId: string;
    version: number;
    screenId: string;
    answers: Record<string, string[]>;
  }): Promise<void> {
    const { flowId, version, screenId, answers } = args;
    await AsyncStorage.setItem(
      key(flowId),
      JSON.stringify({ version, screenId, answers })
    );
  }

  async load(args: { flowId: string }): Promise<FlowProgress | undefined> {
    const raw = await AsyncStorage.getItem(key(args.flowId));
    if (raw == null) return undefined;
    return JSON.parse(raw) as FlowProgress;
  }

  async clear(args: { flowId: string }): Promise<void> {
    await AsyncStorage.removeItem(key(args.flowId));
  }
}
