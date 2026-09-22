import 'package:flutter/material.dart';

/// Renders full-bleed, natively, the instant a flow starts, before the
/// WebView for the first real screen has booted.
class SplashScreenWidget extends StatelessWidget {
  final String fallbackAssetPath;

  const SplashScreenWidget({super.key, required this.fallbackAssetPath});

  @override
  Widget build(BuildContext context) {
    // Cosmetic, never load-bearing -- a missing bundled asset (host
    // misconfigured fallbackAssetPath) should render nothing rather than
    // Flutter's red error box, so a broken splash never blocks the flow
    // it's meant to precede
    return SizedBox.expand(
      child: Image.asset(fallbackAssetPath, fit: BoxFit.cover, errorBuilder: _skipOnError),
    );
  }

  static Widget _skipOnError(BuildContext context, Object error, StackTrace? stackTrace) =>
      const SizedBox.shrink();
}
