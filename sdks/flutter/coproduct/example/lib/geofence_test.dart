// A device test for GPS geo-fence targeting. It seeds a snapshot (one BOOL flag,
// `near_store`, gated by a 500 m geo-fence around SF) directly into the SDK cache,
// so the SDK evaluates offline, then enables location and shows a UI element that
// is ENABLED only when the simulated GPS fix is inside the fence. Drive it with:
//   xcrun simctl location booted set 37.7749,-122.4194   (inside  -> enabled)
//   xcrun simctl location booted set 37.8100,-122.4200   (outside -> disabled)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coproduct/coproduct.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

const String _sdkKey = 'cpk_mob_abcdef0123456789abcdef0123456789';
const String _flagKey = 'near_store';

// center 37.7749,-122.4194, radius 500 m
const Map<String, Object> _envelope = {
  'snapshot': {
    'schemaVersion': 1,
    'version': 1,
    'flags': [
      {
        'key': _flagKey,
        'type': 'BOOL',
        'enabled': true,
        'variations': [
          {'key': 'on', 'value': true},
          {'key': 'off', 'value': false},
        ],
        'offVariation': 'off',
        'fallthroughVariation': 'off',
        'targetingRules': [
          {
            'rule_id': '11111111-1111-1111-1111-111111111111',
            'condition': {
              'type': 'geofence',
              'attribute': 'device_location',
              'center': {'lat': 37.7749, 'lng': -122.4194},
              'radius_m': 500,
            },
            'coverage': 10000,
            'rollout': {'type': 'variation', 'variation': 'on'},
          },
        ],
        'prerequisites': [],
      },
      {
        // Control flag: no targeting, fallthrough = on. Proves the cache loaded.
        'key': 'cache_check',
        'type': 'BOOL',
        'enabled': true,
        'variations': [
          {'key': 'on', 'value': true},
          {'key': 'off', 'value': false},
        ],
        'offVariation': 'off',
        'fallthroughVariation': 'on',
        'targetingRules': [],
        'prerequisites': [],
      },
      {
        // Proves whether device_location reached the context at all.
        'key': 'loc_set',
        'type': 'BOOL',
        'enabled': true,
        'variations': [
          {'key': 'on', 'value': true},
          {'key': 'off', 'value': false},
        ],
        'offVariation': 'off',
        'fallthroughVariation': 'off',
        'targetingRules': [
          {
            'rule_id': '22222222-2222-2222-2222-222222222222',
            'condition': {
              'type': 'attribute',
              'attribute': 'device_location',
              'operator': 'is_set',
              'values': <String>[],
            },
            'coverage': 10000,
            'rollout': {'type': 'variation', 'variation': 'on'},
          },
        ],
        'prerequisites': [],
      },
    ],
    'segments': [],
  },
};

String _keyScope(String sdkKey) {
  final digest = sha256.convert(utf8.encode(sdkKey)).bytes.sublist(0, 16);
  return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Future<void> _seedCache() async {
  final cacheDir = (await getApplicationCacheDirectory()).path;
  final dir = Directory('$cacheDir/coproduct/${_keyScope(_sdkKey)}');
  await dir.create(recursive: true);
  await File('${dir.path}/snapshot.json').writeAsString(jsonEncode(_envelope));
}

void main() {
  runApp(const GeofenceTestApp());
}

class GeofenceTestApp extends StatefulWidget {
  const GeofenceTestApp({super.key});
  @override
  State<GeofenceTestApp> createState() => _GeofenceTestAppState();
}

class _GeofenceTestAppState extends State<GeofenceTestApp> {
  CoproductClient? _client;
  bool _inside = false;
  bool _ready = false;
  bool _locationEnabled = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_setup());
  }

  String _status = 'starting';
  String _posText = '?';
  bool _cacheCheck = false;

  void _log(String m) {
    debugPrint('GEOTEST: $m');
    if (mounted) setState(() => _status = m);
  }

  Future<void> _setup() async {
    try {
      _log('seeding cache');
      await _seedCache();
      _log('initializing');
      // Offline: a dead endpoint so polls fail fast and the seeded cache stays.
      final client = await Coproduct.initialize(
        sdkKey: _sdkKey,
        config: CoproductConfig(
          endpoint: Uri.parse('http://127.0.0.1:9'),
          pollInterval: const Duration(hours: 1),
          startupTimeout: const Duration(seconds: 2),
        ),
      );
      _log('initialized; flag before location = '
          '${client.getBool(_flagKey, defaultValue: false)}');
      if (mounted) setState(() {
        _client = client;
        _ready = true;
      });
      _log('enabling location');
      final granted = await Coproduct.enableLocation();
      _log('enableLocation returned $granted');
      if (mounted) setState(() => _locationEnabled = granted);
      // Re-read one fix every 2s so a simctl location change is reflected quickly
      // (refreshLocation is on-demand, not bound by the interval floor).
      _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
        await Coproduct.refreshLocation();
        final value = client.getBool(_flagKey, defaultValue: false);
        String pos = '?';
        try {
          final p = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
          );
          pos = '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}';
        } catch (e) {
          pos = 'err: $e';
        }
        final cacheCheck = client.getBool('cache_check', defaultValue: false);
        final locSet = client.getBool('loc_set', defaultValue: false);
        debugPrint('GEOTEST: near_store=$value loc_set=$locSet cache_check=$cacheCheck pos=$pos');
        if (mounted) setState(() {
          _inside = value;
          _posText = pos;
          _cacheCheck = cacheCheck;
        });
      });
    } catch (e, st) {
      _log('ERROR: $e');
      debugPrint('GEOTEST stack: $st');
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _inside ? Colors.green : Colors.grey;
    final label = _inside ? 'Store Discount ENABLED' : 'Store Discount disabled';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('Geo-fence test')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _inside ? 'INSIDE the 500 m fence' : 'OUTSIDE the 500 m fence',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              // The UI element gated by the geo-fence flag: a real, disabled-looking
              // button when outside, a live green button when inside.
              Opacity(
                opacity: _inside ? 1.0 : 0.4,
                child: ElevatedButton(
                  onPressed: _inside ? () {} : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  child: Text(label),
                ),
              ),
              const SizedBox(height: 32),
              Text('flag "$_flagKey" = $_inside',
                  style: const TextStyle(fontSize: 16, fontFamily: 'Courier')),
              Text('SDK ready: $_ready   location enabled: $_locationEnabled',
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
              Text('status: $_status',
                  style: const TextStyle(fontSize: 12, color: Colors.black45)),
              Text('device pos: $_posText',
                  style: const TextStyle(fontSize: 13, color: Colors.blue)),
            ],
          ),
        ),
      ),
    );
  }
}
