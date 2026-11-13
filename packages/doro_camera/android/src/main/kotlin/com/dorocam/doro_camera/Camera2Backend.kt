package com.dorocam.doro_camera

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.MediaCodecList
import android.media.MediaFormat

/** Real cameras through Camera2. Capabilities are probed from `CameraCharacteristics`, never assumed (ADR-0002). */
class Camera2Backend(private val env: Camera2Environment) : CameraBackend {
    companion object {
        fun mediaSupport(context: Context): MediaSupport {
            val codecs = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter { it.isEncoder }
            fun hasEncoder(mime: String) = codecs.any { info -> info.supportedTypes.any { it.equals(mime, ignoreCase = true) } }
            return MediaSupport(
                videoEncoder = hasEncoder(MediaFormat.MIMETYPE_VIDEO_AVC),
                audioEncoder = hasEncoder(MediaFormat.MIMETYPE_AUDIO_AAC),
                microphone = context.packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE),
            )
        }

        fun create(context: Context, orientation: OrientationSource, thermal: ThermalSource): Camera2Backend =
            Camera2Backend(
                Camera2Environment(
                    context = context,
                    manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager,
                    media = mediaSupport(context),
                    orientation = orientation,
                    thermal = thermal,
                ),
            )
    }

    private val cache = HashMap<String, CharacteristicsData>()

    private fun characteristics(id: String): CameraCharacteristics = try {
        env.manager.getCameraCharacteristics(if ('#' in id) id.substringAfter('#') else id)
    } catch (e: CameraAccessException) {
        throw CameraException("camera_disconnected", "Camera $id cannot be read", e)
    } catch (e: IllegalArgumentException) {
        throw CameraException("unsupported_configuration", "Unknown camera $id", e)
    }

    private fun dataFor(id: String): CharacteristicsData = synchronized(cache) {
        cache.getOrPut(id) { CharacteristicsReader.read(id, characteristics(id)) }
    }

    override fun owns(cameraId: String): Boolean = env.manager.cameraIdList.contains(cameraId.substringBefore('#'))

    override fun listCameras(): List<CameraDescriptorMessage> {
        val ids = env.manager.cameraIdList.toList()
        val out = mutableListOf<CameraDescriptorMessage>()
        for (id in ids) {
            val data = dataFor(id)
            out += CapabilityProbe.descriptor(data)
            // Physical lenses of a logical camera that the platform does not list on their own.
            for (physical in data.physicalIds.filter { it !in ids }) {
                val composite = "$id#$physical"
                try {
                    val physData = dataFor(composite)
                    out += CapabilityProbe.descriptor(physData.copy(id = composite, physicalIds = emptyList()))
                } catch (_: CameraException) {
                    // The OEM hides this lens from third-party apps: report only what is usable.
                }
            }
        }
        return out
    }

    override fun capabilities(cameraId: String): CameraCapabilitiesMessage {
        val data = dataFor(cameraId)
        return CapabilityProbe.capabilities(data.copy(id = cameraId), env.media)
    }

    override suspend fun open(
        sessionId: Long,
        config: SessionConfigMessage,
        texture: PreviewTexture,
        events: SessionEvents,
        audioAllowed: Boolean,
    ): BackendSession {
        val id = config.cameraId
        val data = dataFor(id)
        val realtime = CharacteristicsReader.timestampSourceIsRealtime(characteristics(id))
        return Camera2Session.open(sessionId, env, OpenTarget.parse(id), data, realtime, config, texture, events, audioAllowed)
    }
}
