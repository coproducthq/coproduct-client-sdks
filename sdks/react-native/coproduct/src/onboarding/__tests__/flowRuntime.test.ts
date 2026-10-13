jest.mock('@react-native-async-storage/async-storage', () =>
  // (see localProgressStore.test.ts for why this exact subpath)
  require('@react-native-async-storage/async-storage/jest/async-storage-mock')
);
jest.mock('react-native-permissions', () =>
  require('react-native-permissions/mock')
);

import AsyncStorage from '@react-native-async-storage/async-storage';
import { FlowRuntime } from '../flowRuntime';
import { LocalProgressStore } from '../localProgressStore';
import { parseOnboardingFlowGraph } from '../models/onboardingFlowGraph';
import type { CoproductClient } from '../coproductClient';

beforeEach(async () => {
  await AsyncStorage.clear();
});

function fakeClient(overrides: Partial<CoproductClient> = {}): CoproductClient {
  return {
    resolveStringFlag: () => undefined,
    fetchOnboardingFlow: async () => undefined,
    sdkContextAttributes: { platform: 'ios' },
    sdkContextSegmentKeys: new Set(),
    refresh: async () => {},
    ...overrides,
  };
}

const flushMicrotasks = () => new Promise((resolve) => setTimeout(resolve, 0));

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

