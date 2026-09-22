import Flutter
import UIKit

/// Answers host-context questions the Dart side cannot answer correctly on its
/// own. Deliberately small: it holds no SDK state, performs no upsert, and knows
/// nothing about the SDK key or the evaluation core. The native library the core
/// runs in is still loaded directly rather than through this channel
public class CoproductHostContextPlugin: NSObject, FlutterPlugin {
    private static let channelName = "app.coproduct.flutter/host_context"

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
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
