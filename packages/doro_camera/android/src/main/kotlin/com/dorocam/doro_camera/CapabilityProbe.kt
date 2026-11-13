package com.dorocam.doro_camera

import android.hardware.camera2.CameraMetadata
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Everything the probe needs from `CameraCharacteristics`, already extracted into plain values.
 * It is the "characteristics source" seam of docs/architecture/camera.md: JVM tests build these
 * fixtures by hand, [CharacteristicsReader] builds them from the real Camera2 object.
 */
data class CharacteristicsData(
    val id: String,
    val lensFacing: Int?,
    val sensorOrientation: Int,
    val hardwareLevel: Int?,
    val capabilities: Set<Int> = emptySet(),
    val sensitivityRange: Pair<Int, Int>? = null,
    val exposureTimeRangeNs: Pair<Long, Long>? = null,
    val aeCompensationRange: Pair<Int, Int>? = null,
    val aeCompensationStep: Double = 0.0,
    val aeLockAvailable: Boolean = false,
    val awbLockAvailable: Boolean = false,
    val apertures: List<Float> = emptyList(),
    val focalLengths: List<Float> = emptyList(),
    val minimumFocusDistanceDiopters: Float? = null,
    val focusCalibration: Int? = null,
    val afModes: Set<Int> = emptySet(),
    val awbModes: Set<Int> = emptySet(),
    val maxAfRegions: Int = 0,
    val maxAeRegions: Int = 0,
    val flashAvailable: Boolean = false,
    val sensorWidthMm: Float? = null,
    val sensorHeightMm: Float? = null,
    val maxDigitalZoom: Float = 1f,
    /** API 30+ `CONTROL_ZOOM_RATIO_RANGE`. Null on older devices (crop-region zoom is used). */
    val zoomRatioRange: Pair<Float, Float>? = null,
    val activeArrayWidth: Int = 0,
    val activeArrayHeight: Int = 0,
    val physicalIds: List<String> = emptyList(),
    val jpegSizes: List<SizeMessage> = emptyList(),
    val heifSizes: List<SizeMessage> = emptyList(),
    val rawSizes: List<SizeMessage> = emptyList(),
    /** Surface (preview/encoder) output sizes with their minimum frame duration in nanoseconds. */
    val surfaceSizes: List<SizeMessage> = emptyList(),
    val minFrameDurationNs: Map<SizeMessage, Long> = emptyMap(),
    val aeTargetFpsRanges: List<Pair<Int, Int>> = emptyList(),
    val opticalStabilizationModes: Set<Int> = emptySet(),
    val videoStabilizationModes: Set<Int> = emptySet(),
    val hdrScenes: Boolean = false,
)

/** Device-wide facts the characteristics cannot tell: are there encoders and a microphone? */
data class MediaSupport(
    val videoEncoder: Boolean,
    val audioEncoder: Boolean,
    val microphone: Boolean,
)

object CapabilityProbe {
    /** Kelvin range we are willing to expose when manual colour gains exist (docs/specs/camera.md). */
    const val KELVIN_MIN = 2000
    const val KELVIN_MAX = 10000
    const val LIVE_MAX_PRE_BUFFER_MS = 3000L

    private const val FULL_FRAME_DIAGONAL_MM = 43.2666

    fun hasCapability(data: CharacteristicsData, capability: Int): Boolean = capability in data.capabilities

    /** Manual ISO/shutter are exposed only with MANUAL_SENSOR *and* valid ranges (docs/specs/camera.md). */
    fun manualSensor(data: CharacteristicsData): Boolean =
        hasCapability(data, CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR)

    fun isoRange(data: CharacteristicsData): IntRangeMessage? {
        val range = data.sensitivityRange ?: return null
        if (!manualSensor(data) || range.first <= 0 || range.first >= range.second) return null
        return IntRangeMessage(range.first.toLong(), range.second.toLong())
    }

    fun exposureRange(data: CharacteristicsData): IntRangeMessage? {
        val range = data.exposureTimeRangeNs ?: return null
        if (!manualSensor(data) || range.first <= 0 || range.first >= range.second) return null
        return IntRangeMessage(range.first, range.second)
    }

    fun exposureBias(data: CharacteristicsData): ExposureBiasCapabilityMessage? {
        val range = data.aeCompensationRange ?: return null
        if (data.aeCompensationStep <= 0.0 || (range.first == 0 && range.second == 0)) return null
        return ExposureBiasCapabilityMessage(
            range = DoubleRangeMessage(range.first * data.aeCompensationStep, range.second * data.aeCompensationStep),
            step = data.aeCompensationStep,
        )
    }

    fun manualFocus(data: CharacteristicsData): ManualFocusCapabilityMessage? {
        val min = data.minimumFocusDistanceDiopters ?: return null
        if (min <= 0f) return null
        val calibration = when (data.focusCalibration) {
            CameraMetadata.LENS_INFO_FOCUS_DISTANCE_CALIBRATION_CALIBRATED -> FocusCalibrationMessage.CALIBRATED
            CameraMetadata.LENS_INFO_FOCUS_DISTANCE_CALIBRATION_APPROXIMATE -> FocusCalibrationMessage.APPROXIMATE
            else -> FocusCalibrationMessage.UNCALIBRATED
        }
        return ManualFocusCapabilityMessage(min.toDouble(), calibration)
    }

