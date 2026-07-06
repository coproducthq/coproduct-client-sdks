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
  bool flagValue = false;
  bool observerRegistered = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final c = await Coproduct.initialize(sdkKey: 'cpk_mob_wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww');
    final flag = c.getBool('test-flag', false);
    // initialize no longer polls, so the transport is not called here. The
    // SecureStore host bridge is exercised by cold-start, which is the host
    // callback this scaffold can prove until the binding exposes a poll entry
    // point.
    final hosts = mockSecureStore.completedHandshake;

    final sub = await c.observe('test-flag', false, (value) {});

    if (!mounted) return;
    setState(() {
      client = c;
      subscription = sub;
      ready = true;
      hostCallbacks = hosts;
      flagValue = flag;
      observerRegistered = true;
    });

    developer.log(
      'COPRODUCT_FLUTTER_DEMO_STATUS '
      'ready=$ready '
      'hostCallbacks=$hostCallbacks '
      'getBool=$flagValue '
      'observerRegistered=$observerRegistered',
      name: 'coproduct',
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Coproduct Flutter scaffold')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('SDK ready: ${ready ? "yes" : "no"}'),
              Text('Host callbacks: ${hostCallbacks ? "yes" : "no"}'),
              Text('getBool: $flagValue'),
              Text('Observer registered: ${observerRegistered ? "yes" : "no"}'),
            ],
          ),
        ),
      ),
    );
  }
}
