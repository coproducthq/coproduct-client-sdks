# AGENTS.md

Guidance for agents working in this repository.

## Purpose

This repository builds Coproduct's mobile SDKs (iOS, Android, React Native, Flutter) on a shared Rust evaluation core. Hold the Rust core and any implemented platform SDK to a production quality bar, with rigorous tests and review rather than feasibility-grade shortcuts. Where a platform's generated bindings build but its full ergonomic SDK is not yet written, that platform is still at the binding-validation stage: keep changes focused on proving the shared core can be consumed cleanly. Check the code and the plans under `docs/` for what is implemented rather than assuming.

## Repository Layout

- `core/` — `coproduct-core` Rust crate. Single source of business logic.
- `ffi/` — FFI bindings (`coproduct-ffi-uniffi` for iOS/Android/RN, `coproduct-ffi-frb` for Flutter).
- `sdks/<platform>/` — publishable SDK packages, one per platform. RN and Flutter nest under `coproduct/` because their packaging tooling (`bob`, `flutter create --template=plugin`) requires it.
- `examples/<platform>-demo/` and `sdks/<framework>/coproduct/example/` — **source-linked** sample apps. Pull the SDK as workspace code via composite build / SPM local ref / `path:` / `file:`. SDK author dev inner loop. Fast iteration; not a release gate.
- `consumer-tests/<platform>/` — **artifact-linked** verification apps. Install the SDK as a packaged release artifact (`.tgz`, `path:` to the SDK that mimics a published copy, SPM file: dep to a packaged zip, mavenLocal). Catch publish/install/autolink bugs that source-linked examples cannot. Release gate.
- `tests/` — cross-cutting fixtures (e.g. `bucketing_vectors.json`).
- `docs/` — design specs and implementation plans (under `docs/superpowers/plans/`).

A bug like the RN 0.82 + Xcode 26 `fmt` consteval failure, or the cargokit Gradle-9 `project.exec` removal, surfaces only in `consumer-tests/` because the existing `example/` Podfile/Gradle settings are pre-pinned to known-good versions.

## Building

Every SDK surface has a build script under `scripts/build/`. Use these rather than reconstructing the underlying commands. Each script gates the env vars it needs, resolves paths from any cwd, and emits a tagged `COPRODUCT_<surface>_<role>_STATUS pass=true` status line on success.

| Surface | Source-linked (Debug, dev inner loop) | Artifact-linked (Release, release gate) |
|---|---|---|
| iOS | `scripts/build/source-linked-ios-demo.sh` | `scripts/build/artifact-linked-ios-consumer-test.sh` |
| Android | `scripts/build/source-linked-android-demo.sh` | `scripts/build/artifact-linked-android-consumer-test.sh` |
| React Native (iOS) | `scripts/build/source-linked-rn-demo-ios.sh` | `scripts/build/artifact-linked-rn-consumer-test-ios.sh` |
| React Native (Android) | `scripts/build/source-linked-rn-demo-android.sh` | `scripts/build/artifact-linked-rn-consumer-test-android.sh` |
| Flutter (iOS) | `scripts/build/source-linked-flutter-demo-ios.sh` | `scripts/build/artifact-linked-flutter-consumer-test-ios.sh` |
| Flutter (Android) | `scripts/build/source-linked-flutter-demo-android.sh` | `scripts/build/artifact-linked-flutter-consumer-test-android.sh` |
| Flutter (iOS, device-running acceptance) | — | `scripts/build/artifact-linked-flutter-acceptance-ios.sh` |
| Flutter (Android, device-running acceptance) | — | `scripts/build/artifact-linked-flutter-acceptance-android.sh` |

The two acceptance gates additionally require a booted simulator/emulator device id, passed via `COPRODUCT_ACCEPTANCE_IOS_DEVICE` / `COPRODUCT_ACCEPTANCE_ANDROID_DEVICE` (see `flutter devices`); they consume an already-booted device and do not boot or provision one. Each emits `COPRODUCT_FLUTTER_ACCEPTANCE_<PLATFORM>_STATUS pass=true` on success.

