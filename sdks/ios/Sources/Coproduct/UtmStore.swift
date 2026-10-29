import CoproductFFI
import Foundation

// Persists UTM acquisition attribution in UserDefaults, which participates in
// device backup by design: attribution survives a device migration the same
// way first_seen_at does. Two attributes per UTM key: the bare key
// (utm_source, utm_medium, utm_campaign, utm_term, utm_content) is first-touch,
// frozen on the first value ever captured, and the key_last variant is
// last-touch, overwritten on every capture. Storage is two dictionary blobs,
// one per touch kind, keyed by the UTM key, which round-trips through
// UserDefaults' native dictionary support without needing per-key constants
// or JSON encoding
final class UtmStore {
    static let firstTouchKey = "app.coproduct.utm.first"
    static let lastTouchKey = "app.coproduct.utm.last"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // Returns the persisted flattened attribute set without capturing anything.
    // Used in the initialize fold so a value captured in an earlier session is
    // present on the very first read of this one
    func utmAttributes() -> [String: AttributeValue] {
        Self.flatten(
            first: storedDictionary(forKey: Self.firstTouchKey),
            last: storedDictionary(forKey: Self.lastTouchKey)
        )
    }

    // Parses url for UTM parameters and merges them into both stores: last-touch
    // always takes the new value, first-touch only fills a key that is still
    // absent. Empty values are never written or returned. When the parse finds
    // nothing, nothing is persisted and the already-stored set is returned
    // unchanged. Assumes serialized (main-thread) deep-link delivery, unlike
    // SessionStore this has no lock around its read-modify-write
    func capture(url: String) -> [String: AttributeValue] {
        let parsed = parseUtmParameters(url: url)
        guard !parsed.isEmpty else {
            return utmAttributes()
        }

        var first = storedDictionary(forKey: Self.firstTouchKey)
        var last = storedDictionary(forKey: Self.lastTouchKey)

        for (key, value) in parsed where !value.isEmpty {
            last[key] = value
            if first[key] == nil {
                first[key] = value
            }
        }

        defaults.set(first, forKey: Self.firstTouchKey)
        defaults.set(last, forKey: Self.lastTouchKey)

        return Self.flatten(first: first, last: last)
    }

    private func storedDictionary(forKey key: String) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    // Bare keys carry first-touch, key_last carries last-touch. Filters out any
    // empty value defensively, so a blank entry can never surface as an attribute
    private static func flatten(first: [String: String], last: [String: String]) -> [String: AttributeValue] {
        var result: [String: AttributeValue] = [:]
        for (key, value) in first where !value.isEmpty {
            result[key] = .string(value)
        }
        for (key, value) in last where !value.isEmpty {
            result["\(key)_last"] = .string(value)
        }
        return result
    }
}
