import Foundation

// Persists the most recent GPS fix in UserDefaults, mirroring SessionStore. The
// stored fix seeds `device_location` at initialize so a geo-fence can evaluate
// from the last known position before a fresh fix arrives. The value is the
// two-element [lat, lng] array the core reads for a geo-fence.
final class LocationStore {
    static let latKey = "app.coproduct.deviceLocationLat"
    static let lngKey = "app.coproduct.deviceLocationLng"
    static let hasFixKey = "app.coproduct.deviceLocationHasFix"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func write(lat: Double, lng: Double) {
        defaults.set(lat, forKey: Self.latKey)
        defaults.set(lng, forKey: Self.lngKey)
        defaults.set(true, forKey: Self.hasFixKey)
    }

    // The auto-populated attribute a stored fix contributes, or an empty map when
    // none is stored, so an unset location leaves geo-fence rules to fall through
    func locationAttributes() -> [String: AttributeValue] {
        guard defaults.bool(forKey: Self.hasFixKey) else { return [:] }
        let lat = defaults.double(forKey: Self.latKey)
        let lng = defaults.double(forKey: Self.lngKey)
        return ["device_location": .numberList([lat, lng])]
    }
}
