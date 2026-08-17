import 'dart:async';

import 'package:coproduct/coproduct.dart';
import 'package:coproduct/src/client_backend.dart';
import 'package:coproduct/src/coproduct_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a caller map mutated after the call does not change the queued identify',
      () async {
    final backend = _CapturingBackend();
    final client = createClientForBackend(backend);

    // Hold the identity queue with an operation that will not settle yet, so the
    // identify below is still queued when the caller mutates its map
    final gate = Completer<void>();
    backend.gate = gate.future;
    unawaited(client.signOut());

    final attributes = <String, AttributeValue>{
      'plan': const AttributeValue.string('pro'),
    };
    final pending = client.identify(userId: 'u1', attributes: attributes);

    attributes['plan'] = const AttributeValue.string('mutated');
    attributes['added'] = const AttributeValue.string('late');

    gate.complete();
    await pending;

    expect(backend.identifyAttributes,
        {'plan': const AttributeValue.string('pro')});
  });

  test('a caller list mutated after the call does not change the queued removal',
      () async {
    final backend = _CapturingBackend();
    final client = createClientForBackend(backend);

    final gate = Completer<void>();
    backend.gate = gate.future;
    unawaited(client.signOut());

    final keys = <String>['plan'];
    final pending = client.removeAttributes(keys);
    keys.add('late');

    gate.complete();
    await pending;

    expect(backend.removedNames, ['plan']);
  });
  test('a caller map mutated after the call does not change the queued setContext',
      () async {
    final backend = _CapturingBackend();
    final client = createClientForBackend(backend);

    final gate = Completer<void>();
    backend.gate = gate.future;
    unawaited(client.signOut());

    final attributes = <String, AttributeValue>{
      'plan': const AttributeValue.string('pro'),
    };
    final pending = client.setContext(targetingKey: 't1', attributes: attributes);
    attributes['plan'] = const AttributeValue.string('mutated');

    gate.complete();
    await pending;

    expect(backend.setContextAttributes,
        {'plan': const AttributeValue.string('pro')});
  });

  test('a caller map mutated after the call does not change the queued update',
      () async {
    final backend = _CapturingBackend();
    final client = createClientForBackend(backend);

    final gate = Completer<void>();
    backend.gate = gate.future;
    unawaited(client.signOut());

    final attributes = <String, AttributeValue>{
      'plan': const AttributeValue.string('pro'),
    };
    final pending = client.updateAttributes(attributes);
    attributes['plan'] = const AttributeValue.string('mutated');

    gate.complete();
    await pending;

    expect(backend.updatedAttributes,
        {'plan': const AttributeValue.string('pro')});
  });
}

final class _CapturingBackend implements CoproductClientBackend {
  Future<void>? gate;
  Map<String, AttributeValue>? identifyAttributes;
  Map<String, AttributeValue>? setContextAttributes;
  Map<String, AttributeValue>? updatedAttributes;
  List<String>? removedNames;

  @override
  Future<void> signOut() async {
    final pending = gate;
    if (pending != null) await pending;
  }

  @override
  Future<void> identify({
    required String userId,
    required Map<String, AttributeValue> attributes,
    required bool linkAnonymous,
  }) async {
    identifyAttributes = Map<String, AttributeValue>.of(attributes);
  }

  @override
  Future<void> setContext({
    required String targetingKey,
    required Map<String, AttributeValue> attributes,
  }) async {
    setContextAttributes = Map<String, AttributeValue>.of(attributes);
  }

  @override
  Future<void> updateAttributes(Map<String, AttributeValue> attributes) async {
    updatedAttributes = Map<String, AttributeValue>.of(attributes);
  }

  @override
  Future<void> removeAttributes(List<String> names) async {
    removedNames = List<String>.of(names);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
