package com.dorocam.doro_camera

import android.hardware.camera2.CameraMetadata
import kotlin.math.abs

/** The fields of a `TotalCaptureResult` we read, as plain values (the results seam). */
data class ResultData(
    val sensitivity: Int? = null,
    val exposureTimeNs: Long? = null,
    val aeCompensationIndex: Int? = null,
    val aperture: Float? = null,
    val focalLength: Float? = null,
    val focusDistance: Float? = null,
    val afMode: Int? = null,
    val afState: Int? = null,
    val awbMode: Int? = null,
    val colorGains: List<Float>? = null,
    val zoomRatio: Float? = null,
    val cropWidth: Int? = null,
    val flashState: Int? = null,
    val flashMode: Int? = null,
    val aeLock: Boolean? = null,
    val awbLock: Boolean? = null,
    val aeMode: Int? = null,
    val opticalStabilization: Int? = null,
    val videoStabilization: Int? = null,
)

/**
 * Turns a capture result into [AppliedSettingsMessage]: what the device REPORTED it used (CAM-050),
 * plus the list of requested manual fields it did not honour, so Dart can downgrade a capability
 * after a persistent mismatch (docs/specs/camera.md).
 */
object AppliedExtractor {
    /** Hardware rounds exposure to its own steps; 10% is well beyond that and still catches an ignored request. */
    private const val EXPOSURE_TOLERANCE = 0.10
    private const val ISO_TOLERANCE = 0.05
    private const val ZOOM_TOLERANCE = 0.02
    private const val FOCUS_TOLERANCE_DIOPTERS = 0.15
    private const val GAIN_TOLERANCE = 0.03

    fun zoomRatio(result: ResultData, data: CharacteristicsData): Double {
        result.zoomRatio?.let { return it.toDouble() }
        val crop = result.cropWidth
        return if (crop != null && crop > 0 && data.activeArrayWidth > 0) data.activeArrayWidth.toDouble() / crop else 1.0
    }

    fun focusMode(afMode: Int?): FocusModeMessage? = when (afMode) {
        CameraMetadata.CONTROL_AF_MODE_OFF -> FocusModeMessage.MANUAL
        CameraMetadata.CONTROL_AF_MODE_AUTO, CameraMetadata.CONTROL_AF_MODE_MACRO -> FocusModeMessage.AUTO
        CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_PICTURE,
        CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_VIDEO,
        -> FocusModeMessage.CONTINUOUS
        else -> null
    }

    fun whiteBalanceMode(awbMode: Int?): String? = when (awbMode) {
        CameraMetadata.CONTROL_AWB_MODE_OFF -> "manual"
        CameraMetadata.CONTROL_AWB_MODE_AUTO -> "auto"
        CameraMetadata.CONTROL_AWB_MODE_DAYLIGHT -> "daylight"
        CameraMetadata.CONTROL_AWB_MODE_CLOUDY_DAYLIGHT -> "cloudy"
        CameraMetadata.CONTROL_AWB_MODE_SHADE -> "shade"
        CameraMetadata.CONTROL_AWB_MODE_INCANDESCENT -> "tungsten"
        CameraMetadata.CONTROL_AWB_MODE_FLUORESCENT -> "fluorescent"
        null -> null
        else -> "other"
    }

    fun stabilization(result: ResultData): StabilizationModeMessage? = when {
        result.opticalStabilization == CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_ON -> StabilizationModeMessage.OPTICAL
        result.videoStabilization == CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_ON -> StabilizationModeMessage.STANDARD
        result.opticalStabilization != null || result.videoStabilization != null -> StabilizationModeMessage.OFF
        else -> null
    }

    fun flash(result: ResultData): FlashModeMessage? = when (result.aeMode) {
        CameraMetadata.CONTROL_AE_MODE_ON_AUTO_FLASH -> FlashModeMessage.AUTO
        CameraMetadata.CONTROL_AE_MODE_ON_ALWAYS_FLASH -> FlashModeMessage.ON
        null -> null
        else -> FlashModeMessage.OFF
    }

    /** Diopters of focus distance reported by the lens; null when the device reports nothing. */
    private fun relative(requested: Double, applied: Double): Double =
        if (requested == 0.0) abs(applied) else abs(applied - requested) / abs(requested)

