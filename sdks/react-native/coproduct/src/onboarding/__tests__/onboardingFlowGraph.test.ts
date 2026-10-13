import {
  parseOnboardingFlowGraph,
  screenById,
} from '../models/onboardingFlowGraph';

describe('parseOnboardingFlowGraph', () => {
  it('parses a minimal one-screen graph from wire JSON', () => {
    const graph = parseOnboardingFlowGraph({
      startScreenId: 'welcome',
      screens: [
        {
          id: 'welcome',
          html: '<p>Hi</p>',
          transitions: [],
          defaultNext: { type: 'complete' },
        },
      ],
    });

    expect(graph.startScreenId).toBe('welcome');
    expect(graph.screens).toHaveLength(1);
    expect(graph.screens[0]?.id).toBe('welcome');
    expect(graph.screens[0]?.defaultNext).toEqual({ type: 'complete' });
  });

  it('parses a transition with an answer condition, keeping it as raw JSON', () => {
    const graph = parseOnboardingFlowGraph({
      startScreenId: 'goal',
      screens: [
        {
          id: 'goal',
          html: '<p>?</p>',
          transitions: [
            {
              condition: {
                type: 'answer',
                questionKey: 'goal',
                operator: 'equals',
                values: ['lose_weight'],
              },
              next: { type: 'screen', screenId: 's3a' },
            },
          ],
          defaultNext: { type: 'complete' },
        },
      ],
    });

    const transition = graph.screens[0]?.transitions[0];
    expect(transition?.condition.type).toBe('answer');
    expect(transition?.next).toEqual({ type: 'screen', screenId: 's3a' });
  });

  it('screenById finds a screen by id and returns undefined otherwise', () => {
    const graph = parseOnboardingFlowGraph({
      startScreenId: 'welcome',
      screens: [
        {
          id: 'welcome',
          html: '<p>Hi</p>',
          transitions: [],
          defaultNext: { type: 'complete' },
        },
      ],
    });

    expect(screenById(graph, 'welcome')?.id).toBe('welcome');
    expect(screenById(graph, 'missing')).toBeUndefined();
  });
});
