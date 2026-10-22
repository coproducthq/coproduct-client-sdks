import 'dart:async' show unawaited;
import 'dart:developer' as developer;

import 'package:coproduct/coproduct.dart';
import 'package:coproduct/paywall.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

// The mobile SDK key, passed at build time so it never sits in source:
// flutter run --dart-define=COPRODUCT_SDK_KEY=your_mobile_sdk_key
const String _sdkKey = String.fromEnvironment('COPRODUCT_SDK_KEY');

// Demo flag keys, one per value type. When the key's project has none of these
// flags, the reads return the defaults passed here, so every read and mutate
// surface still runs end to end
const String _boolFlag = 'test-flag';
const String _stringFlag = 'greeting';
const String _intFlag = 'max-items';
const String _numberFlag = 'ratio';
const String _jsonFlag = 'theme';

/// A paywall demo with no real backend: fetchPaywall returns a fixed
/// snapshot whose one package is Google's static test product id
/// (android.test.purchased), which the Play Store app resolves specially
/// for any installed app with no Play Console configuration needed.
/// recordPurchase/getEntitlements just log, matching this demo's
/// bridge-level verification goal rather than a backend integration test.
class _DemoPaywallClient implements PaywallClient {
  // PaywallSnapshot.html and content.html are meant to carry the identical
  // string (see PaywallSnapshot's own doc comment) -- sharing one constant
  // here keeps that in sync instead of risking the WebView loading a blank
  // body while content.html still lists ctas that never render.
  //
  // The attribute names below (data-cp-action/data-package-key/
  // data-cp-price-for) are what paywall-platform-script.js actually binds
  // click handlers to -- confirmed against the real paywall HTML a
  // production paywall snapshot serves. An earlier version of this demo
  // used invented names (data-cp-cta/data-cp-restore/data-cp-dismiss) that
  // the script's click delegation never matches, so every button silently
  // did nothing; verified live on a device that every button here does.
  static const String _html = '''
<section>
  <h1>Coproduct demo paywall</h1>
  <button data-cp-action="purchase" data-package-key="test">Buy <span data-cp-price-for="test"></span></button>
  <button data-cp-action="restore">Restore</button>
  <button data-cp-action="dismiss">Close</button>
</section>
''';

  @override
  Future<PaywallSnapshot?> fetchPaywall(String paywallId) async {
    return const PaywallSnapshot(
      paywallId: 'demo',
      version: 1,
      templateType: 'hero_single_offer',
      content: PaywallContent(
        offeringKey: 'default',
        ctas: [PaywallCta(packageKey: 'test', label: 'Buy (test)')],
        html: _html,
      ),
      packages: {
        'test': PaywallPackageRef(
          androidProductId: 'android.test.purchased',
          kind: PackageKind.consumable,
        ),
      },
      html: _html,
    );
  }

  @override
  Future<List<Entitlement>> recordPurchase({
    required String appUserId,
    required String platform,
    required String storeProductId,
    required String storeTransactionId,
    required DateTime purchaseDate,
    DateTime? expiresDate,
  }) async {
    developer.log(
      'COPRODUCT_FLUTTER_DEMO_PAYWALL_PURCHASE_RECORDED '
      'platform=$platform storeProductId=$storeProductId',
      name: 'coproduct',
    );
    return const [];
  }

  @override
  Future<List<Entitlement>> getEntitlements(String appUserId) async => const [];

