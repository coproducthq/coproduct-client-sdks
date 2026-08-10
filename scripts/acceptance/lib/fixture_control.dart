import 'dart:async';

/// Where the fixture is in the delayed-poll cycle. `armed` means the next
/// snapshot request will be held; `blocked` means one is being held right now
enum FixtureState { idle, armed, blocked }

/// Raised when a control command is illegal in the current state. The fixture
/// turns this into a 409 so a harness bug surfaces as a failed command rather
/// than as a silently ignored one
class FixtureControlError implements Exception {
  FixtureControlError(this.message);
  final String message;

  @override
  String toString() => 'FixtureControlError: $message';
}

/// The fixture's control state machine, deliberately free of `dart:io` so every
/// legal and illegal transition is testable without a server. The HTTP layer
/// owns routing and status codes; this owns what is legal and what is served
class FixtureControl {
  FixtureControl({required this.buildBody});

  /// Renders the snapshot envelope for a version and a set of omitted flag
  /// keys. Injected so the state machine does not depend on the flag table
  final String Function(int version, Set<String> omittedFlags) buildBody;

  FixtureState _state = FixtureState.idle;
  Completer<void>? _gate;
  Set<String> _omittedFlags = const {};
  int _snapshotVersion = 1;
  int _servedPolls = 0;

  FixtureState get state => _state;

  /// Snapshot requests that have passed the gate. The device test reads this
  /// to tell a poll it caused from one the host scheduler happened to fire
  int get servedPolls => _servedPolls;

  int get snapshotVersion => _snapshotVersion;

  Set<String> get omittedFlags => _omittedFlags;

  /// The body to serve right now. Read after the gate opens, so a snapshot
  /// changed while a poll was held is the one that poll receives
  String get body => buildBody(_snapshotVersion, _omittedFlags);

  /// Hold the next snapshot request until `release`
  void armBlockNextPoll() {
    if (_state != FixtureState.idle) {
      throw FixtureControlError('cannot arm while $_state');
    }
    _state = FixtureState.armed;
  }

  /// Complete the held response. Illegal unless a request is actually being
  /// held, so a test that releases too early fails loudly instead of racing
  void release() {
    if (_state != FixtureState.blocked) {
      throw FixtureControlError('cannot release while $_state');
    }
    _gate!.complete();
    _gate = null;
    _state = FixtureState.idle;
  }

  /// Choose what the next served snapshot contains. Every call advances the
  /// version, so the swap is a real change rather than a repeat the core
  /// could treat as unchanged
  void setActiveSnapshot(Set<String> omitFlags) {
    _omittedFlags = Set.unmodifiable(omitFlags);
    _snapshotVersion += 1;
  }

  /// Called by the request handler before it writes. Returns immediately unless
  /// the fixture is armed, in which case it parks until `release`
  Future<void> awaitTurn() async {
    if (_state == FixtureState.armed) {
      _state = FixtureState.blocked;
      _gate = Completer<void>();
      await _gate!.future;
    }
    _servedPolls += 1;
  }

  /// Return to a clean slate: release anything held, disarm, and serve the
  /// whole flag table again. A test calls this in teardown so the next test
  /// inherits a known fixture rather than whatever the last one left behind
  void reset() {
    completeOutstanding();
    setActiveSnapshot(const {});
  }

  /// Teardown. Completes a held response so no client is left hanging, and
  /// disarms, so a fixture shutting down never strands the app mid-poll
  void completeOutstanding() {
    final gate = _gate;
    _gate = null;
    _state = FixtureState.idle;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }
}