FVM is maintainer-only release infrastructure, not a consumer requirement. The
Flutter floor-verification matrix and the release-preparation step run through
`scripts/build/with-fvm-toolchain.sh <flutter-version> -- <command>`, which pins
an exact FVM-managed Flutter and Dart onto `PATH` for every nested process and
purges the native config that would otherwise pin a global SDK, without mutating
the repository. A developer integrating Coproduct needs only the documented
supported Flutter/Dart versions; FVM never appears in the package README. See
`DEVELOPMENT.md` for the floor gate and the release-preparation procedure.

Android-touching scripts require `JAVA_HOME` (JDK 17), `ANDROID_HOME`, and `ANDROID_NDK_HOME` (`27.1.12297006`) to be set (except `scripts/package/rn-build-native.sh android` and `scripts/package/android-build-jnilibs.sh`, which need only `ANDROID_NDK_HOME` and `cargo-ndk`). iOS-touching scripts require Xcode and CocoaPods on PATH (except `scripts/package/rn-build-native.sh ios`, which needs only Xcode). Supporting packaging scripts live under `scripts/package/` (`ios-build-xcframework.sh` rebuilds `CoproductFFI.xcframework` from Rust source, `ios-spm-binary.sh` archives it, `ios-spm-fixture.sh` packages the consumer-test fixture). When a change alters the UniFFI-exposed surface, rebuild the xcframework (the source-linked iOS build does this automatically) so the iOS bindings link against the live symbols.

`DEVELOPMENT.md` documents the underlying manual commands for stage-by-stage debugging.

## Bundle ID and applicationId convention (scaffold demos and consumer-tests only)

Demo and consumer-test apps use the convention:

```
app.coproduct.<role>.<framework>
```

Where `<role>` is `demo` or `consumer` and `<framework>` is `ios`, `android`, `rn`, or `flutter`. Examples:

- `app.coproduct.demo.ios`
- `app.coproduct.demo.android`
- `app.coproduct.consumer.rn`
- `app.coproduct.consumer.flutter`

This convention applies ONLY to apps under `examples/` and `consumer-tests/`. SDK packages publish under separate ecosystem-specific coordinates (see per-SDK READMEs for the published names).

## Toolchain

- Rust `1.95.0`, edition `2024`. Workspace manifest at the repo root with `resolver = "2"`.
- The canonical target list lives in `rust-toolchain.toml` (3 Apple triples, 4 Android ABIs). Keep it aligned with the mobile surfaces.

## Current Dependency Choices

- UniFFI: use `uniffi = "0.31.1"` unless a concrete integration failure requires falling back.
- Flutter Rust Bridge: use `flutter_rust_bridge = "2.12.0"`.
- Core dependencies are kept lean. The current set is `async-trait`, `http`, `parking_lot`, `semver`, `serde`, `serde_json`, `sha2`, `thiserror`, `time`, `tracing`, `tracing-subscriber`, and `uuid`. Add a dependency only when a capability genuinely warrants it.

## Architecture Rules

- `coproduct-core` owns business logic and Rust-owned snapshot file I/O.
- Host languages provide only platform capabilities. The core defines the internal `Transport` and `SecureStore` traits; the host-facing FFI protocols that adapt to them are `HostTransport` and `HostSecureStore`. Hosts implement:
  - async `HostTransport`
  - async identity-only `HostSecureStore`
  - an ordered observation drain, not an observer callback. The core hands each
    subscription its complete current state through a synchronous non-blocking
    enqueue and never calls host code under its delivery lane. Flutter receives a
    `StreamSink` on Dart's event loop; the native wrappers await a Rust-owned
    mailbox (`pollNext`), which renders as Swift `async`, Kotlin `suspend`, and a
    React Native `Promise`. Developer callbacks therefore run off the delivery
    lane, so one that re-enters the SDK cannot deadlock delivery. This is distinct
    from the anyhow-Result rule for fallible host callbacks