  @override
  Future<void> identify({
    required String appUserId,
    required String targetingKey,
  }) async {}
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.sdkKey = _sdkKey});

  /// The key the app initializes with. An empty key shows setup instructions
  /// instead of starting the SDK. The SDK starts once, when the state is
  /// created, so the key is expected to stay the same for the app's lifetime
  final String sdkKey;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  CoproductClient? client;
  bool ready = false;
  // Loaded once up front, alongside client/ready, so the paywall demo button
  // never needs to await anything itself -- null until loaded, and stays
  // null (disabling the button) if loading the bundled asset ever fails
  String? _paywallScript;

  @override
  void initState() {
    super.initState();
    if (widget.sdkKey.isEmpty) {
      developer.log('COPRODUCT_FLUTTER_DEMO_MISSING_KEY', name: 'coproduct');
      return;
    }
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final CoproductClient c;
    try {
      c = await Coproduct.initialize(sdkKey: widget.sdkKey);
    } on CoproductInitializationCancelled {
      // The widget was disposed while initialize was still in flight
      return;
    } catch (error, stack) {
      developer.log(
        'COPRODUCT_FLUTTER_DEMO_INIT_ERROR',
        name: 'coproduct',
        error: error,
        stackTrace: stack,
      );
      return;
    }

    // Loaded here, not lazily from the button, so opening the demo paywall
    // never has to await anything itself. A failure here only disables that
    // one button -- it's unrelated to the SDK's own readiness
    String? paywallScript;
    try {
      paywallScript = await CoproductPaywall.loadPlatformScript();
    } catch (error, stack) {
      developer.log(
        'COPRODUCT_FLUTTER_DEMO_PAYWALL_SCRIPT_ERROR',
        name: 'coproduct',
        error: error,
        stackTrace: stack,
      );
    }

    if (!mounted) return;
    setState(() {
      client = c;
      ready = true;
      _paywallScript = paywallScript;
    });

    developer.log(
      'COPRODUCT_FLUTTER_DEMO_STATUS '
      'ready=$ready '
      'getBool=${c.getBool(_boolFlag, defaultValue: false)} '
      'getString=${c.getString(_stringFlag, defaultValue: 'default')} '
      'getInt=${c.getInt(_intFlag, defaultValue: 0)} '
      'getNumber=${c.getNumber(_numberFlag, defaultValue: 0)} '
      'getJson=${c.getJson(_jsonFlag, defaultValue: const <String, Object?>{})}',
      name: 'coproduct',
    );
  }

  @override
  void dispose() {
    // Without a key the SDK never started, so there is nothing to shut down
    if (widget.sdkKey.isNotEmpty) {
      unawaited(
        Coproduct.shutdown().catchError((Object error, StackTrace stack) {
          developer.log(
            'COPRODUCT_FLUTTER_DEMO_SHUTDOWN_ERROR',
            name: 'coproduct',
            error: error,
            stackTrace: stack,
          );
        }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sdkKey.isEmpty) {
      return const MaterialApp(home: _MissingKey());
    }
    final c = client;
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Coproduct Flutter scaffold')),
        // The shell renders immediately and the scope is installed once
        // initialize returns, so startup is never blocked on the SDK. An app
        // that prefers the simpler shape can await initialize before runApp
        // instead, which the README shows
        body: c == null
            ? const Center(child: Text('SDK ready: no'))
            : CoproductScope(
                client: c,
                child: _FlagDemo(
                  sdkKey: widget.sdkKey,
                  paywallScript: _paywallScript,
                ),
              ),
      ),
    );
  }
}

