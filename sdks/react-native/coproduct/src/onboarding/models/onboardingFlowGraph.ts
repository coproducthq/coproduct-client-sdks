import { parseScreen, type Screen } from './screen';

export interface OnboardingFlowGraph {
  startScreenId: string;
  screens: Screen[];
}

export function parseOnboardingFlowGraph(json: Record<string, unknown>): OnboardingFlowGraph {
  const screens = json.screens as unknown[];
  return {
    startScreenId: json.startScreenId as string,
    screens: screens.map((s) => parseScreen(s as Record<string, unknown>)),
  };
}

export function screenById(graph: OnboardingFlowGraph, id: string): Screen | undefined {
  return graph.screens.find((screen) => screen.id === id);
}
