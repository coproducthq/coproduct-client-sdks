/// A screen's resolved next step: another screen, or a terminal action.
/// Mirrors ZNextTarget in packages/snapshot-spec/src/onboarding-flow.ts
sealed class NextTarget {
  const NextTarget();

  factory NextTarget.fromJson(Map<String, dynamic> json) {
    switch (json['type'] as String) {
      case 'screen':
        return ScreenTarget(json['screenId'] as String);
      case 'dismiss':
        return const DismissTarget();
      case 'complete':
        return const CompleteTarget();
      default:
        throw FormatException('Unknown NextTarget type: ${json['type']}');
    }
  }

  Map<String, dynamic> toJson();
}

final class ScreenTarget extends NextTarget {
  final String screenId;
  const ScreenTarget(this.screenId);

  @override
  Map<String, dynamic> toJson() => {'type': 'screen', 'screenId': screenId};
}

final class DismissTarget extends NextTarget {
  const DismissTarget();

  @override
  Map<String, dynamic> toJson() => {'type': 'dismiss'};
}

final class CompleteTarget extends NextTarget {
  const CompleteTarget();

  @override
  Map<String, dynamic> toJson() => {'type': 'complete'};
}
