import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coproduct_onboarding/src/splash_screen_widget.dart';

void main() {
  testWidgets('renders the bundled fallback asset', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SplashScreenWidget(fallbackAssetPath: 'assets/coproduct_fallback_splash.png'),
    ));
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
  });

  testWidgets('skips the splash instead of erroring when the fallback asset fails to load', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SplashScreenWidget(fallbackAssetPath: 'assets/does-not-exist.png'),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
