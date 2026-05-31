# Coproduct Client SDKs

This repository holds the iOS, Android, React Native, and Flutter SDKs for [Coproduct](https://coproduct.app), a feature flag and experimentation platform. All four SDKs share a single Rust evaluation engine via FFI bindings, so flag bucketing decisions are byte-identical across every platform.

## Repository structure

| Directory | Purpose |
|---|---|
| `core/coproduct-core/` | Pure Rust evaluation engine, snapshot cache, identity lifecycle. No FFI macros. |
| `ffi/coproduct-ffi-uniffi/` | UniFFI crate that produces C ABI bindings consumed by iOS, Android, and React Native. |
| `ffi/coproduct-ffi-frb/` | `flutter_rust_bridge` crate that produces Dart bindings for Flutter. |
| `sdks/ios/` | Swift package, ergonomic wrapper around UniFFI-generated Swift. |
| `sdks/android/` | Android library, ergonomic wrapper around UniFFI-generated Kotlin. |
| `sdks/react-native/coproduct/` | React Native package, TurboModule via `uniffi-bindgen-react-native`. |
| `sdks/flutter/coproduct/` | Flutter plugin, Dart bindings via `flutter_rust_bridge`. |
| `examples/<platform>-demo/` | Source-linked sample apps (native iOS, native Android). |
| `sdks/<framework>/coproduct/example/` | Source-linked sample apps for RN and Flutter (nested per framework convention). |
| `consumer-tests/<platform>/` | Artifact-linked release-verification apps. Install the SDK as a packaged release. |
| `tests/` | Cross-cutting fixtures (e.g. `bucketing_vectors.json`). |
| `scripts/` | Shell helpers (packaging, consumer-test orchestration). |
| `docs/` | Documentation. |

## Quickstart

To build and run any platform's sample app, see [DEVELOPMENT.md](./DEVELOPMENT.md) for the prerequisites and per-surface commands.

For SDK-specific documentation:
- [iOS SDK](./sdks/ios/README.md)
- [Android SDK](./sdks/android/README.md)
- [React Native SDK](./sdks/react-native/coproduct/README.md)
- [Flutter SDK](./sdks/flutter/coproduct/README.md)

## License

Apache License 2.0. See [LICENSE](./LICENSE).