- Snapshot cache must not cross the FFI boundary. Rust reads and writes `{cache_dir}/coproduct/snapshot.json` directly.
- FFI crates should expose local wrapper and adapter types, not raw `coproduct-core` types.
- Config is split by consumer. `coproduct_core::CoproductConfig` holds only values the core reads, validates, or persists. Host-behavior settings such as foreground refresh (`poll_on_foreground`) live on the host-facing configs (the platform SDK config and `FfiConfig`) and are consumed by the host timer, which reads its own copy; they are deliberately not relayed into the core config. `FfiConfig` intentionally carries host-behavior fields the core config does not, so a field that crosses the FFI without a core-side counterpart is by design, not an oversight. If the core ever owns a polling loop, such a field is re-added together with the code that reads it and its tests, never as a speculative field beforehand.
- `initialize` does not perform a network poll. The contract is: the client is constructed, the cache is loaded if present (so the provider starts `Ready` from cache, otherwise `NotReady`), and reads can immediately evaluate against cache or developer defaults. Driving polling is the host wrapper's responsibility, including the first poll. Do not assume `initialize` has fetched a fresh snapshot. A production wrapper that wants fresh values at launch must start polling right after `initialize` (call `poll_now()` / `pollNow()` or start a host timer whose first tick fires immediately) and, if it wants to wait for readiness, bound that wait with its own `startup_timeout` rather than expecting `initialize` to block. The iOS and Flutter wrappers already do this (immediate first tick plus a bounded wait for readiness); Android and React Native are scaffold-level and must adopt the same pattern when they grow real polling.
- Automatic context is bounded by one budget, not two. The Flutter host collects the static attributes (`platform`, `os_version`, `app_version`, `app_build`, `locale`, `timezone`) from the platform channels concurrently, fail-closed per field, bounded by the same `startup_timeout` convergence budget that bounds first-poll readiness. The budget is one monotonic deadline captured before native setup, so native loading, cache lookup, and construction consume part of it and only the remainder is available to metadata and readiness. At expiry the host stops waiting for convergence, freezes the metadata completed within the budget, then proceeds through mandatory publication and finalization before returning; those mandatory operations run outside the budget, so return time can exceed it. There is no separate internal metadata ceiling. The developer contract is one asynchronous `initialize`, one public `startupTimeout`, no manual plugin warm-up, and reliable immediate reads once it completes.

## Identifier unification principle

Use identical identifiers across all four SDK surfaces wherever the language permits. Use each language's idiomatic visibility mechanism for access control. Never let identifiers diverge for cosmetic reasons.

Examples this rule covers:

- Public method names: `initialize`, `getBool`, `getString`, `getNumber`, `getInt`, `getJSON`, `identify`, `signOut`, `setContext`, `updateAttributes`, `removeAttributes`, `addHandler`, `addEvaluationHook`, `shutdown` (observation methods are typed per flag type; see the deviations below)
- Public type names: `CoproductClient`, `CoproductConfig`, `CoproductSnapshot`, `Logger`, `HostTransport`, `HostSecureStore`, `EvaluationEvent`, `ProviderState`
- Thrown error names: `InvalidKeyType`, `UnsupportedSchemaVersion`, `InvalidTargetingKey`, `TransportError`, `SecureStoreError`
- Internal accessors: `bucketForVectors` (per-platform visibility mechanism: Swift `internal`, Kotlin `internal`, TS `/internal` subpath, Dart `lib/src/`)

Documented per-platform deviations:

- Swift uses all-caps initialisms: `getJSON` (not `getJson`) per Apple convention. Other platforms use camelCase `getJson`.
- Observation is typed per flag type rather than a single `observe`:
  `observeBool`, `observeString`, `observeInt`, `observeNumber`, and `observeJson`,
  consistent with the already-typed getters. Kotlin and React Native expose only
  `observe` for booleans today, which is a coverage gap rather than a naming
  divergence; the cross-platform public naming is reconciled when those platforms
  gain ergonomic reactive APIs.
- JSON observation is Flutter-specific. iOS has no `observeJSON`, because its
  bundle observation already carries JSON through `FlagDetailValue`.
- Flutter's observations are `FlagObservation<T>`, a `ValueListenable` seeded
  synchronously from the native session and disposed by its owner, plus
  `CoproductFlagBuilder` for widgets that should own that lifecycle themselves.
  `CoproductScope` is the Flutter client-access surface: a builder resolves the
  client from the nearest scope when `client` is omitted, and an explicit
  `client` still wins so an app carrying it in Provider, Riverpod, or BLoC needs
  no scope. Flutter deliberately has no multi-flag observation, which is
  additive and held until its shape is settled.
- Cancelling an observation is per platform, and none of them is the stream-primitive
  cancel: iOS releases the `FlagObservation` (its `deinit` ends the native session),
  Kotlin and React Native call `cancel()` on the returned handle, and Flutter calls
  `FlagObservation.dispose()`. A unified `Cancellable` type is deliberately not in the
  identifier list. On Flutter in particular, cancelling only a Dart stream subscription
  would leave the native session registered, which is why disposal is the documented verb.
