import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'auto_upsert.dart';
import 'host.dart' show ForegroundBinder;
import 'rust/api.dart' as frb;

/// Keeps `device_location` current for one runtime by reading a GPS fix on a
/// foreground cadence and publishing it through the auto-upsert path, so a
/// geo-fence re-evaluates as the device moves.
///
/// Opt-in and gated: nothing runs until the host calls [enable] (or
/// [setIntervalMs]), which requests OS location permission on its first call.
/// The loop is foreground-only; a `Timer` naturally stops firing while the
/// isolate is frozen in the background and resumes on return, and [bindResume]
/// takes a fresh fix the moment the app is foregrounded. The SDK holds no
/// continuous `Geolocator` stream; it reads one fix per tick on the host's
/// cadence. Mirrors NetworkTypeService's construction (an upsert future plus a
/// resume binder), but pull-based rather than event-stream based.
class LocationService {
  LocationService({
    required Future<AutoUpsert?> upsert,
    required ForegroundBinder bindResume,
  }) : _upsert = upsert,
       _bindResume = bindResume;

  /// Interval used when the host enables location without naming one.
  static const Duration defaultInterval = Duration(minutes: 2);

  /// Smallest repeating interval, so an over-eager caller cannot drain the battery.
  static const Duration minInterval = Duration(seconds: 30);

  /// Clamp a requested interval. `Duration.zero` disables the loop (one fix only),
  /// anything else is floored.
  static Duration clampInterval(Duration requested) {
    if (requested <= Duration.zero) return Duration.zero;
    return requested < minInterval ? minInterval : requested;
  }

  final Future<AutoUpsert?> _upsert;
  final ForegroundBinder _bindResume;

  Duration _interval = defaultInterval;
  bool _enabled = false;
  bool _closed = false;
  bool _acquiring = false;
  Timer? _timer;
  void Function()? _disposeResume;

  /// Request permission and, if granted, turn location on: take a first fix now
  /// and start the foreground loop unless the interval is zero. Returns whether
  /// permission was granted. Idempotent.
  Future<bool> enable() async {
    if (_closed) return false;
    if (!await _ensurePermission()) return false;
    if (!_enabled) {
      _enabled = true;
      _disposeResume = _bindResume(_onResume);
    }
    await _tick();
    _schedule();
    return true;
  }

  /// Enable (requesting permission) and set the repeating interval. `0` keeps
  /// only the one-shot fix. Returns whether permission was granted.
  Future<bool> setIntervalMs(int ms) async {
    _interval = clampInterval(Duration(milliseconds: ms));
    return enable();
  }

  /// On-demand fix, ignored until the host has enabled location.
  Future<void> refreshNow() async {
    if (!_enabled || _closed) return;
    await _tick();
  }

  /// Stops observing for good. Synchronous, so a shutdown does not wait on the
  /// platform, and anything arriving afterwards is dropped.
  void close() {
    if (_closed) return;
    _closed = true;
    _enabled = false;
    _timer?.cancel();
    _timer = null;
    final dispose = _disposeResume;
    _disposeResume = null;
    dispose?.call();
  }

  Future<bool> _ensurePermission() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (error) {
      _debugLog('location permission request failed: $error');
      return false;
    }
  }

  void _onResume() {
    if (_closed || !_enabled) return;
    unawaited(_tick());
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (_closed || !_enabled || _interval <= Duration.zero) return;
    _timer = Timer(_interval, () {
      _timer = null;
      unawaited(_tickThenSchedule());
    });
  }

  Future<void> _tickThenSchedule() async {
    await _tick();
    _schedule();
  }

  Future<void> _tick() async {
    if (_closed || _acquiring) return;
    _acquiring = true;
    try {
      final position = await Geolocator.getCurrentPosition();
      if (_closed) return;
      final attributes = {
        'device_location': frb.FrbContextValue.numberList(
          Float64List.fromList([position.latitude, position.longitude]),
        ),
      };
      final upsert = await _upsert;
      upsert?.publish(attributes);
    } catch (error) {
      _debugLog('failed to read location: $error');
    } finally {
      _acquiring = false;
    }
  }
}

void _debugLog(String message) {
  assert(() {
    debugPrint('coproduct: $message');
    return true;
  }());
}
