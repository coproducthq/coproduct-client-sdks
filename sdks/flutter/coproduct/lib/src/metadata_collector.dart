import 'rust/api.dart' as frb;

/// Produces one static attribute value, or null if it cannot be collected
typedef MetadataProvider = Future<String?> Function();

/// Reports one provider's outcome for internal diagnostics: how long it ran and
/// whether its field was omitted (it timed out, threw, or returned null or
/// empty). Wired to surface omissions so the collection ceiling can be tuned on
/// real measurements rather than guesses
typedef MetadataObserver = void Function(String field, Duration elapsed,
    {required bool omitted});

/// The injectable providers for each static attribute. Real implementations wrap
/// package_info_plus, device_info_plus, flutter_timezone, and dart:io
/// Tests substitute fakes. device_type is deliberately absent, no reliable
/// cross-platform classifier exists
class MetadataProviders {
  const MetadataProviders({
    required this.platform,
    required this.osVersion,
    required this.appVersion,
    required this.appBuild,
    required this.locale,
    required this.timezone,
  });

  final MetadataProvider platform;
  final MetadataProvider osVersion;
  final MetadataProvider appVersion;
  final MetadataProvider appBuild;
  final MetadataProvider locale;
  final MetadataProvider timezone;
}

/// Collects the static device and app attributes, best-effort and fail-closed per
/// field: each provider is bounded by [perProviderTimeout], and a provider that
/// times out, throws, or returns null or empty omits only its field. The
/// providers run concurrently, so the aggregate bound is one timeout, not their
/// sum. This never throws, so it cannot fail initialization. Values are raw, the
/// core normalizes them
Future<Map<String, frb.FrbContextValue>> collectStaticAttributes(
  MetadataProviders providers, {
  required Duration perProviderTimeout,
  MetadataObserver? observe,
}) async {
  final fields = <String, MetadataProvider>{
    'platform': providers.platform,
    'os_version': providers.osVersion,
    'app_version': providers.appVersion,
    'app_build': providers.appBuild,
    'locale': providers.locale,
    'timezone': providers.timezone,
  };
  final attributes = <String, frb.FrbContextValue>{};
  await Future.wait(fields.entries.map((entry) async {
    final stopwatch = Stopwatch()..start();
    var omitted = true;
    try {
      final value = await entry.value().timeout(perProviderTimeout);
      if (value != null && value.isNotEmpty) {
        attributes[entry.key] = frb.FrbContextValue.string(value);
        omitted = false;
      }
    } catch (_) {
      // Fail closed, omit this field rather than fail collection
    } finally {
      stopwatch.stop();
      try {
        observe?.call(entry.key, stopwatch.elapsed, omitted: omitted);
      } catch (_) {
        // Diagnostics must never affect collection, so a throwing observer is
        // contained the same way a failing provider is
      }
    }
  }));
  return attributes;
}