- The OpenFeature `errorCode` enum (`FLAG_NOT_FOUND`, `TYPE_MISMATCH`, etc.) is a separate concept from thrown error names. The codes are data on `FlagEvaluationDetails.errorCode`, not catchable exception types.

## Evaluation semantics (cross-platform)

These are evaluation rules every platform SDK must match, not just the reference
core. They are documented here because a divergent re-implementation is a silent
parity bug. The authoritative implementation is `coproduct-core`.

- **Prerequisites are gates, not value comparisons.** A prerequisite is satisfied
  only when the prerequisite flag *actively* resolves to the required variation,
  meaning it is enabled, not paused, and resolves through a targeting match or
  fallthrough. A paused, disabled, off, errored, missing, or itself-prerequisite-
  failed prerequisite fails its dependents even if the off value it serves happens
  to equal the required variation. Turning a prerequisite off reliably turns off
  everything downstream. (The reference core keys this off the resolution reason
  being `TargetingMatch` or `Fallthrough`.)
- **A prerequisite match is on the variation key, not the value type.** An unknown-
  value-type flag still resolves to a well-defined variation key, so it can satisfy
  a prerequisite through the rule above even though its typed getters fail closed.
- **An unknown flag type fails closed for getters.** A flag whose `type` the SDK
  build does not understand is retained but returns the caller default from every
  typed getter and is omitted from observation.
- **`user_id` is identity, resolved from the targeting key.** A read of the
  `user_id` attribute always returns the targeting key, ahead of every layer, so a
  targeting rule on `user_id` matches the same identity that bucketing uses and a
  developer attribute cannot shadow it. `user_id` and `targetingKey` are reserved
  attribute names: the identity mutators (`identify` / `set_context` /
  `update_attributes`) drop them with a warning. Set identity through `identify` or
  `set_context`, never as an attribute.
- **Ingestion is per-flag tolerant.** One unparseable flag or segment is dropped
  (fail closed) while the rest of the snapshot applies. The top-level envelope
  stays strict. A malformed weight coalesces the way coverage does.
- **An empty `And` condition is vacuously true** and matches every context.
- **An unknown condition node fails the whole flag closed, strictly.** A condition
  type this SDK build does not understand trips `RULE_CIRCUIT_BREAK`. A rule whose
  condition tree contains an unknown node anywhere fails the flag closed for every
  context, before any rule is evaluated, so the break does not depend on rule order
  or on whether a given context's evaluation would short-circuit past the unknown
  child. In particular, a flag whose last rule carries an unknown node fails closed
  even for a context that matches an earlier valid rule. The walker computes this
  from the flag on each evaluation rather than caching it, so the guarantee holds
  for any flag the walker is handed, however it was constructed, not only for flags
  that went through snapshot ingestion.
- **A circuit break serves the off variation, not the caller default.** When a
  rule error trips `RULE_CIRCUIT_BREAK`, the flag resolves to its off variation.
  Every read surface serves that off value: the plain getters, the observers, and
  the detail getters' `value`. The detail getters still report `reason = ERROR`
  and `errorCode = RULE_CIRCUIT_BREAK` alongside the served off value. The caller
  default is served only when no variation resolves (not-ready, not-found, or a
  stored value whose type does not match the getter). This deliberately diverges
  from OpenFeature's error-serves-default rule, so an OpenFeature provider layered
  on this SDK maps a served-with-error result back to the default itself.

## Rust Practices

