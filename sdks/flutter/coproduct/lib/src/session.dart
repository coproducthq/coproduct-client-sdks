import 'errors.dart';
import 'rust/api.dart' as frb;

/// The largest integer a double holds exactly. Both values reach the core as a
/// double, so the native side never produces a larger one, and one arriving
/// anyway is a defect rather than a value to round
const int kMaxExactInteger = 9007199254740991;

/// Both session attributes from one native transaction. One value rather than
/// two, so half a pair has no way to be published
final class SessionPair {
  const SessionPair({required this.firstSeenAt, required this.sessionCount});

  final int firstSeenAt;
  final int sessionCount;

  /// Numbers rather than strings, so numeric targeting operators compare them
  /// the way the other SDKs publish them. Exact, because [fromChannel] admits
  /// nothing above [kMaxExactInteger]
  Map<String, frb.FrbContextValue> get attributes => {
    'first_seen_at': frb.FrbContextValue.number(firstSeenAt.toDouble()),
    'session_count': frb.FrbContextValue.number(sessionCount.toDouble()),
  };

  /// Validates the platform answer as a unit. Anything short of a map carrying
  /// both integers in range is a defect in the native side or the codec, and
  /// publishing half of it would be worse than publishing neither
  static SessionPair fromChannel(Object? raw) {
    if (raw
        case {
          'first_seen_at': final int firstSeenAt,
          'session_count': final int sessionCount,
        }
        when firstSeenAt >= 0 &&
            firstSeenAt <= kMaxExactInteger &&
            sessionCount >= 1 &&
            sessionCount <= kMaxExactInteger) {
      return SessionPair(firstSeenAt: firstSeenAt, sessionCount: sessionCount);
    }
    throw const SessionAttributesUnavailable(
      SessionAttributesUnavailableCause.malformedResponse,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SessionPair &&
      other.firstSeenAt == firstSeenAt &&
      other.sessionCount == sessionCount;

  @override
  int get hashCode => Object.hash(firstSeenAt, sessionCount);

  @override
  String toString() =>
      'SessionPair(firstSeenAt: $firstSeenAt, sessionCount: $sessionCount)';
}