    fun focus(data: CharacteristicsData): FocusCapabilitiesMessage {
        val auto = CameraMetadata.CONTROL_AF_MODE_AUTO in data.afModes
        val continuous = CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_PICTURE in data.afModes
        return FocusCapabilitiesMessage(
            auto = auto,
            continuous = continuous,
            tapToFocus = (auto || continuous) && data.maxAfRegions > 0,
            manual = manualFocus(data),
        )
    }

    /** True when white balance can be driven by Kelvin: colour gains need MANUAL_POST_PROCESSING and AWB off. */
    fun kelvinSupported(data: CharacteristicsData): Boolean =
        hasCapability(data, CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_POST_PROCESSING) &&
            CameraMetadata.CONTROL_AWB_MODE_OFF in data.awbModes

    fun whiteBalance(data: CharacteristicsData): WhiteBalanceCapabilitiesMessage {
        val presets = buildList {
            if (CameraMetadata.CONTROL_AWB_MODE_AUTO in data.awbModes) add(WbPresetMessage.AUTO)
            if (CameraMetadata.CONTROL_AWB_MODE_DAYLIGHT in data.awbModes) add(WbPresetMessage.DAYLIGHT)
            if (CameraMetadata.CONTROL_AWB_MODE_CLOUDY_DAYLIGHT in data.awbModes) add(WbPresetMessage.CLOUDY)
            if (CameraMetadata.CONTROL_AWB_MODE_SHADE in data.awbModes) add(WbPresetMessage.SHADE)
            if (CameraMetadata.CONTROL_AWB_MODE_INCANDESCENT in data.awbModes) add(WbPresetMessage.TUNGSTEN)
            if (CameraMetadata.CONTROL_AWB_MODE_FLUORESCENT in data.awbModes) add(WbPresetMessage.FLUORESCENT)
        }
        return WhiteBalanceCapabilitiesMessage(
            presets = presets,
            kelvin = if (kelvinSupported(data)) IntRangeMessage(KELVIN_MIN.toLong(), KELVIN_MAX.toLong()) else null,
        )
    }

    fun zoom(data: CharacteristicsData): ZoomCapabilitiesMessage {
        val ratio = data.zoomRatioRange
        return if (ratio != null) {
            ZoomCapabilitiesMessage(ratio.first.toDouble(), ratio.second.toDouble(), listOf(1.0))
        } else {
            ZoomCapabilitiesMessage(1.0, max(1f, data.maxDigitalZoom).toDouble(), listOf(1.0))
        }
    }

    fun photoFormats(data: CharacteristicsData): List<PhotoFormatMessage> = buildList {
        if (data.heifSizes.isNotEmpty()) add(PhotoFormatMessage.HEIF)
        if (data.jpegSizes.isNotEmpty()) add(PhotoFormatMessage.JPEG)
        if (data.rawSizes.isNotEmpty() && hasCapability(data, CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_RAW)) {
            add(PhotoFormatMessage.DNG)
        }
    }

    fun stabilization(data: CharacteristicsData): StabilizationCapabilitiesMessage {
        val photo = buildList {
            add(StabilizationModeMessage.OFF)
            if (CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_ON in data.opticalStabilizationModes) {
                add(StabilizationModeMessage.OPTICAL)
            }
        }
        val video = buildList {
            add(StabilizationModeMessage.OFF)
            if (CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_ON in data.videoStabilizationModes) {
                add(StabilizationModeMessage.STANDARD)
            }
            if (CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_ON in data.opticalStabilizationModes) {
                add(StabilizationModeMessage.OPTICAL)
            }
        }
        return StabilizationCapabilitiesMessage(photo, video)
    }

    private val VIDEO_SIZES = listOf(
        SizeMessage(3840, 2160),
        SizeMessage(1920, 1080),
        SizeMessage(1280, 720),
        SizeMessage(640, 480),
    )
    private val VIDEO_FPS = listOf(24, 30, 60)

    /** Video sizes and the frame rates this device can really deliver for them (VID-002). */
    fun video(data: CharacteristicsData, media: MediaSupport): VideoCapabilitiesMessage {
        if (!media.videoEncoder) return VideoCapabilitiesMessage(emptyList(), audio = false)
        val options = VIDEO_SIZES.filter { it in data.surfaceSizes }.mapNotNull { size ->
            val minDuration = data.minFrameDurationNs[size] ?: return@mapNotNull null
            val fps = VIDEO_FPS.filter { rate ->
                val frameNs = 1_000_000_000L / rate
                frameNs >= minDuration && data.aeTargetFpsRanges.any { it.first <= rate && it.second >= rate }
            }
            if (fps.isEmpty()) null else VideoSizeOptionMessage(size, fps.map { it.toLong() })
        }
        return VideoCapabilitiesMessage(options, audio = media.audioEncoder && media.microphone)
    }

