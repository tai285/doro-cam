package com.dorocam.doro_camera

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger

/**
 * Android side of the Doro Cam camera plugin. It only does hardware work: product logic such as
 * scenarios, presets and intent resolution lives in Dart (ADR-0001).
 */
class DoroCameraPlugin(
    private val environment: PlatformEnvironment = SystemPlatformEnvironment,
) : FlutterPlugin, CameraHostApi {
    private var messenger: BinaryMessenger? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attach(binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detach()
    }

    internal fun attach(binaryMessenger: BinaryMessenger) {
        messenger = binaryMessenger
        CameraHostApi.setUp(binaryMessenger, this)
    }

    internal fun detach() {
        messenger?.let { CameraHostApi.setUp(it, null) }
        messenger = null
    }

    override fun ping(message: String): PingResultMessage =
        PingResultMessage(
            echo = message,
            platform = "android",
            osVersion = environment.osVersion,
            syntheticCameraCompiledIn = SyntheticCameraBuild.isCompiledIn,
        )
}
