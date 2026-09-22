import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coproduct_onboarding/src/flow_runtime.dart';
import 'package:coproduct_onboarding/src/local_progress_store.dart';
import 'package:coproduct_onboarding/src/models/onboarding_flow_graph.dart';
import 'package:coproduct_onboarding/src/coproduct_client.dart';

class FakeCoproductClient implements CoproductClient {
  final Map<String, String> flags;
  final Map<String, OnboardingFlowGraph> flows;
  FakeCoproductClient({this.flags = const {}, this.flows = const {}});

  @override
  String? resolveStringFlag(String flagKey) => flags[flagKey];

  @override
  Future<OnboardingFlowGraph?> fetchOnboardingFlow(String flowId) async => flows[flowId];

  @override
  Map<String, Object> get sdkContextAttributes => {'platform': 'ios'};

  @override
  Set<String> get sdkContextSegmentKeys => {};

  int refreshCallCount = 0;

  @override
  Future<void> refresh() async {
    refreshCallCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() { SharedPreferences.setMockInitialValues({}); });

  final graph = OnboardingFlowGraph.fromJson({
    'startScreenId': 'welcome',
    'screens': [
      {'id': 'welcome', 'html': '<p>Hi</p>', 'transitions': [], 'defaultNext': {'type': 'complete'}},
    ],
  });

  test('buildShellHtml assembles the graph into a shell document', () {
    final client = FakeCoproductClient(flows: {'f-1': graph});
    final runtime = FlowRuntime(client: client, progressStore: LocalProgressStore());

    final html = runtime.buildShellHtml(graph: graph, flowId: 'f-1');
    expect(html, contains('data-screen-id="welcome"'));
  });

  test('handleNavigationRequest routes a track action to onEvent and returns prevent', () async {
    final events = <String>[];
    final client = FakeCoproductClient(flows: {'f-1': graph});
    final runtime = FlowRuntime(
      client: client,
      progressStore: LocalProgressStore(),
      flowId: 'f-1',
      flowVersion: 1,
      onEvent: (event, screenId, answers) async { events.add(event); },
    );

    final decision = await runtime.handleNavigationRequest(
      'coproduct-action:track?event=screen_viewed&screenId=welcome',
    );

    expect(decision, FlowNavigationDecision.prevent);
    expect(events, ['screen_viewed']);
  });

  test('a track event persists progress before onEvent fires', () async {
    final client = FakeCoproductClient(flows: {'f-1': graph});
    final store = LocalProgressStore();
    var savedBeforeCallback = false;

    final runtime = FlowRuntime(
      client: client,
      progressStore: store,
      flowId: 'f-1',
      flowVersion: 3,
      onEvent: (event, screenId, answers) async {
        final progress = await store.load(flowId: 'f-1');
        savedBeforeCallback = progress != null && progress.screenId == screenId;
      },
    );

    await runtime.handleNavigationRequest('coproduct-action:track?event=screen_viewed&screenId=welcome');
    expect(savedBeforeCallback, isTrue);
  });

  test('handleNavigationRequest routes requestPermission to onRequestPermission', () async {
    String? requestedPermission;
    final client = FakeCoproductClient(flows: {'f-1': graph});
    final runtime = FlowRuntime(
      client: client,
      progressStore: LocalProgressStore(),
      flowId: 'f-1',
      flowVersion: 1,
      onRequestPermission: (permission) async { requestedPermission = permission; },
    );

    await runtime.handleNavigationRequest('coproduct-action:requestPermission?permission=notifications');
    expect(requestedPermission, 'notifications');
  });

  test('handleNavigationRequest allows a non-coproduct-action URL to navigate normally', () async {
    final client = FakeCoproductClient(flows: {'f-1': graph});
    final runtime = FlowRuntime(client: client, progressStore: LocalProgressStore());

    final decision = await runtime.handleNavigationRequest('https://example.com');
    expect(decision, FlowNavigationDecision.navigate);
  });