- Keep Rust code readable and explicit. Prefer simple structs and conversion helpers over clever abstractions.
- Do not hold a `MutexGuard` across `.await`.
- Keep all FFI/core record conversion in one obvious adapter section per FFI crate.
- Never name an error-enum variant field `message`. UniFFI maps each error variant to a Kotlin class that extends `Throwable`, which already defines `message`, so a field named `message` produces a conflicting declaration and the generated Kotlin will not compile. Swift is unaffected, so the breakage is silent until a Kotlin build. Use `reason` or another name.
- Run `cargo fmt --all` before claiming Rust work is complete.
- Run `cargo build --workspace` and `cargo test --workspace` for Rust changes. Use the whole workspace, not `cargo test -p coproduct-core`: the FFI crates carry their own tests (for example the `ffi/coproduct-ffi-uniffi` binding-generation tests that read committed paths), so a single-package run passes while the workspace is red.
- Name Rust test files after stable SDK behavior, not the implementation plan, checkpoint, task, or historical reason the test was introduced. Use lowercase `snake_case` domain names such as `pipeline_prerequisites.rs`, `snapshot_ingestion_tolerance.rs`, `observer_fanout_delivery_order.rs`, and `config_validation.rs`. Avoid names like `pipeline_step_6_prerequisites.rs`, `task_4_12_smoke.rs`, `checkpoint_2_snapshot.rs`, or `context_placeholder.rs`. When renaming tests, preserve behavior and keep the filename aligned with what the tests actually assert.
- When you move or rename a path that is referenced by convention (the generated bindings directory, a fixture, a cache location), grep the whole repo for the old path before claiming done. The iOS generated bindings path alone is referenced by `scripts/audit/swift-binding-check.sh`, `scripts/package/ios-build-xcframework.sh`, `scripts/package/ios-spm-fixture.sh`, `sdks/ios/BUILDING.md`, the `ffi/coproduct-ffi-uniffi` binding-generation test, and `.gitattributes`.

## Public Source Hygiene

This repository is public-facing. Code comments, doc comments, public API docs,
commit messages intended for merge, and user-visible strings should describe
product behavior and stable engineering rationale, not internal execution
history.

Avoid internal planning references such as checkpoint names, task numbers, plan
labels, subagent notes, temporary implementation history, or phrases like "later
task", "was placeholder", or "preserved from C1". If historical context is
useful, rewrite it as stable technical rationale.

Good examples:

- "The schema-version fence parses only `schemaVersion` before full snapshot
  deserialization."
- "Unknown condition nodes preserve their wire tag for diagnostics."

Avoid examples:

- "Preserved from Checkpoint 1."
- "Task 2.6 fills this in."
- "Later checkpoints replace this."

Comment and doc terminology. Reserve `user` for the evaluated end-user (the targeting subject: `userId`, `targetingKey`, the evaluation context), never the integrator. Use `caller` for who invoked a function or supplied a value, and `public` or `developer` for the API audience. Do not use `customer`.

## Release Identity

Each SDK carries a version identity in four places that must agree at release: the
install instructions (the repo URL and version a developer copies), the published
package or release tag, the built artifact version, and the `User-Agent` the SDK
sends (`coproduct-<platform>/<version>`, set in the wrapper). These are the same
concern seen from four angles, and they drift because they live in different
files.

Invariants (a release-blocking check, applied per platform: iOS, Android, React
Native, Flutter):

- A development branch keeps an explicit dev `User-Agent` such as
  `coproduct-ios/0.0.1-dev`. Do not raise it to a release version until that
  platform's package or tag is actually published.
- A public release must not ship a `-dev` `User-Agent`, and the `User-Agent`
  version must equal the published package version for that platform.
- Install docs must not present a copy-pasteable command for a repo or tag that is
  not yet published. Before a public release, update the install docs, the
  package/release tag, the artifact version, and the `User-Agent` together for
  that platform, in one change.

Where each lives today (keep this list current as platforms ship): iOS
`User-Agent` is `coproductUserAgent` in `sdks/ios/Sources/Coproduct/Coproduct.swift`
and the install doc is `sdks/ios/README.md`; Android and React Native set a
`USER_AGENT` constant in their wrapper; Flutter's is `coproductUserAgent` in
`sdks/flutter/coproduct/lib/src/sdk_version.dart`, passed through the FRB
`initialize` call. See `DEVELOPMENT.md` for the release checklist.

### Breaking low-level observer migration

The generated observer protocol was replaced, not extended. The UniFFI
`FlagObserver` callback interface and the `Subscription` object are gone, as is the
FRB `observe` function; registration now returns a typed session carrying its own
evaluated seed, and delivery is drained rather than pushed. None of these SDKs had
been published, so this landed as a single breaking change with every in-repo
consumer migrated in the same branch rather than as a dual-protocol shim. A
developer implementing the raw generated observer directly must migrate; the
wrapped public APIs on each platform shield ordinary consumers.

## UniFFI Notes

