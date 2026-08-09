//! Guards that the committed iOS Swift bindings expose every typed getter and
//! detail record. Reads the in-tree generated source so it stays in lock-step
//! with the FFI surface without spawning a build

use std::path::PathBuf;

fn generated_swift() -> PathBuf {
    let manifest = env!("CARGO_MANIFEST_DIR").parse::<PathBuf>().unwrap();
    manifest
        .parent()
        .and_then(|p| p.parent())
        .map(|p| p.join("sdks/ios/Sources/CoproductFFI/coproduct_ffi_uniffi.swift"))
        .expect("workspace root resolves from the ffi crate")
}

#[test]
fn committed_swift_bindings_expose_typed_getters_and_details() {
    let src = std::fs::read_to_string(generated_swift()).expect("committed swift bindings exist");
    for symbol in [
        "func getBool(",
        "func getString(",
        "func getInt(",
        "func getNumber(",
        "func getJson(",
        "func getBoolDetails(",
        "func getStringDetails(",
        "func getIntDetails(",
        "func getNumberDetails(",
        "func getJsonDetails(",
        "FlagEvaluationDetailsBool",
        "FlagEvaluationDetailsString",
        "FlagEvaluationDetailsInt",
        "FlagEvaluationDetailsNumber",
        "FlagEvaluationDetailsJson",
    ] {
        assert!(
            src.contains(symbol),
            "committed bindings missing symbol: {symbol}"
        );
    }
}

#[test]
fn committed_swift_bindings_expose_lifecycle_surface() {
    let src = std::fs::read_to_string(generated_swift()).expect("committed swift bindings exist");
    for symbol in [
        "func state(",
        "func pollNow(",
        "enum ProviderState",
        "enum PollOutcome",
    ] {
        assert!(
            src.contains(symbol),
            "committed bindings missing symbol: {symbol}"
        );
    }
}

#[test]
fn committed_swift_bindings_expose_lifecycle_handler_surface() {
    let src = std::fs::read_to_string(generated_swift()).expect("committed swift bindings exist");
    for symbol in [
        "func addHandler",
        "func addEvaluationHook",
        "func setEvaluationListener",
        "func shutdown",
        "enum LifecycleEvent",
        "enum EvaluationStage",
        "enum EvaluationReason",
        "enum FlagValue",
        "struct EvaluationEvent",
        "struct HookContext",
    ] {
        assert!(
            src.contains(symbol),
            "committed bindings missing symbol: {symbol}"
        );
    }
}

#[test]
fn committed_swift_bindings_expose_identity_surface() {
    let src = std::fs::read_to_string(generated_swift()).expect("committed swift bindings exist");
    for symbol in [
        "func identify(",
        "func signOut(",
        "func setContext(",
        "func updateAttributes(",
        "func removeAttributes(",
        "func previousAnonymousId(",
        "enum ContextValue",
        "enum FfiIdentityError",
    ] {
        assert!(
            src.contains(symbol),
            "committed bindings missing symbol: {symbol}"
        );
    }
}

#[test]
fn committed_swift_bindings_expose_typed_observations() {
    let src = std::fs::read_to_string(generated_swift()).expect("committed swift bindings exist");
    for symbol in [
        "func observeBool(",
        "func observeString(",
        "func observeInt(",
        "func observeNumber(",
        "func observeJson(",
        "func observeBundle(",
        "func pollNext(",
        "enum BoolDelivery",
        "enum BundleDelivery",
    ] {
        assert!(
            src.contains(symbol),
            "committed bindings missing symbol: {symbol}"
        );
    }
}
