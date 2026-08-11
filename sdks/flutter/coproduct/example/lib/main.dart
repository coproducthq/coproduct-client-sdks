import 'dart:async' show unawaited;
import 'dart:developer' as developer;

import 'package:coproduct/coproduct.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  CoproductClient? client;
  bool ready = false;
  bool flagValue = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final CoproductClient c;
    try {
      c = await Coproduct.initialize(
        sdkKey: const String.fromEnvironment(
          'COPRODUCT_SDK_KEY',
          defaultValue: 'cpk_mob_wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww',
        ),
      );
    } on CoproductInitializationCancelled {
      // The widget was disposed while initialize was still in flight
      return;
    } catch (error, stack) {
      developer.log('COPRODUCT_FLUTTER_DEMO_INIT_ERROR',
          name: 'coproduct', error: error, stackTrace: stack);
      return;
    }
    final flag = c.getBool('test-flag', false);

    if (!mounted) return;
    setState(() {
      client = c;
      ready = true;
      flagValue = flag;
    });

    developer.log(
      'COPRODUCT_FLUTTER_DEMO_STATUS '
      'ready=$ready '
      'getBool=$flagValue',
      name: 'coproduct',
    );
  }

  @override
  void dispose() {
    unawaited(Coproduct.shutdown().catchError((Object error, StackTrace stack) {
      developer.log('COPRODUCT_FLUTTER_DEMO_SHUTDOWN_ERROR',
          name: 'coproduct', error: error, stackTrace: stack);
    }));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                child: const _FlagDemo(),
              ),
      ),
    );
  }
}

/// Everything below the scope reads flags without being handed the client
class _FlagDemo extends StatelessWidget {
  const _FlagDemo();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('SDK ready: yes'),
          // Rebuilds by itself whenever the flag changes, and disposes its
          // observation when this widget leaves the tree
          CoproductFlagBuilder.boolFlag(
            flagKey: 'test-flag',
            defaultValue: false,
            builder: (context, enabled, child) =>
                Text('observeBool: $enabled'),
          ),
          // The synchronous getter reads the value once, when this widget
          // builds. It does not follow later changes the way the builder above
          // does, which is the difference between the two surfaces
          Text('getBool at build: ${CoproductScope.of(context).getBool(
            'test-flag',
            false,
          )}'),
        ],
      ),
    );
  }
}