- Avoid FFI parameter names that are C/Swift keywords. In particular, do not use `default`. Use `default_value`.
- Verify more than Rust compilation. A UniFFI crate is not healthy until binding generation works:
  ```bash
  cargo run -p coproduct-ffi-uniffi --features uniffi/cli --bin uniffi-bindgen -- \
    generate \
    --library target/debug/libcoproduct_ffi_uniffi.dylib \
    --language swift \
    --out-dir /tmp/swift-bindings
  ```
- The generated Swift, header, and modulemap are expected outputs.
- Regenerate the React Native bindings with the locally installed `uniffi-bindgen-react-native` (not on PATH, it lives at `sdks/react-native/coproduct/node_modules/.bin/ubrn`). After `cargo build -p coproduct-ffi-uniffi`, run from the repo root:
  ```bash
  sdks/react-native/coproduct/node_modules/.bin/ubrn generate jsi bindings \
    --library --crate coproduct_ffi_uniffi \
    --ts-dir sdks/react-native/coproduct/src/generated \
    --cpp-dir sdks/react-native/coproduct/cpp/generated \
    target/debug/libcoproduct_ffi_uniffi.dylib
  ```
  The RN native ABI changes whenever the FFI surface does, so verify with a
  native build (`scripts/build/source-linked-rn-demo-android.sh`), not just a
  typecheck. Before that build, refresh the gitignored static libraries the
  example links against. Stale local copies surface as undefined `uniffi_*`
  symbols at link time:
  ```bash
  scripts/package/rn-build-native.sh android
  ```
  This rebuilds the four jniLibs. It needs only `ANDROID_NDK_HOME` and `cargo-ndk`,
  a deliberately narrower requirement than the Android consumer gate.
  The RN iOS framework is a separate gitignored artifact. `ubrn build` writes it
  to `build/CoproductFFI.xcframework`, but the podspec vendors and `yarn pack`
  bundles `ios/CoproductFFI.xcframework`, so the build output must be copied into
  place. Refresh it after an FFI surface change by running, from the repo root:
  ```bash
  scripts/package/rn-build-native.sh ios
  ```
  This runs the ubrn build and copies the result into place, and builds both the
  device and universal simulator slices.
  The artifact-linked RN consumer-test gates fail fast through
  `scripts/audit/ffi-symbol-freshness.sh` when these committed libraries are
  stale relative to the FFI surface, rather than rebuilding them inside the gate.

## Flutter Rust Bridge Notes

The Flutter plugin lives at `sdks/flutter/coproduct` and consumes the single FRB crate at `ffi/coproduct-ffi-frb` (parallel to how `sdks/react-native` consumes `ffi/coproduct-ffi-uniffi`). It does not contain its own Rust crate. Both `flutter_rust_bridge.yaml` and the cargokit config in `android/build.gradle` plus `ios/coproduct.podspec` point at `../../../ffi/coproduct-ffi-frb` by relative path. The demo builds and runs on the iOS simulator and Android emulator.

Load-bearing invariants. Breaking any of these breaks the build or runtime:

- The FRB crate package name is `coproduct_ffi_frb` with underscores, even though the directory is `coproduct-ffi-frb`. cargokit derives the built library filename from the package name verbatim, so a dashed package makes it look for `libcoproduct-ffi-frb.a` while cargo emits underscores. Do not rename it to dashes for symmetry with `coproduct-ffi-uniffi`.
- The exported API lives in `ffi/coproduct-ffi-frb/src/api.rs`, and `lib.rs` is only `mod frb_generated; pub mod api;`. FRB injects `frb_generated.rs` at the crate root, and `rust_input: crate::api` must point at a submodule, never the crate root. Do not move the API back into `lib.rs`.
- Host callbacks use `anyhow::Result<T>`, not custom error enums. FRB does not support a custom error type as the error of a `DartFnFuture<Result<T, E>>`. The Rust adapters convert `anyhow::Error` into the typed core errors. This is an intentional divergence from the UniFFI crate, which keeps typed errors.
- Free functions take the client by reference (`&CoproductClientHandle`) and `initialize` / the typed observation registrations (`observe_bool` and its siblings) return bare handles, not `Arc<...>`. Passing the handle by value makes FRB move-and-dispose the Dart handle (`DroppableDisposedException`), and returning `Arc<...>` emits an `Arc`-prefixed Dart type that mismatches the borrowed-parameter type.
- The plugin is an FFI plugin: `pubspec.yaml` declares `ffiPlugin: true` for android and ios with no `pluginClass`, and there are no Kotlin/Swift plugin classes. FRB loads the native library directly.
- On iOS and macOS the Dart wrapper inits with `RustLib.init(externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true))`, because cargokit force-loads the static library into the app executable and the default Apple loader looks for a non-existent `<stem>.framework`. Android uses the default loader (`lib<crate>.so`).
- Regenerate bindings with `flutter_rust_bridge_codegen generate` after editing `api.rs`. The codegen binary is pinned to the same version as the `flutter_rust_bridge` crate (`2.12.0`). Codegen rewrites `frb_generated.rs`, `lib/src/rust/*`, and re-injects the `mod frb_generated;` line.
- Run `cargo fmt --all` after regenerating FRB bindings. `rustfmt.toml` lists `frb_generated.rs` in `ignore`, but `ignore` is a nightly-only feature, so on the stable toolchain rustfmt still formats the file. The committed `frb_generated.rs` must be fmt-formatted or `cargo fmt --all --check` fails the green gate, and the codegen output is not fmt-clean on its own.
- Avoid FFI parameter names that are Dart reserved words. Do not use `default`; use `default_value`. This matches the UniFFI crate, where `default` is also a Swift keyword.

