import DoroCameraCore
import Flutter

/// iOS side of the Doro Cam camera plugin. It only does hardware work: product logic such as
/// scenarios, presets and intent resolution lives in Dart (ADR-0001).
public class DoroCameraPlugin: NSObject, FlutterPlugin, CameraHostApi {
    private let pingResponder = PingResponder()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = DoroCameraPlugin()
        CameraHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    }

    func ping(message: String) throws -> PingResultMessage {
        let response = pingResponder.respond(to: message)
        return PingResultMessage(
            echo: response.echo,
            platform: response.platform,
            osVersion: response.osVersion,
            syntheticCameraCompiledIn: response.syntheticCameraCompiledIn
        )
    }
}