  test('a request action for requestPermission calls the injected requestPermission function and resolves with its status', () async {
    final client = FakeCoproductClient(flows: {'f-1': graph});
    final resolved = <(String, Map<String, String>)>[];
    final runtime = FlowRuntime(
      client: client,
      progressStore: LocalProgressStore(),
      flowId: 'f-1',
      flowVersion: 1,
      requestPermission: (permission) async {
        expect(permission, 'camera');
        return {'status': 'granted'};
      },
    );
    runtime.attachResolver((requestId, response) async { resolved.add((requestId, response)); });

    final decision = await runtime.handleNavigationRequest(
      'coproduct-action:request?operation=requestPermission&requestId=req-1&param_permission=camera',
    );

    expect(decision, FlowNavigationDecision.prevent);
    await Future<void>.delayed(Duration.zero); // let the detached async work flush
    // Compared field-by-field rather than via `expect(resolved, [(...)])`:
    // record equality falls back to Map's identity-based `==`, so two
    // separately-constructed maps with equal contents never compare equal
    // as record fields even though `equals()` deep-compares a bare Map.
    expect(resolved, hasLength(1));
    expect(resolved.single.$1, 'req-1');
    expect(resolved.single.$2, {'status': 'granted'});
  });

  test('a request action for a custom operation dispatches to onNativeOperation', () async {
    final client = FakeCoproductClient(flows: {'f-1': graph});
    final resolved = <(String, Map<String, String>)>[];
    final runtime = FlowRuntime(
      client: client,
      progressStore: LocalProgressStore(),
      flowId: 'f-1',
      flowVersion: 1,
      onNativeOperation: (operation, params) async {
        expect(operation, 'fetchPlan');
        expect(params, {'goal': 'lose_weight'});
        return {'status': 'ok', 'planName': 'Pro'};
      },
    );
    runtime.attachResolver((requestId, response) async { resolved.add((requestId, response)); });

    await runtime.handleNavigationRequest(
      'coproduct-action:request?operation=fetchPlan&requestId=req-2&param_goal=lose_weight',
    );
    await Future<void>.delayed(Duration.zero);

    expect(resolved, hasLength(1));
    expect(resolved.single.$1, 'req-2');
    expect(resolved.single.$2, {'status': 'ok', 'planName': 'Pro'});
  });

  test('a custom operation with no onNativeOperation registered resolves with a status:error, never hangs', () async {
    final client = FakeCoproductClient(flows: {'f-1': graph});
    final resolved = <(String, Map<String, String>)>[];
    final runtime = FlowRuntime(client: client, progressStore: LocalProgressStore(), flowId: 'f-1', flowVersion: 1);
    runtime.attachResolver((requestId, response) async { resolved.add((requestId, response)); });

    await runtime.handleNavigationRequest('coproduct-action:request?operation=fetchPlan&requestId=req-3');
    await Future<void>.delayed(Duration.zero);

    expect(resolved.single.$1, 'req-3');
    expect(resolved.single.$2['status'], 'error');
  });

  test('onNativeOperation throwing resolves with status:error instead of an uncaught exception', () async {
    final client = FakeCoproductClient(flows: {'f-1': graph});
    final resolved = <(String, Map<String, String>)>[];
    final runtime = FlowRuntime(
      client: client,
      progressStore: LocalProgressStore(),
      flowId: 'f-1',
      flowVersion: 1,
      onNativeOperation: (operation, params) async { throw StateError('boom'); },
    );
    runtime.attachResolver((requestId, response) async { resolved.add((requestId, response)); });

    await runtime.handleNavigationRequest('coproduct-action:request?operation=fetchPlan&requestId=req-4');
    await Future<void>.delayed(Duration.zero);

    expect(resolved.single.$2['status'], 'error');
  });

  test('handleNavigationRequest returns prevent immediately without waiting for a slow operation to finish', () async {
    final client = FakeCoproductClient(flows: {'f-1': graph});
    final completer = Completer<Map<String, String>>();
    final runtime = FlowRuntime(
      client: client,
      progressStore: LocalProgressStore(),
      flowId: 'f-1',
      flowVersion: 1,
      onNativeOperation: (operation, params) => completer.future,
    );
    runtime.attachResolver((requestId, response) async {});

    final decision = await runtime.handleNavigationRequest(
      'coproduct-action:request?operation=fetchPlan&requestId=req-5',
    );

    expect(decision, FlowNavigationDecision.prevent); // returned before completer.complete() below
    completer.complete({'status': 'ok'});
  });
}
