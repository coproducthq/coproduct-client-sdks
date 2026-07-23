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
    final c = await Coproduct.initialize(sdkKey: 'cpk_mob_wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww');
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
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Coproduct Flutter scaffold')),
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
