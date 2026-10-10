import 'next_target.dart';

/// A screen's ordered transition: a condition (kept as raw JSON, evaluated
/// client-side by the platform script running inside the WebView, not by
/// Dart) and where it leads.
class Transition {
  final Map<String, dynamic> condition;
  final NextTarget next;

  const Transition({required this.condition, required this.next});

  factory Transition.fromJson(Map<String, dynamic> json) => Transition(
        condition: json['condition'] as Map<String, dynamic>,
        next: NextTarget.fromJson(json['next'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {'condition': condition, 'next': next.toJson()};
}
