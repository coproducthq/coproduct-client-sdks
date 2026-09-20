import 'screen.dart';

class OnboardingFlowGraph {
  final String startScreenId;
  final String? splashImage;
  final List<Screen> screens;

  const OnboardingFlowGraph({
    required this.startScreenId,
    required this.splashImage,
    required this.screens,
  });

  factory OnboardingFlowGraph.fromJson(Map<String, dynamic> json) => OnboardingFlowGraph(
        startScreenId: json['startScreenId'] as String,
        splashImage: json['splashImage'] as String?,
        screens: (json['screens'] as List)
            .map((s) => Screen.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  Screen? screenById(String id) {
    for (final screen in screens) {
      if (screen.id == id) return screen;
    }
    return null;
  }
}
