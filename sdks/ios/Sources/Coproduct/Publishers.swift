// Detached observations that emit a fixed value with no live core subscription.
// Internal helpers used by the reactive-surface tests. A documented preview and
// test surface belongs to the first-class test and preview API

extension FlagObservation {
    // A detached observation that emits a single fixed value and never receives
    // core changes
    static func constant(_ value: T) -> FlagObservation<T> {
        FlagObservation<T>(key: "", initial: value)
    }
}

extension FlagBundleObservation {
    // A detached bundle observation seeded with a fixed snapshot. The empty keys
    // list signals that no live core subscription backs it
    static func constant(_ snapshot: [String: FlagDetailValue]) -> FlagBundleObservation {
        FlagBundleObservation(keys: [], initial: snapshot)
    }
}
