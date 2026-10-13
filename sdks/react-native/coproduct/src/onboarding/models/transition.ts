import { parseNextTarget, type NextTarget } from './nextTarget';

// A screen's ordered transition: a condition (kept as raw JSON, evaluated
// client-side by the platform script running inside the WebView, never by
// this SDK) and where it leads.
export interface Transition {
  condition: Record<string, unknown>;
  next: NextTarget;
}

export function parseTransition(json: Record<string, unknown>): Transition {
  return {
    condition: json.condition as Record<string, unknown>,
    next: parseNextTarget(json.next as Record<string, unknown>),
  };
}
