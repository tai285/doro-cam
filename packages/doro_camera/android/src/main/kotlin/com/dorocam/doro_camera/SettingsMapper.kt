package com.dorocam.doro_camera

import android.hardware.camera2.CameraMetadata
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

/** The metered exposure the device picked on its own, used when only ISO or only shutter is manual. */
data class AutoSnapshot(val iso: Int?, val exposureTimeNs: Long?)

/**
 * Camera2 request values derived from [ResolvedCaptureSettingsMessage]. It is a plain value so the
 * mapping (the only logic here) is unit tested without hardware; the thin Android glue copies these
 * values onto a `CaptureRequest.Builder`.
 */
data class RequestParams(
    val aeMode: Int,
    val sensitivity: Int?,
    val exposureTimeNs: Long?,
    val aeCompensationIndex: Int,
    val aeLock: Boolean,
    val afMode: Int,
    val focusDistance: Float?,
    val awbMode: Int,
    val awbLock: Boolean,
    /** Red, green-even, green-odd, blue. Non-null only for Kelvin white balance. */
    val colorGains: List<Float>?,
    val zoomRatio: Float,
    /** `CaptureRequest.FLASH_MODE` for the preview (torch or off). */
    val flashMode: Int,
    /** AE mode to use for the still capture (adds auto/always flash on top of normal AE). */
    val stillAeMode: Int,
    val opticalStabilization: Int?,
    val videoStabilization: Int?,
    val manualExposure: Boolean,
    val requestedIso: Int?,
    val requestedExposureNs: Long?,
    val requestedFocusDiopters: Float?,
    val requestedKelvin: Int?,
    val requestedWbPreset: WbPresetMessage?,
    val requestedFocusMode: FocusModeMessage,
    val afLockRequested: Boolean,
)

object SettingsMapper {
    const val DEFAULT_ISO = 100
    const val DEFAULT_EXPOSURE_NS = 16_666_666L

    fun map(
        settings: ResolvedCaptureSettingsMessage,
        data: CharacteristicsData,
        auto: AutoSnapshot? = null,
        forVideo: Boolean = false,
    ): RequestParams {
        val isoRange = CapabilityProbe.isoRange(data)
        val exposureRange = CapabilityProbe.exposureRange(data)
        val wantsManual = (settings.iso != null || settings.exposureTimeNs != null) && isoRange != null && exposureRange != null
        val sensitivity: Int?
        val exposure: Long?
        if (wantsManual) {
            // Camera2 needs both values when AE is off. The one the user did not choose keeps the metered value (docs/specs/camera.md rule 3).
            val iso = settings.iso?.toInt() ?: auto?.iso ?: DEFAULT_ISO
            val ns = settings.exposureTimeNs ?: auto?.exposureTimeNs ?: DEFAULT_EXPOSURE_NS
            sensitivity = iso.coerceIn(isoRange!!.min.toInt(), isoRange.max.toInt())
            exposure = ns.coerceIn(exposureRange!!.min, exposureRange.max)
        } else {
            sensitivity = null
            exposure = null
        }

        val flash = settings.flash
        val flashSupported = data.flashAvailable
        val aeMode = if (wantsManual) CameraMetadata.CONTROL_AE_MODE_OFF else CameraMetadata.CONTROL_AE_MODE_ON
        val stillAeMode = when {
            wantsManual -> CameraMetadata.CONTROL_AE_MODE_OFF
            flashSupported && flash == FlashModeMessage.AUTO -> CameraMetadata.CONTROL_AE_MODE_ON_AUTO_FLASH
            flashSupported && flash == FlashModeMessage.ON -> CameraMetadata.CONTROL_AE_MODE_ON_ALWAYS_FLASH
            else -> CameraMetadata.CONTROL_AE_MODE_ON
        }

        val bias = CapabilityProbe.exposureBias(data)
        val biasIndex = if (!wantsManual && bias != null && settings.exposureBiasEv != null) {
            (settings.exposureBiasEv!! / bias.step).roundToInt()
                .coerceIn((bias.range.min / bias.step).roundToInt(), (bias.range.max / bias.step).roundToInt())
        } else {
            0
        }

        val focusMode = settings.focusMode
        val manualFocus = CapabilityProbe.manualFocus(data)
        val afMode: Int
        val focusDistance: Float?
        when {
            focusMode == FocusModeMessage.MANUAL && manualFocus != null -> {
                afMode = CameraMetadata.CONTROL_AF_MODE_OFF
                focusDistance = (settings.focusDistanceDiopters ?: 0.0).toFloat()
                    .coerceIn(0f, manualFocus.minFocusDistanceDiopters.toFloat())
            }
            focusMode == FocusModeMessage.AUTO && CameraMetadata.CONTROL_AF_MODE_AUTO in data.afModes -> {
                afMode = CameraMetadata.CONTROL_AF_MODE_AUTO
                focusDistance = null
            }
            else -> {
                val continuous = if (forVideo) CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_VIDEO else CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_PICTURE
                afMode = when {
                    continuous in data.afModes -> continuous
                    CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_PICTURE in data.afModes -> CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_PICTURE
                    CameraMetadata.CONTROL_AF_MODE_AUTO in data.afModes -> CameraMetadata.CONTROL_AF_MODE_AUTO
                    else -> CameraMetadata.CONTROL_AF_MODE_OFF
                }
                focusDistance = null
            }
        }

        var awbMode = CameraMetadata.CONTROL_AWB_MODE_AUTO
        var gains: List<Float>? = null
        val kelvin = settings.kelvin
        if (kelvin != null && CapabilityProbe.kelvinSupported(data)) {
            awbMode = CameraMetadata.CONTROL_AWB_MODE_OFF
            gains = KelvinGains.gainsFor(kelvin.toInt().coerceIn(CapabilityProbe.KELVIN_MIN, CapabilityProbe.KELVIN_MAX))
        } else if (settings.whiteBalancePreset != null) {
            val mode = awbModeFor(settings.whiteBalancePreset!!)
            if (mode in data.awbModes) awbMode = mode
        }

        val zoomMax = CapabilityProbe.zoom(data)
        val zoom = settings.zoomRatio.toFloat().coerceIn(zoomMax.min.toFloat(), zoomMax.max.toFloat())

        val torch = settings.torch && flashSupported
        val stabilization = settings.stabilization
        val optical = when {
            stabilization == null -> null
            stabilization == StabilizationModeMessage.OPTICAL && CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_ON in data.opticalStabilizationModes ->
                CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_ON
            CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_OFF in data.opticalStabilizationModes -> CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_OFF
            else -> null
        }
        val video = when {
            stabilization == null -> null
            stabilization == StabilizationModeMessage.STANDARD && CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_ON in data.videoStabilizationModes ->
                CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_ON
            CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_OFF in data.videoStabilizationModes -> CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_OFF
            else -> null
        }

        return RequestParams(
            aeMode = aeMode,
            sensitivity = sensitivity,
            exposureTimeNs = exposure,
            aeCompensationIndex = biasIndex,
            aeLock = settings.aeLock && !wantsManual && data.aeLockAvailable,
            afMode = afMode,
            focusDistance = focusDistance,
            awbMode = awbMode,
            awbLock = false,
            colorGains = gains,
            zoomRatio = zoom,
            flashMode = if (torch) CameraMetadata.FLASH_MODE_TORCH else CameraMetadata.FLASH_MODE_OFF,
            stillAeMode = stillAeMode,
            opticalStabilization = optical,
            videoStabilization = video,
            manualExposure = wantsManual,
            requestedIso = settings.iso?.toInt(),
            requestedExposureNs = settings.exposureTimeNs,
            requestedFocusDiopters = if (focusMode == FocusModeMessage.MANUAL) settings.focusDistanceDiopters?.toFloat() else null,
            requestedKelvin = settings.kelvin?.toInt(),
            requestedWbPreset = settings.whiteBalancePreset,
            requestedFocusMode = focusMode,
            afLockRequested = settings.afLock,
        )
    }

