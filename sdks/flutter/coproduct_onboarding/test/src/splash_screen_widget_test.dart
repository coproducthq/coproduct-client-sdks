import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coproduct_onboarding/src/splash_screen_widget.dart';

void main() {
  testWidgets('renders the bundled fallback when splashImageUrl is null', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SplashScreenWidget(splashImageUrl: null, fallbackAssetPath: 'assets/coproduct_fallback_splash.png'),
    ));
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
  });

  testWidgets('renders the remote splash image when splashImageUrl is set', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SplashScreenWidget(
        splashImageUrl: 'https://assets.coproduct.app/p-1/a-1-splash.png',
        fallbackAssetPath: 'assets/coproduct_fallback_splash.png',
      ),
    ));
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<NetworkImage>());
  });

  testWidgets('skips the splash instead of erroring when the network image fails to load', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SplashScreenWidget(
        splashImageUrl: 'https://assets.coproduct.app/p-1/a-1-splash.png',
        fallbackAssetPath: 'assets/coproduct_fallback_splash.png',
      ),
    ));
    // The test harness fails every real HTTP request (returns 400) -- a
    // splash is cosmetic, never load-bearing, so that failure renders
    // nothing rather than surfacing as an uncaught exception
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('skips the splash instead of erroring when the fallback asset fails to load', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SplashScreenWidget(splashImageUrl: null, fallbackAssetPath: 'assets/does-not-exist.png'),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
