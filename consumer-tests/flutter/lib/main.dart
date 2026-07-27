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
          defaultValue: 'cpk_mob_test_scaffold',
        ),
      );
    } on CoproductInitializationCancelled {
      return;
    } catch (error, stack) {
      developer.log('COPRODUCT_FLUTTER_CONSUMER_INIT_ERROR',
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
      'COPRODUCT_FLUTTER_CONSUMER_STATUS '
      'ready=$ready '
      'getBool=$flagValue',
      name: 'coproduct',
    );
  }

  @override
  void dispose() {
    unawaited(Coproduct.shutdown().catchError((Object error, StackTrace stack) {
      developer.log('COPRODUCT_FLUTTER_CONSUMER_SHUTDOWN_ERROR',
          name: 'coproduct', error: error, stackTrace: stack);
    }));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Coproduct Flutter consumer')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('SDK ready: ${ready ? "yes" : "no"}'),
              Text('getBool: $flagValue'),
            ],
          ),
        ),
      ),
    );
  }
}