    /** The size LIVE and video use when nothing else is requested: the largest option up to 1080p. */
    fun defaultMotionSize(data: CharacteristicsData): SizeMessage? =
        listOf(SizeMessage(1920, 1080), SizeMessage(1280, 720), SizeMessage(640, 480)).firstOrNull { it in data.surfaceSizes }

    fun live(data: CharacteristicsData, media: MediaSupport): LiveCapabilitiesMessage {
        val supported = media.videoEncoder && defaultMotionSize(data) != null
        return LiveCapabilitiesMessage(
            supported = supported,
            maxPreBufferMs = if (supported) LIVE_MAX_PRE_BUFFER_MS else 0,
            audio = supported && media.audioEncoder && media.microphone,
        )
    }

    fun hardwareLevelName(level: Int?): String = when (level) {
        CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY -> "LEGACY"
        CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_LIMITED -> "LIMITED"
        CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_FULL -> "FULL"
        CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_3 -> "LEVEL_3"
        CameraMetadata.INFO_SUPPORTED_HARDWARE_LEVEL_EXTERNAL -> "EXTERNAL"
        else -> "UNKNOWN"
    }

    fun capabilities(data: CharacteristicsData, media: MediaSupport): CameraCapabilitiesMessage =
        CameraCapabilitiesMessage(
            cameraId = data.id,
            iso = isoRange(data),
            exposureTimeNs = exposureRange(data),
            exposureBias = exposureBias(data),
            apertures = data.apertures.map { it.toDouble() },
            focus = focus(data),
            whiteBalance = whiteBalance(data),
            zoom = zoom(data),
            flash = if (data.flashAvailable) listOf(FlashModeMessage.OFF, FlashModeMessage.AUTO, FlashModeMessage.ON) else emptyList(),
            torch = data.flashAvailable,
            photoFormats = photoFormats(data),
            photoSizes = (data.jpegSizes + data.heifSizes).distinct().sortedByDescending { it.width * it.height },
            stabilization = stabilization(data),
            video = video(data, media),
            hdr = data.hdrScenes,
            live = live(data, media),
            hardwareLevel = hardwareLevelName(data.hardwareLevel),
        )

    // ---- descriptor -----------------------------------------------------------------------------

    /** 35 mm equivalent focal length from the physical focal length and sensor size, or null if unknown. */
    fun focalLength35mmEq(focalMm: Float?, sensorWidthMm: Float?, sensorHeightMm: Float?): Double? {
        if (focalMm == null || focalMm <= 0f || sensorWidthMm == null || sensorHeightMm == null) return null
        val diagonal = hypot(sensorWidthMm.toDouble(), sensorHeightMm.toDouble())
        if (diagonal <= 0.0) return null
        return (focalMm * FULL_FRAME_DIAGONAL_MM / diagonal * 10.0).roundToInt() / 10.0
    }

    /** Classifies a back-facing lens by its 35 mm equivalent focal length. */
    fun lensKind(facing: Int?, eq: Double?): LensKindMessage = when {
        facing == CameraMetadata.LENS_FACING_FRONT -> LensKindMessage.FRONT
        eq == null -> LensKindMessage.OTHER
        eq < 20.0 -> LensKindMessage.ULTRA_WIDE
        eq <= 40.0 -> LensKindMessage.WIDE
        eq >= 60.0 -> LensKindMessage.TELE
        else -> LensKindMessage.OTHER
    }

    fun facing(lensFacing: Int?): CameraFacingMessage = when (lensFacing) {
        CameraMetadata.LENS_FACING_FRONT -> CameraFacingMessage.FRONT
        CameraMetadata.LENS_FACING_EXTERNAL -> CameraFacingMessage.EXTERNAL
        else -> CameraFacingMessage.BACK
    }

    fun descriptor(data: CharacteristicsData, label: String? = null): CameraDescriptorMessage {
        val focal = data.focalLengths.minOrNull()
        val eq = focalLength35mmEq(focal, data.sensorWidthMm, data.sensorHeightMm)
        val kind = lensKind(data.lensFacing, eq)
        val facing = facing(data.lensFacing)
        val base = when (facing) {
            CameraFacingMessage.FRONT -> "Front camera"
            CameraFacingMessage.EXTERNAL -> "External camera"
            CameraFacingMessage.BACK -> "Back camera"
        }
        val suffix = when (kind) {
            LensKindMessage.ULTRA_WIDE -> " (ultra-wide)"
            LensKindMessage.TELE -> " (telephoto)"
            else -> ""
        }
        return CameraDescriptorMessage(
            id = data.id,
            facing = facing,
            lensKind = kind,
            isLogical = hasCapability(data, CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA),
            physicalIds = data.physicalIds,
            sensorOrientation = data.sensorOrientation.toLong(),
            source = CameraSourceMessage.HARDWARE,
            label = label ?: (base + suffix),
            focalLengthMm = focal?.toDouble(),
            focalLength35mmEq = eq,
        )
    }

}
