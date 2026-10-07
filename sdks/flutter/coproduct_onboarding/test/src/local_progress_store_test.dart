import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:coproduct_onboarding/src/local_progress_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('round-trips saved progress for a flowId', () async {
    final store = LocalProgressStore();
    await store.save(flowId: 'f-1', version: 2, screenId: 'goal', answers: {'goal': ['lose_weight']});

    final loaded = await store.load(flowId: 'f-1');
    expect(loaded, isNotNull);
    expect(loaded!.version, 2);
    expect(loaded.screenId, 'goal');
    expect(loaded.answers, {'goal': ['lose_weight']});
  });

  test('returns null for a flowId with no saved progress', () async {
    final store = LocalProgressStore();
    expect(await store.load(flowId: 'never-started'), isNull);
  });

  test('keeps two flowIds independent', () async {
    final store = LocalProgressStore();
    await store.save(flowId: 'f-1', version: 1, screenId: 'a', answers: {});
    await store.save(flowId: 'f-2', version: 1, screenId: 'b', answers: {});

    expect((await store.load(flowId: 'f-1'))!.screenId, 'a');
    expect((await store.load(flowId: 'f-2'))!.screenId, 'b');
  });

  test('clear removes saved progress', () async {
    final store = LocalProgressStore();
    await store.save(flowId: 'f-1', version: 1, screenId: 'a', answers: {});
    await store.clear(flowId: 'f-1');
    expect(await store.load(flowId: 'f-1'), isNull);
  });
}
