import 'dart:async' show unawaited;
import 'dart:developer' as developer;

import 'package:coproduct/coproduct.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

// Demo flag keys, one per value type. With no real snapshot loaded the reads
// return the defaults passed here, so the example runs end to end against the
// placeholder key and still exercises every read and mutate surface
const String _boolFlag = 'test-flag';
const String _stringFlag = 'greeting';
const String _intFlag = 'max-items';
const String _numberFlag = 'ratio';
const String _jsonFlag = 'theme';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  CoproductClient? client;
  bool ready = false;

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

    if (!mounted) return;
    setState(() {
      client = c;
      ready = true;
    });

    developer.log(
      'COPRODUCT_FLUTTER_DEMO_STATUS '
      'ready=$ready '
      'getBool=${c.getBool(_boolFlag, false)} '
      'getString=${c.getString(_stringFlag, 'default')} '
      'getInt=${c.getInt(_intFlag, 0)} '
      'getNumber=${c.getNumber(_numberFlag, 0)} '
      'getJson=${c.getJson(_jsonFlag, const <String, Object?>{})}',
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
          const Text('Observed (live)',
              style: TextStyle(fontWeight: FontWeight.bold)),
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
          const Text('Read at build (one-shot)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Text('getBool: ${CoproductScope.of(context).getBool(_boolFlag, false)}'),
          Text('getString: '
              '${CoproductScope.of(context).getString(_stringFlag, 'default')}'),
          Text('getInt: ${CoproductScope.of(context).getInt(_intFlag, 0)}'),
          Text('getNumber: '
              '${CoproductScope.of(context).getNumber(_numberFlag, 0)}'),
          Text('getJson: '
              '${CoproductScope.of(context).getJson(_jsonFlag, const <String, Object?>{})}'),
          const SizedBox(height: 16),

          // Identity mutations re-evaluate the loaded snapshot locally and
          // notify the observers above, so a rule keyed on identity moves the
          // live reads without a network round trip
          const Text('Identity', style: TextStyle(fontWeight: FontWeight.bold)),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: () => _run('identify', () => client.identify(
                      userId: 'user-123',
                      attributes: const {'plan': AttributeValue.string('pro')},
                    )),
                child: const Text('identify'),
              ),
              ElevatedButton(
                onPressed: () => _run('updateAttributes',
                    () => client.updateAttributes(
                          const {'seats': AttributeValue.number(5)},
                        )),
                child: const Text('update attrs'),
              ),
              ElevatedButton(
                onPressed: () =>
                    _run('removeAttributes', () => client.removeAttributes(
                          const ['seats'],
                        )),
                child: const Text('remove attrs'),
              ),
              ElevatedButton(
                onPressed: () => _run('setContext', () => client.setContext(
                      targetingKey: 'tenant-42',
                      attributes: const {'tier': AttributeValue.string('gold')},
                    )),
                child: const Text('set context'),
              ),
              ElevatedButton(
                onPressed: () => _run('signOut', () => client.signOut()),
                child: const Text('sign out'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Fire an identity mutation and log its outcome. A real app awaits the future
  // where it needs to read settled state such as previousAnonymousId afterward
  void _run(String label, Future<void> Function() action) {
    unawaited(action().then((_) {
      developer.log('COPRODUCT_FLUTTER_DEMO_IDENTITY ok=$label',
          name: 'coproduct');
    }).catchError((Object error, StackTrace stack) {
      developer.log('COPRODUCT_FLUTTER_DEMO_IDENTITY_ERROR label=$label',
          name: 'coproduct', error: error, stackTrace: stack);
    }));
  }
}