    fun mismatches(requested: RequestParams?, result: ResultData, data: CharacteristicsData): List<String> {
        if (requested == null) return emptyList()
        val out = mutableListOf<String>()

        if (requested.manualExposure) {
            if (requested.requestedIso != null) {
                val applied = result.sensitivity
                val wanted = requested.sensitivity ?: requested.requestedIso
                if (applied == null || relative(wanted.toDouble(), applied.toDouble()) > ISO_TOLERANCE) out += "iso"
            }
            if (requested.requestedExposureNs != null) {
                val applied = result.exposureTimeNs
                val wanted = requested.exposureTimeNs ?: requested.requestedExposureNs
                if (applied == null || relative(wanted.toDouble(), applied.toDouble()) > EXPOSURE_TOLERANCE) out += "exposureTime"
            }
        } else if (requested.aeCompensationIndex != 0) {
            val applied = result.aeCompensationIndex
            if (applied == null || applied != requested.aeCompensationIndex) out += "exposureBias"
        }

        if (requested.aeLock && result.aeLock != true) out += "aeLock"
        if (requested.afLockRequested && requested.requestedFocusMode != FocusModeMessage.MANUAL &&
            result.afState != CameraMetadata.CONTROL_AF_STATE_FOCUSED_LOCKED &&
            result.afState != CameraMetadata.CONTROL_AF_STATE_NOT_FOCUSED_LOCKED
        ) {
            out += "afLock"
        }

        if (requested.requestedFocusMode == FocusModeMessage.MANUAL && requested.focusDistance != null) {
            val applied = result.focusDistance
            if (result.afMode != CameraMetadata.CONTROL_AF_MODE_OFF ||
                applied == null ||
                abs(applied - requested.focusDistance) > FOCUS_TOLERANCE_DIOPTERS
            ) {
                out += "focusDistance"
            }
        }

        val gains = requested.colorGains
        if (gains != null) {
            val applied = result.colorGains
            if (result.awbMode != CameraMetadata.CONTROL_AWB_MODE_OFF ||
                applied == null ||
                applied.size < 4 ||
                applied.indices.any { relative(gains[it].toDouble(), applied[it].toDouble()) > GAIN_TOLERANCE }
            ) {
                out += "kelvin"
            }
        } else if (requested.requestedWbPreset != null && requested.requestedWbPreset != WbPresetMessage.AUTO) {
            if (result.awbMode != requested.awbMode) out += "whiteBalance"
        }

        val zoomApplied = zoomRatio(result, data)
        if (abs(zoomApplied - requested.zoomRatio) > ZOOM_TOLERANCE * requested.zoomRatio) out += "zoom"

        return out
    }

    fun extract(requested: RequestParams?, result: ResultData, data: CharacteristicsData): AppliedSettingsMessage {
        val gains = result.colorGains
        val manualGains = result.awbMode == CameraMetadata.CONTROL_AWB_MODE_OFF
        return AppliedSettingsMessage(
            iso = result.sensitivity?.toLong(),
            exposureTimeNs = result.exposureTimeNs,
            exposureBiasEv = result.aeCompensationIndex?.let { it * data.aeCompensationStep },
            aperture = result.aperture?.toDouble(),
            focalLengthMm = result.focalLength?.toDouble(),
            focusDistanceDiopters = result.focusDistance?.toDouble(),
            focusMode = focusMode(result.afMode),
            whiteBalanceMode = whiteBalanceMode(result.awbMode),
            whiteBalanceGains = gains?.map { it.toDouble() },
            estimatedKelvin = if (manualGains && gains != null) KelvinGains.estimateKelvin(gains)?.toLong() else null,
            aeLocked = result.aeLock == true,
            afLocked = result.afState == CameraMetadata.CONTROL_AF_STATE_FOCUSED_LOCKED ||
                result.afState == CameraMetadata.CONTROL_AF_STATE_NOT_FOCUSED_LOCKED ||
                (result.afMode == CameraMetadata.CONTROL_AF_MODE_OFF && requested?.requestedFocusMode == FocusModeMessage.MANUAL),
            zoomRatio = zoomRatio(result, data),
            flashFired = result.flashState?.let { it == CameraMetadata.FLASH_STATE_FIRED },
            flash = flash(result),
            stabilization = stabilization(result),
            mismatches = mismatches(requested, result, data).map { it },
        )
    }
}
