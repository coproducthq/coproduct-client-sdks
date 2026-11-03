import UIKit

/// Reads the OS version and the app's version and build number for the
/// os_version, app_version, and app_build attributes. Each value is the
/// platform's own string, unnormalized, and an absent one is NSNull rather than
/// empty. The app fields describe the main bundle, which in an app that embeds
/// Flutter is the host app and in an app extension is the extension
enum HostInfo {
    /// The production answer. UIDevice rather than ProcessInfo, because the two
    /// report different versions for an iPhone or iPad app running on a Mac or
    /// on Apple Vision Pro. The bundle lookup is object(forInfoDictionaryKey:),
    /// which returns the localized InfoPlist.strings value where one exists
    static func current() -> [String: Any] {
        read(
            systemVersion: UIDevice.current.systemVersion,
            infoValue: { Bundle.main.object(forInfoDictionaryKey: $0) }
        )
    }

    /// Split from current() so a test can supply the bundle values. A missing,
    /// empty, or non-string value is absent, and the build never falls back to
    /// the version
    static func read(systemVersion: String, infoValue: (String) -> Any?) -> [String: Any] {
        func string(_ key: String) -> Any {
            guard let value = infoValue(key) as? String, !value.isEmpty else { return NSNull() }
            return value
        }
        return [
            "os_version": systemVersion,
            "app_version": string("CFBundleShortVersionString"),
            "app_build": string("CFBundleVersion"),
        ]
    }
}
