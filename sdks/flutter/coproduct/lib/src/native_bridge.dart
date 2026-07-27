import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart'
    show ExternalLibrary;
import 'package:path_provider/path_provider.dart';

import 'rust/api.dart' as frb;
import 'rust/frb_generated.dart';

/// The native operations the host runtime performs, behind an interface so the
/// orchestration is unit-tested with a fake and the production path binds to
/// flutter_rust_bridge. [H] is the opaque client handle, the real FRB handle in
/// production and a stand-in in tests.
abstract interface class NativeBridge<H extends Object> {
  /// Loads the native library once per isolate generation. Idempotent.
  Future<void> ensureInitialized();

  /// The directory the core reads and writes its snapshot under.
  Future<String> cacheDirectory();

  /// Constructs the core client, resolving identity from the secure store and
  /// loading any cached snapshot. Does not poll.
  Future<H> initialize({
    required String sdkKey,
    required String userAgent,
    required frb.FfiConfig config,
    required String cacheDir,
    required FutureOr<frb.HttpResponse> Function(frb.HttpRequest) transportRequest,
    required FutureOr<String?> Function(String) secureRead,
    required FutureOr<void> Function(String, String) secureWrite,
  });

  /// Installs the auto-populated attributes on the core context.
  Future<void> setAutoPopulatedAttributes(
      H handle, Map<String, frb.FrbContextValue> attributes);

  /// The current provider state, read synchronously from core memory.
  frb.ProviderState state(H handle);

  /// Performs one network poll and reports the outcome.
  Future<frb.PollOutcome> pollNow(H handle);

  /// Sets the core shutdown latch and tears the client down.
  Future<void> shutdown(H handle);
}

/// The production NativeBridge over flutter_rust_bridge. Owns the single-flight
/// RustLib load and the application cache directory. On iOS and macOS cargokit
/// force-loads the static library into the app executable, so FRB is pointed at
/// the process image rather than a non-existent framework bundle.
class FrbNativeBridge implements NativeBridge<frb.CoproductClientHandle> {
  bool _libraryReady = false;

  @override
  Future<void> ensureInitialized() async {
    if (_libraryReady) return;
    if (Platform.isIOS || Platform.isMacOS) {
      await RustLib.init(
        externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
      );
    } else {
      await RustLib.init();
    }
    _libraryReady = true;
  }

  @override
  Future<String> cacheDirectory() async =>
      (await getApplicationCacheDirectory()).path;

  @override
  Future<frb.CoproductClientHandle> initialize({
    required String sdkKey,
    required String userAgent,
    required frb.FfiConfig config,
    required String cacheDir,
    required FutureOr<frb.HttpResponse> Function(frb.HttpRequest) transportRequest,
    required FutureOr<String?> Function(String) secureRead,
    required FutureOr<void> Function(String, String) secureWrite,
  }) =>
      frb.initialize(
        sdkKey: sdkKey,
        userAgent: userAgent,
        config: config,
        cacheDir: cacheDir,
        transportRequest: transportRequest,
        secureRead: secureRead,
        secureWrite: secureWrite,
      );

  @override
  Future<void> setAutoPopulatedAttributes(
          frb.CoproductClientHandle handle,
          Map<String, frb.FrbContextValue> attributes) =>
      frb.setAutoPopulatedAttributes(handle: handle, attributes: attributes);

  @override
  frb.ProviderState state(frb.CoproductClientHandle handle) =>
      frb.state(client: handle);

  @override
  Future<frb.PollOutcome> pollNow(frb.CoproductClientHandle handle) =>
      frb.pollNow(client: handle);

  @override
  Future<void> shutdown(frb.CoproductClientHandle handle) =>
      frb.shutdown(client: handle);
}
