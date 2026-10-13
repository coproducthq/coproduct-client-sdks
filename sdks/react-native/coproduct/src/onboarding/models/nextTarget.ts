// A screen's resolved next step: another screen, or a terminal action.
// Mirrors ZNextTarget in packages/snapshot-spec/src/onboarding-flow.ts
// (coproduct-platform repo) and Flutter's NextTarget (next_target.dart).
export type NextTarget = { type: 'screen'; screenId: string } | { type: 'dismiss' } | { type: 'complete' };

export function parseNextTarget(json: Record<string, unknown>): NextTarget {
  switch (json.type) {
    case 'screen':
      return { type: 'screen', screenId: json.screenId as string };
    case 'dismiss':
      return { type: 'dismiss' };
    case 'complete':
      return { type: 'complete' };
    default:
      throw new Error(`Unknown NextTarget type: ${String(json.type)}`);
  }
}
