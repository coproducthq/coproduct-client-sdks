import 'dart:async';

import 'cancellation.dart';
import 'errors.dart';
import 'rust/api.dart' as frb;

/// Produces one static attribute value, or null if it cannot be collected. Null
/// is the only omission signal the collector understands, so a provider that
/// wants an absent field returns null rather than an empty value. Typed rather
/// than string-shaped because some attributes are numbers and must not
/// round-trip through a lossy string
typedef MetadataProvider = Future<frb.FrbContextValue?> Function();

/// Wraps a string-valued source, converting null or empty to the collector's
/// null omission signal. Empty is omission rather than a value: the core would
/// otherwise store a blank attribute that satisfies is_set while matching
/// nothing. A provider that is not string-valued is responsible for its own
/// emptiness rule, because only the string case has one
MetadataProvider stringProvider(Future<String?> Function() read) => () async {
      final value = await read();
      if (value == null || value.isEmpty) return null;
      return frb.FrbContextValue.string(value);
    };

/// Reports one provider's outcome for internal diagnostics: how long it ran and
/// whether its field was absent from the initial batch (it timed out, threw, or
/// returned null). Absence here is not permanent, since a provider settling
/// after the deadline still publishes through the late sink. Wired to surface
/// omissions so the shared startup budget can be tuned on real measurements
/// rather than guesses
typedef MetadataObserver = void Function(String field, Duration elapsed,
    {required bool omitted});

/// The injectable providers for each static attribute. Real implementations wrap
/// package_info_plus, device_info_plus, flutter_timezone, and dart:io
/// Tests substitute fakes
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
/// deadline, throws, or returns null omits only its field. Emptiness is not the
/// collector's concern: a string-valued source converts empty to null through
/// [stringProvider] before the collector sees it. The providers run
/// concurrently, so the budget is shared, not multiplied per field. This never
/// throws for a provider failure, only for cancellation via [cancel]. Values
/// are raw, the core normalizes them
///
/// The deadline bounds how long the caller waits, not whether a value can be
/// used. A provider that has not settled by the deadline is absent from the
/// returned map and is instead handed to [onLate] when it settles, so one slow
/// platform channel costs a field its place in the initial batch rather than
/// costing it the whole runtime. Each field reaches exactly one of the two,
/// never both. [onLate] is not called after cancellation, and a sink that
/// throws cannot affect collection. Providers are started even when the budget
/// is already spent, in which case every field arrives through [onLate]
Future<Map<String, frb.FrbContextValue>> collectStaticAttributes(
  MetadataProviders providers, {
  required Duration deadline,
  required Duration Function() clock,
  required CancellationSignal cancel,
  required void Function(String field, frb.FrbContextValue value) onLate,
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

  // Invoke providers and attach handlers using Future.sync so a provider that
  // throws synchronously fails only its field. Declared once and shared by both
  // the budgeted and exhausted paths so their late routing cannot drift apart
  List<Future<void>> startProviders() {
    final started = <Future<void>>[];
    fields.forEach((field, provider) {
      final sw = Stopwatch()..start();
      stopwatches[field] = sw;
      started.add(Future<frb.FrbContextValue?>.sync(provider).then((value) {
        sw.stop();
        if (value == null) {
          report(field, sw.elapsed, omitted: true);
          return;
        }
        if (!sealed) {
          attributes[field] = value;
          report(field, sw.elapsed, omitted: false);
          return;
        }
        // A cancelled collection is being abandoned, so there is nothing left
        // for a straggler to amend
        if (cancel.isCancelled) return;
        // The seal already reported this field as absent from the batch, so
        // routing it here publishes the value without a second report, which
        // would break the one-report-per-field invariant the observer rests on
        try {
          onLate(field, value);
        } catch (_) {
          // A sink failure must never affect collection, matching the rule the
          // diagnostic observer already follows
        }
      }, onError: (Object _, StackTrace _) {
        sw.stop();
        report(field, sw.elapsed, omitted: true);
      }));
    });
    return started;
  }

  if (cancel.isCancelled) {
    throw const CoproductInitializationCancelled();
  }
  final remaining = deadline - clock();
  if (remaining <= Duration.zero) {
    // Sealed before any provider is attached, so every result routes late. A
    // zero-duration timer would not do: microtasks drain before timer callbacks,
    // so an immediately settling provider would land in a batch already gone
    seal();
    // seal invokes the observer synchronously, which may cancel, so recheck
    // before returning so cancellation still takes precedence
    if (cancel.isCancelled) {
      throw const CoproductInitializationCancelled();
    }
    // Started but deliberately not awaited: a budget exhausted before collection
    // begins must not cost every field for the life of the runtime. Nothing in
    // the handler chain can throw, so the futures need no error sink of their
    // own: the late sink is guarded and the diagnostic reporter already is
    startProviders();
    return Map.unmodifiable(attributes);
  }

  final pending = startProviders();

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