/// Shown in place of the flag demo when the app started without a key
class _MissingKey extends StatelessWidget {
  const _MissingKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Coproduct Flutter scaffold')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No SDK key was passed, so the SDK has not started.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              'Create a mobile SDK key in Coproduct, then run the app with '
              'it:',
            ),
            SizedBox(height: 8),
            Text(
              'flutter run --dart-define=COPRODUCT_SDK_KEY=your_mobile_sdk_key',
            ),
            SizedBox(height: 12),
            Text(
              'Pass the key at build time rather than writing it into the '
              'source.',
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything below the scope reads flags without being handed the client
class _FlagDemo extends StatelessWidget {
  const _FlagDemo({required this.sdkKey, required this.paywallScript});

  final String sdkKey;

  /// Null until `_bootstrap` loads it (or if loading it ever fails), which
  /// disables the paywall button below rather than crashing it
  final String? paywallScript;

  @override
  Widget build(BuildContext context) {
    // Resolved once from the nearest scope, then passed to the identity
    // controls. The reads below resolve the scope themselves
    final client = CoproductScope.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SDK ready: yes'),
          const SizedBox(height: 16),

          // Reactive reads. Each builder rebuilds by itself whenever its flag
          // changes and disposes its observation when it leaves the tree
          const Text(
            'Observed (live)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          CoproductFlagBuilder.boolFlag(
            flagKey: _boolFlag,
            defaultValue: false,
            builder: (context, value, child) => Text('observeBool: $value'),
          ),
          CoproductFlagBuilder.stringFlag(
            flagKey: _stringFlag,
            defaultValue: 'default',
            builder: (context, value, child) => Text('observeString: $value'),
          ),
          CoproductFlagBuilder.intFlag(
            flagKey: _intFlag,
            defaultValue: 0,
            builder: (context, value, child) => Text('observeInt: $value'),
          ),
          CoproductFlagBuilder.numberFlag(
            flagKey: _numberFlag,
            defaultValue: 0,
            builder: (context, value, child) => Text('observeNumber: $value'),
          ),
          CoproductFlagBuilder.jsonFlag(
            flagKey: _jsonFlag,
            defaultValue: const <String, Object?>{},
            builder: (context, value, child) => Text('observeJson: $value'),
          ),
          const SizedBox(height: 16),

          // One-shot reads. The synchronous getters read each value once, when
          // this widget builds, and do not follow later changes the way the
          // builders above do. That is the difference between the two surfaces
          const Text(
            'Read at build (one-shot)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            'getBool: ${CoproductScope.of(context).getBool(_boolFlag, defaultValue: false)}',
          ),
          Text(
            'getString: '
            '${CoproductScope.of(context).getString(_stringFlag, defaultValue: 'default')}',
          ),
          Text(
            'getInt: ${CoproductScope.of(context).getInt(_intFlag, defaultValue: 0)}',
          ),
          Text(
            'getNumber: '
            '${CoproductScope.of(context).getNumber(_numberFlag, defaultValue: 0)}',
          ),
          Text(
            'getJson: '
            '${CoproductScope.of(context).getJson(_jsonFlag, defaultValue: const <String, Object?>{})}',
          ),
          const SizedBox(height: 16),

          // Identity mutations re-evaluate the loaded snapshot locally and
          // notify the observers above, so a rule keyed on identity moves the
          // live reads without a network round trip
          const Text('Identity', style: TextStyle(fontWeight: FontWeight.bold)),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: () => _run(
                  'identify',
                  () => client.identify(
                    userId: 'user-123',
                    attributes: const {'plan': AttributeValue.string('pro')},
                  ),
                ),
                child: const Text('identify'),
              ),
              ElevatedButton(
                onPressed: () => _run(
                  'updateAttributes',
                  () => client.updateAttributes(const {
                    'seats': AttributeValue.number(5),
                  }),
                ),
                child: const Text('update attrs'),
              ),
              ElevatedButton(
                onPressed: () => _run(
                  'removeAttributes',
                  () => client.removeAttributes(const ['seats']),
                ),
                child: const Text('remove attrs'),
              ),
              ElevatedButton(
                onPressed: () => _run(
                  'setContext',
                  () => client.setContext(
                    targetingKey: 'tenant-42',
                    attributes: const {'tier': AttributeValue.string('gold')},
                  ),
                ),
                child: const Text('set context'),
              ),
              ElevatedButton(
                onPressed: () => _run('signOut', () => client.signOut()),
                child: const Text('sign out'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Exercises the real MethodChannelPaywallBridge against the real
          // CoproductPaywallPlugin.kt (no bridge override), using Google's
          // static test product id -- see the manual verification steps in
          // this task's plan for what a tap through this actually confirms
          const Text('Paywall', style: TextStyle(fontWeight: FontWeight.bold)),
          ElevatedButton(
            onPressed: paywallScript == null
                ? null
                : () {
                    final script = paywallScript!;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (routeContext) => Scaffold(
                          appBar: AppBar(title: const Text('Demo paywall')),
                          body: CoproductPaywall(
                            paywallId: 'demo',
                            appUserId: 'demo-user',
                            sdkKey: sdkKey,
                            platformScriptJs: script,
                            client: _DemoPaywallClient(),
                            onDismiss: () => Navigator.of(routeContext).pop(),
                          ),
                        ),
                      ),
                    );
                  },
            child: const Text('Open demo paywall'),
          ),
        ],
      ),
    );
  }

  // Fire an identity mutation and log its outcome. A real app awaits the future
  // where it needs to read settled state such as previousAnonymousId afterward
  void _run(String label, Future<void> Function() action) {
    unawaited(
      action()
          .then((_) {
            developer.log(
              'COPRODUCT_FLUTTER_DEMO_IDENTITY ok=$label',
              name: 'coproduct',
            );
          })
          .catchError((Object error, StackTrace stack) {
            developer.log(
              'COPRODUCT_FLUTTER_DEMO_IDENTITY_ERROR label=$label',
              name: 'coproduct',
              error: error,
              stackTrace: stack,
            );
          }),
    );
  }
}
