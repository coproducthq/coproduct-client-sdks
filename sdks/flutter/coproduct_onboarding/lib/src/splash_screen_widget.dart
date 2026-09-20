import 'package:flutter/material.dart';

/// Renders full-bleed, natively, the instant a flow starts, before the
/// WebView for the first real screen has booted. Only takes effect from a
/// device's second app open onward; a cold install has nothing to
/// remote-configure yet, so it always shows the bundled fallback.
class SplashScreenWidget extends StatelessWidget {
  final String? splashImageUrl;
  final String fallbackAssetPath;

  const SplashScreenWidget({super.key, required this.splashImageUrl, required this.fallbackAssetPath});

  @override
  Widget build(BuildContext context) {
    // A splash image is cosmetic, never load-bearing -- a missing bundled
    // asset (host misconfigured fallbackAssetPath) or a network splash that
    // fails to load (bad URL, offline) should render nothing rather than
    // Flutter's red error box, so a broken splash never blocks the flow it's
    // meant to precede
    final image = splashImageUrl == null
        ? Image.asset(fallbackAssetPath, fit: BoxFit.cover, errorBuilder: _skipOnError)
        : Image.network(splashImageUrl!, fit: BoxFit.cover, errorBuilder: _skipOnError);

    return SizedBox.expand(child: image);
  }

  static Widget _skipOnError(BuildContext context, Object error, StackTrace? stackTrace) =>
      const SizedBox.shrink();
}
