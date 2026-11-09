import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'attribute_value.dart';
import 'rust/api.dart' as frb;

/// Persists UTM attribution across launches and flattens it into the
/// auto-populated attribute shape.
///
/// Two values live per UTM key: first-touch, the bare key (`utm_source`,
/// `utm_medium`, `utm_campaign`, `utm_term`, `utm_content`), captured once
/// and frozen, and last-touch, the key with a `_last` suffix, overwritten on
/// every [capture]. An empty or absent value is omitted from both. Backed by
/// `shared_preferences` rather than the native session store, since neither
/// value needs a native transaction: a developer calls [capture] from Dart
/// with a URL it already has
class UtmStore {
  UtmStore({Map<String, String> Function(String url)? parse})
    : _parse = parse ?? ((url) => frb.parseUtmParameters(url: url));

  final Map<String, String> Function(String url) _parse;

  static const _firstTouchKey = 'app.coproduct.flutter.utm.first';
  static const _lastTouchKey = 'app.coproduct.flutter.utm.last';

  /// Parses [url] for UTM parameters, freezes any first-touch value this is
  /// the first capture to see, overwrites last-touch with every present
  /// value, persists the result, and returns the flattened attribute map.
  ///
  /// An empty parse (no UTM parameters on [url]) persists nothing and
  /// returns whatever is already stored
  Future<Map<String, AttributeValue>> capture(String url) async {
    final parsed = Map<String, String>.of(_parse(url))
      ..removeWhere((_, value) => value.isEmpty);
    final prefs = await SharedPreferences.getInstance();
    if (parsed.isEmpty) {
      return _flatten(
        _readMap(prefs, _firstTouchKey),
        _readMap(prefs, _lastTouchKey),
      );
    }

    final first = _readMap(prefs, _firstTouchKey);
    final last = _readMap(prefs, _lastTouchKey)..addAll(parsed);
    var firstChanged = false;
    for (final entry in parsed.entries) {
      if (first.containsKey(entry.key)) continue;
      first[entry.key] = entry.value;
      firstChanged = true;
    }

    await prefs.setString(_lastTouchKey, jsonEncode(last));
    if (firstChanged) {
      await prefs.setString(_firstTouchKey, jsonEncode(first));
    }
    return _flatten(first, last);
  }

  /// Returns the persisted UTM attributes, flattened, without capturing
  /// anything. Used to seed the auto-populated layer at initialize from
  /// whatever an earlier launch captured
  Future<Map<String, AttributeValue>> readAttributes() async {
    final prefs = await SharedPreferences.getInstance();
    return _flatten(
      _readMap(prefs, _firstTouchKey),
      _readMap(prefs, _lastTouchKey),
    );
  }

  Map<String, String> _readMap(SharedPreferences prefs, String key) {
    final raw = prefs.getString(key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
    } catch (_) {
      // Malformed persisted JSON is treated as absent rather than thrown,
      // matching how a missing key is handled
    }
    return {};
  }

  Map<String, AttributeValue> _flatten(
    Map<String, String> first,
    Map<String, String> last,
  ) {
    final result = <String, AttributeValue>{};
    first.forEach((key, value) {
      if (value.isNotEmpty) result[key] = AttributeValue.string(value);
    });
    last.forEach((key, value) {
      if (value.isNotEmpty) {
        result['${key}_last'] = AttributeValue.string(value);
      }
    });
    return result;
  }
}
