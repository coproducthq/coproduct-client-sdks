import 'next_target.dart';
import 'transition.dart';

/// A screen's html is a body fragment rendered inside a
/// <section data-screen-id="..."> in the assembled shell, not a full
/// document.
class Screen {
  final String id;
  final String html;
  final List<Transition> transitions;
  final NextTarget defaultNext;

  const Screen({
    required this.id,
    required this.html,
    required this.transitions,
    required this.defaultNext,
  });

  factory Screen.fromJson(Map<String, dynamic> json) => Screen(
        id: json['id'] as String,
        html: json['html'] as String,
        transitions: (json['transitions'] as List)
            .map((t) => Transition.fromJson(t as Map<String, dynamic>))
            .toList(),
        defaultNext: NextTarget.fromJson(json['defaultNext'] as Map<String, dynamic>),
      );
}
