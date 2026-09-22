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
}
