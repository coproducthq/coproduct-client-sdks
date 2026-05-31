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
  Cancellable? subscription;
  bool ready = false;
  bool hostCallbacks = false;
  bool loadedFromCache = false;
  bool flagValue = false;
  bool observerFired = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final c = await Coproduct.initialize(sdkKey: 'cpk_mob_test_scaffold');
    final cached = c.wasLoadedFromCache();
    final flag = c.getBool('test-flag', false);
    final hosts =
        mockTransport.requestCount == 1 && mockSecureStore.completedHandshake;

    final sub = await c.observe('test-flag', false, (value) {
      if (mounted) {
        setState(() => observerFired = true);
      }
    });

    await c.simulateChange('test-flag', true);

    if (!mounted) return;
    setState(() {
      client = c;
      subscription = sub;
      ready = true;
      hostCallbacks = hosts;
      loadedFromCache = cached;
      flagValue = flag;
    });

    developer.log(
      'COPRODUCT_FLUTTER_CONSUMER_STATUS '
      'ready=$ready '
      'hostCallbacks=$hostCallbacks '
      'loadedFromCache=$loadedFromCache '
      'getBool=$flagValue '
      'observerFired=$observerFired',
      name: 'coproduct',
    );
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
              Text('Host callbacks: ${hostCallbacks ? "yes" : "no"}'),
              Text('Loaded from cache: ${loadedFromCache ? "yes" : "no"}'),
              Text('getBool: $flagValue'),
              Text('Observer fired: ${observerFired ? "yes" : "no"}'),
            ],
          ),
        ),
      ),
    );
  }
}
