import { parseNativeOnLoadRequest, type NativeOnLoadRequest } from './nativeOnLoadRequest';
import { parseNextTarget, type NextTarget } from './nextTarget';
import { parseTransition, type Transition } from './transition';

// A screen's html is a body fragment rendered inside a
// <section data-screen-id="..."> in the assembled shell, not a full
// document. Intentionally narrower than the full wire schema (ZScreen in
// packages/snapshot-spec/src/onboarding-flow.ts) -- `name`, `strings`, and
// `position` are author-tool-only fields the runtime never reads, matching
// Flutter's Screen model (screen.dart), which also omits them.
export interface Screen {
  id: string;
  html: string;
  transitions: Transition[];
  defaultNext: NextTarget;
  onLoad?: NativeOnLoadRequest;
}

export function parseScreen(json: Record<string, unknown>): Screen {
  const transitions = json.transitions as unknown[];
  return {
    id: json.id as string,
    html: json.html as string,
    transitions: transitions.map((t) => parseTransition(t as Record<string, unknown>)),
    defaultNext: parseNextTarget(json.defaultNext as Record<string, unknown>),
    onLoad: json.onLoad == null ? undefined : parseNativeOnLoadRequest(json.onLoad as Record<string, unknown>),
  };
}