describe('FlowRuntime', () => {
  it('buildShellHtml assembles the graph into a shell document', () => {
    const runtime = new FlowRuntime({
      client: fakeClient(),
      progressStore: new LocalProgressStore(),
    });

    const html = runtime.buildShellHtml({ graph, flowId: 'f-1' });
    expect(html).toContain('data-screen-id="welcome"');
  });

  it('handleNavigationRequest routes a track action to onEvent and returns prevent', async () => {
    const events: string[] = [];
    const runtime = new FlowRuntime({
      client: fakeClient(),
      progressStore: new LocalProgressStore(),
      flowId: 'f-1',
      flowVersion: 1,
      onEvent: async (event) => {
        events.push(event);
      },
    });

    const decision = await runtime.handleNavigationRequest(
      'coproduct-action:track?event=screen_viewed&screenId=welcome'
    );

    expect(decision).toBe('prevent');
    expect(events).toEqual(['screen_viewed']);
  });

  it('a track event persists progress before onEvent fires', async () => {
    const store = new LocalProgressStore();
    let savedBeforeCallback = false;

    const runtime = new FlowRuntime({
      client: fakeClient(),
      progressStore: store,
      flowId: 'f-1',
      flowVersion: 3,
      onEvent: async (_event, screenId) => {
        const progress = await store.load({ flowId: 'f-1' });
        savedBeforeCallback =
          progress != null && progress.screenId === screenId;
      },
    });

    await runtime.handleNavigationRequest(
      'coproduct-action:track?event=screen_viewed&screenId=welcome'
    );
    expect(savedBeforeCallback).toBe(true);
  });

  it('handleNavigationRequest routes requestPermission to onRequestPermission', async () => {
    let requestedPermission: string | undefined;
    const runtime = new FlowRuntime({
      client: fakeClient(),
      progressStore: new LocalProgressStore(),
      flowId: 'f-1',
      flowVersion: 1,
      onRequestPermission: async (permission) => {
        requestedPermission = permission;
      },
    });

    await runtime.handleNavigationRequest(
      'coproduct-action:requestPermission?permission=notifications'
    );
    expect(requestedPermission).toBe('notifications');
  });

  it('handleNavigationRequest allows a non-coproduct-action URL to navigate normally', async () => {
    const runtime = new FlowRuntime({
      client: fakeClient(),
      progressStore: new LocalProgressStore(),
    });

    const decision = await runtime.handleNavigationRequest(
      'https://example.com'
    );
    expect(decision).toBe('navigate');
  });

  it('a request action for requestPermission calls the injected requestPermission function and resolves with its status', async () => {
    const resolved: Array<[string, Record<string, string>]> = [];
    const runtime = new FlowRuntime({
      client: fakeClient(),
      progressStore: new LocalProgressStore(),
      flowId: 'f-1',
      flowVersion: 1,
      requestPermission: async (permission) => {
        expect(permission).toBe('camera');
        return { status: 'granted' };
      },
    });
    runtime.attachResolver(async (requestId, response) => {
      resolved.push([requestId, response]);
    });

    const decision = await runtime.handleNavigationRequest(
      'coproduct-action:request?operation=requestPermission&requestId=req-1&param_permission=camera'
    );

    expect(decision).toBe('prevent');
    await flushMicrotasks();
    expect(resolved).toHaveLength(1);
    expect(resolved[0]?.[0]).toBe('req-1');
    expect(resolved[0]?.[1]).toEqual({ status: 'granted' });
  });

  it('a request action for a custom operation dispatches to onNativeOperation', async () => {
    const resolved: Array<[string, Record<string, string>]> = [];
    const runtime = new FlowRuntime({
      client: fakeClient(),
      progressStore: new LocalProgressStore(),
      flowId: 'f-1',
      flowVersion: 1,
      onNativeOperation: async (operation, params) => {
        expect(operation).toBe('fetchPlan');
        expect(params).toEqual({ goal: 'lose_weight' });
        return { status: 'ok', planName: 'Pro' };
      },
    });
    runtime.attachResolver(async (requestId, response) => {
      resolved.push([requestId, response]);
    });

    await runtime.handleNavigationRequest(
      'coproduct-action:request?operation=fetchPlan&requestId=req-2&param_goal=lose_weight'
    );
    await flushMicrotasks();

    expect(resolved).toHaveLength(1);
    expect(resolved[0]?.[0]).toBe('req-2');
    expect(resolved[0]?.[1]).toEqual({ status: 'ok', planName: 'Pro' });
  });

  it('a custom operation with no onNativeOperation registered resolves with a status:error, never hangs', async () => {
    const resolved: Array<[string, Record<string, string>]> = [];
    const runtime = new FlowRuntime({
      client: fakeClient(),
      progressStore: new LocalProgressStore(),
      flowId: 'f-1',
      flowVersion: 1,
    });
    runtime.attachResolver(async (requestId, response) => {
      resolved.push([requestId, response]);
    });

    await runtime.handleNavigationRequest(
      'coproduct-action:request?operation=fetchPlan&requestId=req-3'
    );
    await flushMicrotasks();

    expect(resolved[0]?.[0]).toBe('req-3');
    expect(resolved[0]?.[1]?.status).toBe('error');
  });

  it('onNativeOperation throwing resolves with status:error instead of an uncaught exception', async () => {
    const resolved: Array<[string, Record<string, string>]> = [];
    const runtime = new FlowRuntime({
      client: fakeClient(),
      progressStore: new LocalProgressStore(),
      flowId: 'f-1',
      flowVersion: 1,
      onNativeOperation: async () => {
        throw new Error('boom');
      },
    });
    runtime.attachResolver(async (requestId, response) => {
      resolved.push([requestId, response]);
    });

    await runtime.handleNavigationRequest(
      'coproduct-action:request?operation=fetchPlan&requestId=req-4'
    );
    await flushMicrotasks();

    expect(resolved[0]?.[1]?.status).toBe('error');
  });

  it('a throwing injected requestPermission resolves with status:error instead of an uncaught exception', async () => {
    const resolved: Array<[string, Record<string, string>]> = [];
    const runtime = new FlowRuntime({
      client: fakeClient(),
      progressStore: new LocalProgressStore(),
      flowId: 'f-1',
      flowVersion: 1,
      requestPermission: async () => {
        throw new Error('boom');
      },
    });
    runtime.attachResolver(async (requestId, response) => {
      resolved.push([requestId, response]);
    });

    await runtime.handleNavigationRequest(
      'coproduct-action:request?operation=requestPermission&requestId=req-6&param_permission=camera'
    );
    await flushMicrotasks();

    expect(resolved[0]?.[0]).toBe('req-6');
    expect(resolved[0]?.[1]?.status).toBe('error');
    expect(resolved[0]?.[1]?.message).toContain('boom');
  });

  it('handleNavigationRequest returns prevent immediately without waiting for a slow operation to finish', async () => {
    let resolveCompleter: ((value: Record<string, string>) => void) | undefined;
    const completer = new Promise<Record<string, string>>((resolve) => {
      resolveCompleter = resolve;
    });
    const runtime = new FlowRuntime({
      client: fakeClient(),
      progressStore: new LocalProgressStore(),
      flowId: 'f-1',
      flowVersion: 1,
      onNativeOperation: async () => completer,
    });
    runtime.attachResolver(async () => {});

    const decision = await runtime.handleNavigationRequest(
      'coproduct-action:request?operation=fetchPlan&requestId=req-5'
    );

    expect(decision).toBe('prevent'); // returned before resolveCompleter() below
    resolveCompleter?.({ status: 'ok' });
  });
});
