import Foundation
#if canImport(UIKit)
import UIKit
#endif

// Collects the static SDK-owned device attributes once per initialize. Pure
// reads with no side effects: session persistence lives in SessionStore and
// the live network fact lives in NetworkMonitor. Values are raw platform
// facts; the core normalizes them (version padding, locale hyphenation) so
// every platform wrapper stays parity-identical
enum DeviceContext {
    static func staticAttributes() -> [String: AttributeValue] {
        var attrs: [String: AttributeValue] = [:]
        attrs["platform"] = .string("ios")

        // Formatted from the struct components so the value is always plain
        // major.minor.patch, never a descriptive string
        let os = ProcessInfo.processInfo.operatingSystemVersion
        attrs["os_version"] = .string("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")

        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            attrs["app_version"] = .string(version)
        }
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            attrs["app_build"] = .string(build)
        }
        if let language = Locale.preferredLanguages.first {
            // Passed through raw: locale hyphenation is the core's
            // normalization contract, not a wrapper responsibility
            attrs["locale"] = .string(language)
        }
        attrs["timezone"] = .string(TimeZone.current.identifier)

        #if canImport(UIKit)
        if let deviceType = deviceType(for: UIDevice.current.userInterfaceIdiom) {
            attrs["device_type"] = .string(deviceType)
        }
        #endif
        return attrs
    }

    #if canImport(UIKit)
    // phone and tablet only. An unmapped idiom omits the attribute entirely so
    // is_set and is_not_set stay meaningful. The vocabulary
    // widens only when the platform recognizes a new device-type value,
    // never by inventing values here
    static func deviceType(for idiom: UIUserInterfaceIdiom) -> String? {
        switch idiom {
        case .phone: return "phone"
        case .pad: return "tablet"
        default: return nil
        }
    }
    #endif
}