    fun awbModeFor(preset: WbPresetMessage): Int = when (preset) {
        WbPresetMessage.AUTO -> CameraMetadata.CONTROL_AWB_MODE_AUTO
        WbPresetMessage.DAYLIGHT -> CameraMetadata.CONTROL_AWB_MODE_DAYLIGHT
        WbPresetMessage.CLOUDY -> CameraMetadata.CONTROL_AWB_MODE_CLOUDY_DAYLIGHT
        WbPresetMessage.SHADE -> CameraMetadata.CONTROL_AWB_MODE_SHADE
        WbPresetMessage.TUNGSTEN -> CameraMetadata.CONTROL_AWB_MODE_INCANDESCENT
        WbPresetMessage.FLUORESCENT -> CameraMetadata.CONTROL_AWB_MODE_FLUORESCENT
    }
}

/**
 * Kelvin to colour gains. The conversion is the widely used black-body RGB approximation: it gives the
 * colour of light at a temperature, and the gains are what cancels that colour (green stays 1.0).
 * The result is an *estimate*, never claimed as hardware calibration (docs/specs/camera.md).
 */
object KelvinGains {
    /** RGB (0..255) of black-body light at [kelvin]. */
    fun lightRgb(kelvin: Int): Triple<Double, Double, Double> {
        val t = kelvin / 100.0
        val r = if (t <= 66) 255.0 else 329.698727446 * (t - 60).pow(-0.1332047592)
        val g = if (t <= 66) 99.4708025861 * ln(t) - 161.1195681661 else 288.1221695283 * (t - 60).pow(-0.0755148492)
        val b = when {
            t >= 66 -> 255.0
            t <= 19 -> 0.0
            else -> 138.5177312231 * ln(t - 10) - 305.0447927307
        }
        fun clamp(v: Double) = min(255.0, max(1.0, v))
        return Triple(clamp(r), clamp(g), clamp(b))
    }

    /** Red, green-even, green-odd, blue gains (all >= 1.0, the smallest being exactly 1.0). */
    fun gainsFor(kelvin: Int): List<Float> {
        val (r, g, b) = lightRgb(kelvin)
        var gr = g / r
        var gb = g / b
        val floor = min(1.0, min(gr, gb))
        gr /= floor
        gb /= floor
        val gg = 1.0 / floor
        return listOf(gr.toFloat(), gg.toFloat(), gg.toFloat(), gb.toFloat())
    }

    /** Inverse of [gainsFor], from the red/blue gain ratio. An estimate within a few hundred Kelvin. */
    fun estimateKelvin(gains: List<Float>): Int? {
        if (gains.size < 4 || gains[0] <= 0f || gains[3] <= 0f) return null
        val observed = ln((gains[0] / gains[3]).toDouble())
        var best = CapabilityProbe.KELVIN_MIN
        var bestError = Double.MAX_VALUE
        var k = CapabilityProbe.KELVIN_MIN
        while (k <= CapabilityProbe.KELVIN_MAX) {
            val g = gainsFor(k)
            val error = abs(ln((g[0] / g[3]).toDouble()) - observed)
            if (error < bestError) {
                bestError = error
                best = k
            }
            k += 50
        }
        return best
    }
}