Android toolchain. cargokit upstream calls `project.exec()`, removed in Gradle 9; the vendored cargokit at `sdks/flutter/coproduct/cargokit/gradle/plugin.gradle` carries a `ProcessBuilder` patch (see [FRB issue #3007](https://github.com/fzyzcjy/flutter_rust_bridge/issues/3007), marked wontfix upstream) so the SDK works on Gradle 9. The patch must be re-applied if the vendored cargokit is updated; the file carries an inline comment marking the patched region. `sdks/flutter/coproduct/example/` and `sdks/react-native/coproduct/example/` share **Gradle 8.14 + JDK 17** from the React Native example template's defaults. The React Native example stays on **AGP 8.12.0**; the Flutter example is on **AGP 8.12.1**, the floor `device_info_plus` and `package_info_plus` require. Native Android source-linked demos use **Gradle 9.4.1 + JDK 17 + AGP 9.2.1** to match Android Studio Panda's generated defaults. `consumer-tests/flutter/` runs on bleeding-edge **Gradle 9.1.0 + AGP 9.0.1 + Kotlin 2.3.20** to verify the patched cargokit holds for real adopters on modern toolchains. The SDK's `compileSdkVersion` is `36.1` for native Android and `36` for Flutter's current AGP path. cargokit downloads its own NDK if the configured one is absent. Do not enable Swift Package Manager for the plugin: FRB needs the CocoaPods `Classes/` layout, and Flutter only warns about the missing SwiftPM support.

## iOS Notes

- `CoproductFFI.xcframework` is generated scaffold output from static Rust libraries.
- The iOS Swift package should use Swift 5 language mode for now. UniFFI-generated Swift currently trips Swift 6 strict-concurrency checks around static callback vtable pointers.
- `swift build` targets macOS by default and is not the right verification for this iOS-only binary target. Any ad-hoc verification should use `xcodebuild -destination 'generic/platform=iOS Simulator'` like the build scripts do.
- The generated UniFFI Swift bindings live in their own `CoproductFFI` target under `sdks/ios/Sources/CoproductFFI/`. That target is deliberately not a library product, which keeps the raw generated surface (the top-level `initialize`, `CoproductClient`, `FfiConfig`, `bucketForVectors`, the converters, and the handle types) out of autocomplete and out of a plain `import Coproduct`. This is hidden by default, not an enforced boundary: SwiftPM builds every target's module into the products directory, so `import CoproductFFI` still resolves for a determined consumer. Do not rely on the split for anything security-shaped. The wrapper re-exposes the genuinely public generated types via per-declaration `@_exported import` in `Sources/Coproduct/PublicFFISurface.swift` (per-declaration rather than typealiases so enum cases and struct members come across; `@_exported` is an accepted underscored-attribute risk). Add a line there when a new generated type legitimately joins the public contract, and never make `CoproductFFI` a product.
- When the FFI surface changes, regenerate and verify the committed Swift bindings with `scripts/audit/swift-binding-check.sh`. It rebuilds the crate, regenerates the bindings in place under `Sources/CoproductFFI/`, runs the name audit, typechecks the bindings plus the `Tests/BindingSmoke/` smokes, and emits `COPRODUCT_IOS_BINDING_STATUS pass=true`. Commit the resulting `CoproductFFI/` diff.
- The binding check does not rebuild the xcframework, and neither does the `xcodebuild test` path. Regenerating the bindings without rebuilding `CoproductFFI.xcframework` leaves the committed bindings ahead of the linked binary, which surfaces at test runtime as a `UniFFI API checksum mismatch`, not as a build error. After a binding regen, rebuild the xcframework with `scripts/package/ios-build-xcframework.sh` (the source-linked iOS build also rebuilds it) before running the test target.
- Detailed iOS build commands live in `sdks/ios/BUILDING.md`.

## Android Notes

- If an Android virtual device is needed for scaffold validation, use a reusable generic name such as `Android_API_36_ARM64` rather than an SDK-specific name.
- The canonical native source-linked demo is at `examples/android-demo`. Keep this as the only native Android example path unless a future task explicitly needs a separate comparison project.
- Generate Kotlin bindings with the workspace `uniffi-bindgen` binary into `sdks/android/src/main/kotlin`. The generated package is `uniffi.coproduct_ffi_uniffi` and the public wrapper lives in `app.coproduct`.
- Android UniFFI bindings need JNA 5.12.0+ and kotlinx coroutines (for suspend functions and foreign callbacks). The module uses `net.java.dev.jna:jna:5.12.0@aar`.
- Build the native Android `.so` files with `scripts/package/android-build-jnilibs.sh`, which runs `cargo ndk -o` for `arm64-v8a`, `armeabi-v7a`, `x86`, and `x86_64` into `sdks/android/src/main/jniLibs`. These libraries are gitignored. The native Android SDK loads them dynamically through JNA, so a stale copy surfaces at runtime as a JNA load error or a UniFFI checksum mismatch, not at link time. The artifact-linked Android consumer gate fails fast through `scripts/audit/ffi-symbol-freshness.sh` when they are stale.
- Native Android follows the Android Studio Panda generated shape. `sdks/android` uses `com.android.library` plus `com.android.built-in-kotlin`, not the legacy `org.jetbrains.kotlin.android` plugin. Do not reintroduce `android.builtInKotlin=false` or `android.newDsl=false` unless a concrete AGP regression requires it. Pinned versions: Gradle 9.4.1, AGP 9.2.1, Kotlin 2.2.10, compile SDK 36.1.
- Historical note on the JDK 17 pin. The `create-react-native-library` template shipped Gradle 9.0.0, and Gradle 9 with JDK 21 fails at configuration time with `JvmVendorSpec does not have member field 'IBM_SEMERU'`. Gradle 8.14 with JDK 17 does not hit this. The RN and Flutter example wrappers are pinned to 8.14 for that reason.
- After switching JDKs, run `./gradlew --stop` so a daemon started under the wrong JDK is not reused.

## Validation Anchors

- Golden bucketing vectors live in `tests/bucketing_vectors.json`. Treat vector mismatches as implementation bugs, not permission to change expected values.
- iOS package build is not the same as a full demo validation. The full validation runs the demo app on a simulator exercising initialize, host callbacks, sync `getBool`, observer registration, and provider state.

## Generated And Build Output

- Do not hand-edit generated output: `target/`, the UniFFI Swift bindings under `sdks/ios/Sources/CoproductFFI/`, the UniFFI Kotlin bindings under `sdks/android/src/main/kotlin/uniffi/`, the React Native bindings under `sdks/react-native/coproduct/cpp/generated/` and `sdks/react-native/coproduct/src/generated/`, and the Flutter Rust Bridge output (`ffi/coproduct-ffi-frb/src/frb_generated.rs` and `sdks/flutter/coproduct/lib/src/rust/`). Regenerate with the per-platform commands above. If editing generated output becomes necessary, document why.
- `sdks/ios/CoproductFFI.xcframework` is generated scaffold output and can be large in debug mode.
- The `.gitignore` covers everything else (`.gradle/`, `.kotlin/`, `.swiftpm/`, `xcuserdata/`, `build/`, `local.properties`, plus the usual `.DS_Store` / `*.xcuserstate`). Don't add tracked equivalents.
