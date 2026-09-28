import Flutter
import UIKit

/// Answers host-context questions the Dart side cannot answer correctly on its
/// own, and streams network_type. Deliberately small: it performs no upsert,
/// holds no SDK state beyond the session transaction's process-wide guard and
/// failure latch and this engine's one network observation, and knows nothing
/// about the SDK key or the evaluation core. The native library the core runs
/// in is still loaded directly rather than through these channels
public class CoproductHostContextPlugin: NSObject, FlutterPlugin {
    private static let channelName = "app.coproduct.flutter/host_context"
    private static let networkChannelName = "app.coproduct.flutter/network_type"

    private let defaultsFilePath: String?
    private let sessionProcess: SessionProcessState
    private let networkObserver: NetworkTypeObserver

    /// Tests pass their own defaults file, process state, and network
    /// observer, since they cannot lock a simulator, give the test host a fresh
    /// process, or change its network. Registration goes through the plain
    /// init, which supplies the production values
    init(
        defaultsFilePath: String?,
        sessionProcess: SessionProcessState,
        networkObserver: NetworkTypeObserver = NetworkTypeObserver()
    ) {
        self.defaultsFilePath = defaultsFilePath
        self.sessionProcess = sessionProcess
        self.networkObserver = networkObserver
        super.init()
    }

    /// Kept so the class still answers a plain init, which Objective-C callers
    /// reach through NSObject and would otherwise crash on
    public override convenience init() {
        self.init(defaultsFilePath: DefaultsFile.standardPath, sessionProcess: .shared)
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        install(
            CoproductHostContextPlugin(),
            messenger: registrar.messenger(),
            addMethodCallDelegate: { registrar.addMethodCallDelegate($0, channel: $1) },
            publish: { registrar.publish($0) }
        )
    }

    /// Split from register(with:) so a test can drive it without a registrar
    static func install(
        _ instance: CoproductHostContextPlugin,
        messenger: FlutterBinaryMessenger,
        addMethodCallDelegate: (CoproductHostContextPlugin, FlutterMethodChannel) -> Void,
        publish: (NSObject) -> Void
    ) {
        addMethodCallDelegate(instance, FlutterMethodChannel(name: channelName, binaryMessenger: messenger))
        // No task queue, so listen and cancel run on the main thread with the
        // monitor's updates
        FlutterEventChannel(name: networkChannelName, binaryMessenger: messenger)
            .setStreamHandler(instance.networkObserver)
        // detachFromEngine(for:) reaches only a published instance
        publish(instance)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        detach()
    }

    /// Split from detachFromEngine(for:) so a test can reach it without a
    /// registrar. A no-op when Dart already cancelled
    func detach() {
        networkObserver.cancel()
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
