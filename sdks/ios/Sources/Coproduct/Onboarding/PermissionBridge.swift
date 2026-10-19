import AVFoundation
import CoreLocation
import Foundation
import Photos
import UserNotifications

/// Maps an authored flow's `requestPermission` action name to a real OS
/// permission prompt, returning a status dictionary rather than throwing for
/// an ordinary denial -- denial is an expected outcome, not an error.
public typealias PermissionRequestFn = @Sendable (String) async throws -> [String: String]

/// Namespace for the default `requestPermission` action-name mapping.
/// `requestPermissionOverrideForTesting`, when set, replaces the real OS
/// calls entirely -- the actual permission prompts cannot run in a unit
/// test host, which has no UI and no entitlements to grant against.
public enum PermissionBridge {
    public static var requestPermissionOverrideForTesting: PermissionRequestFn?

    public static func requestPermission(_ permission: String) async throws -> [String: String] {
        if let override = requestPermissionOverrideForTesting {
            return try await override(permission)
        }
        switch permission {
        case "camera":
            return ["status": await requestCaptureAccess(for: .video)]
        case "microphone":
            return ["status": await requestCaptureAccess(for: .audio)]
        case "location":
            return ["status": await requestLocationAccess()]
        case "photos":
            return ["status": photoStatus(await PHPhotoLibrary.requestAuthorization(for: .readWrite))]
        case "notifications":
            return ["status": try await requestNotificationAccess()]
        default:
            return ["status": "error", "message": "Unknown permission \"\(permission)\""]
        }
    }

    private static func requestCaptureAccess(for mediaType: AVMediaType) async -> String {
        await AVCaptureDevice.requestAccess(for: mediaType) ? "granted" : "denied"
    }

    private static func requestNotificationAccess() async throws -> String {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        return granted ? "granted" : "denied"
    }

    private static func photoStatus(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized, .limited: return "granted"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "denied"
        }
    }

    @MainActor
    private static func requestLocationAccess() async -> String {
        let manager = CLLocationManager()
        let current = manager.authorizationStatus
        if current != .notDetermined {
            return locationStatus(current)
        }
        let requester = LocationPermissionRequester(manager: manager)
        return locationStatus(await requester.requestAndAwaitDecision())
    }

    private static func locationStatus(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: return "granted"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "denied"
        }
    }
}

/// `CLLocationManager` reports its authorization decision through a delegate
/// callback, not a completion handler, so this bridges that to a single
/// `async` call.
@MainActor
private final class LocationPermissionRequester: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    init(manager: CLLocationManager) {
        self.manager = manager
        super.init()
    }

    func requestAndAwaitDecision() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        Task { @MainActor in
            continuation?.resume(returning: status)
            continuation = nil
        }
    }
}
