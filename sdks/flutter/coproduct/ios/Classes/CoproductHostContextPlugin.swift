import Flutter
import UIKit

/// Answers host-context questions the Dart side cannot answer correctly on its
/// own. Deliberately small: it performs no upsert, holds no SDK state beyond the
/// session transaction's process-wide guard and failure latch, and knows nothing
/// about the SDK key or the evaluation core. The native library the core
/// runs in is still loaded directly rather than through this channel
public class CoproductHostContextPlugin: NSObject, FlutterPlugin {
    private static let channelName = "app.coproduct.flutter/host_context"

    private let defaultsFilePath: String?
    private let sessionProcess: SessionProcessState

    /// Tests pass their own defaults file and process state, since they cannot
    /// lock a simulator or give the test host a fresh process. Registration
    /// goes through the plain init, which supplies the production values
    init(defaultsFilePath: String?, sessionProcess: SessionProcessState) {
        self.defaultsFilePath = defaultsFilePath
        self.sessionProcess = sessionProcess
        super.init()
    }

    /// Kept so the class still answers a plain init, which Objective-C callers
    /// reach through NSObject and would otherwise crash on
    public override convenience init() {
        self.init(defaultsFilePath: DefaultsFile.standardPath, sessionProcess: .shared)
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(CoproductHostContextPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "readDeviceType":
            result(DeviceClassifier.deviceType(for: UIDevice.current.userInterfaceIdiom))
        case "beginSession":
            // Off the main thread, because the transaction holds a process-wide
            // lock around a UserDefaults write and a second engine may be waiting
            // on it. readDeviceType stays on main because it reads UIKit
            let filePath = defaultsFilePath
            let process = sessionProcess
            DispatchQueue.global(qos: .userInitiated).async {
                let pair = SessionStore(
                    storage: UserDefaultsSessionStorage(defaults: .standard, filePath: filePath),
                    process: process
                ).begin()
                DispatchQueue.main.async { result(pair?.channelValue) }
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
