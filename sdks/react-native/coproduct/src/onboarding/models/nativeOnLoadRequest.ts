// A screen's on-load native request: fires the instant the screen becomes
// current, suspending the screen's own reveal until native resolves it.
// Mirrors ZNativeRequest in packages/snapshot-spec/src/onboarding-flow.ts.
export interface NativeOnLoadRequest {
  operation: string;
  params: Record<string, string>;
  resultKey: string;
  timeoutMs: number;
}

export function parseNativeOnLoadRequest(json: Record<string, unknown>): NativeOnLoadRequest {
  return {
    operation: json.operation as string,
    params: json.params as Record<string, string>,
    resultKey: json.resultKey as string,
    timeoutMs: json.timeoutMs as number,
  };
}
