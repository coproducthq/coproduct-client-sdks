import 'dart:async';

import 'package:coproduct_acceptance/fixture_control.dart';
import 'package:test/test.dart';

FixtureControl control() => FixtureControl(
      buildBody: (version, omitted) =>
          'v=$version omitted=${(omitted.toList()..sort()).join(',')}',
    );

void main() {
  test('an unarmed poll is served without blocking', () async {
    final c = control();
    await c.awaitTurn().timeout(const Duration(seconds: 1));
    expect(c.state, FixtureState.idle);
    expect(c.servedPolls, 1);
  });

  test('arming blocks the next poll until it is released', () async {
    final c = control();
    c.armBlockNextPoll();
    expect(c.state, FixtureState.armed);

    var served = false;
    final turn = c.awaitTurn().then((_) => served = true);
    // Let the microtask queue drain so the handler has reached the gate
    await Future<void>.delayed(Duration.zero);
    expect(c.state, FixtureState.blocked,
        reason: 'the poll arrived and is being held');
    expect(served, isFalse, reason: 'the response must not complete yet');
    expect(c.servedPolls, 0, reason: 'a held poll has not been served');

    c.release();
    await turn.timeout(const Duration(seconds: 1));
    expect(served, isTrue);
    expect(c.state, FixtureState.idle);
    expect(c.servedPolls, 1);
  });

  test('only the armed poll is held, the one after it is served', () async {
    final c = control();
    c.armBlockNextPoll();
    final held = c.awaitTurn();
    await Future<void>.delayed(Duration.zero);
    c.release();
    await held.timeout(const Duration(seconds: 1));

    await c.awaitTurn().timeout(const Duration(seconds: 1));
    expect(c.servedPolls, 2);
    expect(c.state, FixtureState.idle);
  });

  test('arming twice is rejected', () {
    final c = control();
    c.armBlockNextPoll();
    expect(c.armBlockNextPoll, throwsA(isA<FixtureControlError>()));
  });

  test('releasing when nothing is held is rejected', () {
    final c = control();
    expect(c.release, throwsA(isA<FixtureControlError>()));
    c.armBlockNextPoll();
    expect(c.release, throwsA(isA<FixtureControlError>()),
        reason: 'armed is not yet blocked, there is no response to complete');
  });

  test('setting the active snapshot bumps the version and omits flags', () {
    final c = control();
    expect(c.snapshotVersion, 1);
    expect(c.body, 'v=1 omitted=');

    c.setActiveSnapshot({'fetch-control'});
    expect(c.snapshotVersion, 2,
        reason: 'a new version makes the swap a real change for the core');
    expect(c.omittedFlags, {'fetch-control'});
    expect(c.body, 'v=2 omitted=fetch-control');

    c.setActiveSnapshot(const {});
    expect(c.snapshotVersion, 3);
    expect(c.body, 'v=3 omitted=');
  });

  test('the active snapshot can be changed while a poll is held', () async {
    // The device test arms, changes the snapshot, then releases, so the held
    // response must serve the snapshot chosen after it was blocked
    final c = control();
    c.armBlockNextPoll();
    final held = c.awaitTurn();
    await Future<void>.delayed(Duration.zero);
    c.setActiveSnapshot({'fetch-control'});
    c.release();
    await held.timeout(const Duration(seconds: 1));
    expect(c.body, 'v=2 omitted=fetch-control');
  });

  test('teardown completes an outstanding response', () async {
    final c = control();
    c.armBlockNextPoll();
    var served = false;
    final held = c.awaitTurn().then((_) => served = true);
    await Future<void>.delayed(Duration.zero);
    expect(served, isFalse);

    c.completeOutstanding();
    await held.timeout(const Duration(seconds: 1),
        onTimeout: () => fail('teardown left a client hanging'));
    expect(served, isTrue);
    expect(c.state, FixtureState.idle);
  });

  test('reset releases a held poll and restores the full snapshot', () async {
    final c = control();
    c.setActiveSnapshot({'fetch-control'});
    c.armBlockNextPoll();
    var served = false;
    final held = c.awaitTurn().then((_) => served = true);
    await Future<void>.delayed(Duration.zero);

    c.reset();
    await held.timeout(const Duration(seconds: 1),
        onTimeout: () => fail('reset left a client hanging'));
    expect(served, isTrue);
    expect(c.state, FixtureState.idle);
    expect(c.omittedFlags, isEmpty, reason: 'the whole table is served again');
  });

  test('teardown with nothing outstanding is a no-op', () {
    final c = control();
    c.completeOutstanding();
    expect(c.state, FixtureState.idle);
    c.armBlockNextPoll();
    c.completeOutstanding();
    expect(c.state, FixtureState.idle,
        reason: 'an armed but unblocked fixture disarms on teardown');
  });
}
