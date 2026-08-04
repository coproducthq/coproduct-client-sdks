import 'dart:async';

import 'cancellation.dart';
import 'errors.dart';
import 'rust/api.dart' as frb;

/// Produces one static attribute value, or null if it cannot be collected
typedef MetadataProvider = Future<String?> Function();

/// Reports one provider's outcome for internal diagnostics: how long it ran and
/// whether its field was omitted (it timed out, threw, or returned null or
/// empty). Wired to surface omissions so the shared startup budget can be tuned
/// on real measurements rather than guesses
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

/// Collects the static device and app attributes, best-effort and fail-closed
/// per field, bounded by an absolute [deadline] on the shared [clock] rather
/// than a fixed per-provider timeout. A provider that has not settled by the
/// deadline, throws, or returns null or empty omits only its field. The
/// providers run concurrently, so the budget is shared, not multiplied per
/// field. This never throws for a provider failure, only for cancellation via
/// [cancel]. Values are raw, the core normalizes them
Future<Map<String, frb.FrbContextValue>> collectStaticAttributes(
  MetadataProviders providers, {
  required Duration deadline,
  required Duration Function() clock,
  required CancellationSignal cancel,
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
  final reported = <String>{};
  final stopwatches = <String, Stopwatch>{};

  void report(String field, Duration elapsed, {required bool omitted}) {
    if (!reported.add(field)) return; // exactly once per field
    try {
      observe?.call(field, elapsed, omitted: omitted);
    } catch (_) {
      // Diagnostics must never affect collection
    }
  }

  var sealed = false;
  final sealed$ = Completer<void>();
  void seal() {
    if (sealed) return;
    sealed = true;
    // Report every field that has not settled as omitted, with the time spent
    // before giving up, so a wedged provider still produces a useful diagnostic
    for (final field in fields.keys) {
      report(field, stopwatches[field]?.elapsed ?? Duration.zero, omitted: true);
    }
    if (!sealed$.isCompleted) sealed$.complete();
  }

  // Cancellation and an exhausted budget are decided synchronously before any
  // provider is invoked, so no new platform-channel work starts once the budget
  // is gone
  if (cancel.isCancelled) {
    throw const CoproductInitializationCancelled();
  }
  final remaining = deadline - clock();
  if (remaining <= Duration.zero) {
    seal();
    // seal invokes the observer synchronously, which may cancel, so recheck
    // before returning so cancellation still takes precedence
    if (cancel.isCancelled) {
      throw const CoproductInitializationCancelled();
    }
    return Map.unmodifiable(attributes);
  }

  // Invoke providers and attach handlers before arming the deadline timer, using
  // Future.sync so a provider that throws synchronously fails only its field
  final pending = <Future<void>>[];
  fields.forEach((field, provider) {
    final sw = Stopwatch()..start();
    stopwatches[field] = sw;
    pending.add(Future<String?>.sync(provider).then((value) {
      sw.stop();
      if (!sealed && value != null && value.isNotEmpty) {
        attributes[field] = frb.FrbContextValue.string(value);
        report(field, sw.elapsed, omitted: false);
      } else {
        report(field, sw.elapsed, omitted: true);
      }
    }, onError: (Object _, StackTrace _) {
      sw.stop();
      report(field, sw.elapsed, omitted: true);
    }));
  });

  final deadlineTimer = Timer(remaining, seal);
  unawaited(cancel.whenCancelled.then((_) => seal()));

  await Future.any([Future.wait(pending), sealed$.future]);
  deadlineTimer.cancel();
  seal(); // freeze if every provider settled before the deadline

  // Cancellation outranks a deadline-partial result, rechecked synchronously
  // before returning regardless of the seal reason
  if (cancel.isCancelled) {
    throw const CoproductInitializationCancelled();
  }
  return Map.unmodifiable(attributes);
}
