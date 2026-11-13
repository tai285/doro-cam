package com.dorocam.doro_camera

import android.hardware.camera2.CameraMetadata as M

/** Hand-built characteristics (the "characteristics source" seam). No device model is ever hard-coded in production code. */
object Fixtures {
    val ALL_AF = setOf(M.CONTROL_AF_MODE_OFF, M.CONTROL_AF_MODE_AUTO, M.CONTROL_AF_MODE_CONTINUOUS_PICTURE, M.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
    val ALL_AWB = setOf(
        M.CONTROL_AWB_MODE_OFF, M.CONTROL_AWB_MODE_AUTO, M.CONTROL_AWB_MODE_DAYLIGHT, M.CONTROL_AWB_MODE_CLOUDY_DAYLIGHT,
        M.CONTROL_AWB_MODE_SHADE, M.CONTROL_AWB_MODE_INCANDESCENT, M.CONTROL_AWB_MODE_FLUORESCENT,
    )
    val SURFACE_SIZES = listOf(SizeMessage(3840, 2160), SizeMessage(1920, 1080), SizeMessage(1280, 720), SizeMessage(640, 480), SizeMessage(4000, 3000))

    /** A FULL-level device with manual sensor and post-processing, like the emulator's HAL claims to be. */
    fun full(id: String = "0") = CharacteristicsData(
        id = id,
        lensFacing = M.LENS_FACING_BACK,
        sensorOrientation = 90,
        hardwareLevel = M.INFO_SUPPORTED_HARDWARE_LEVEL_FULL,
        capabilities = setOf(
            M.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR,
            M.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_POST_PROCESSING,
            M.REQUEST_AVAILABLE_CAPABILITIES_RAW,
        ),
        sensitivityRange = 50 to 3200,
        exposureTimeRangeNs = 100_000L to 1_000_000_000L,
        aeCompensationRange = -12 to 12,
        aeCompensationStep = 1.0 / 3.0,
        aeLockAvailable = true,
        awbLockAvailable = true,
        apertures = listOf(1.8f),
        focalLengths = listOf(4.2f),
        minimumFocusDistanceDiopters = 10f,
        focusCalibration = M.LENS_INFO_FOCUS_DISTANCE_CALIBRATION_APPROXIMATE,
        afModes = ALL_AF,
        awbModes = ALL_AWB,
        maxAfRegions = 1,
        maxAeRegions = 1,
        flashAvailable = true,
        sensorWidthMm = 6.4f,
        sensorHeightMm = 4.8f,
        maxDigitalZoom = 4f,
        zoomRatioRange = 1f to 8f,
        activeArrayWidth = 4000,
        activeArrayHeight = 3000,
        physicalIds = emptyList(),
        jpegSizes = listOf(SizeMessage(4000, 3000), SizeMessage(1920, 1080)),
        heifSizes = listOf(SizeMessage(4000, 3000)),
        rawSizes = listOf(SizeMessage(4000, 3000)),
        surfaceSizes = SURFACE_SIZES,
        minFrameDurationNs = SURFACE_SIZES.associateWith { if (it.width >= 3840) 33_333_333L else 16_666_666L },
        aeTargetFpsRanges = listOf(15 to 30, 30 to 30, 30 to 60),
        opticalStabilizationModes = setOf(M.LENS_OPTICAL_STABILIZATION_MODE_OFF, M.LENS_OPTICAL_STABILIZATION_MODE_ON),
        videoStabilizationModes = setOf(M.CONTROL_VIDEO_STABILIZATION_MODE_OFF, M.CONTROL_VIDEO_STABILIZATION_MODE_ON),
        hdrScenes = true,
    )

    /** A LIMITED device: no MANUAL_SENSOR, no manual post-processing, fixed focus, no flash. */
    fun limited(id: String = "1") = full(id).copy(
        lensFacing = M.LENS_FACING_FRONT,
        sensorOrientation = 270,
        hardwareLevel = M.INFO_SUPPORTED_HARDWARE_LEVEL_LIMITED,
        capabilities = emptySet(),
        minimumFocusDistanceDiopters = 0f,
        afModes = setOf(M.CONTROL_AF_MODE_OFF),
        awbModes = setOf(M.CONTROL_AWB_MODE_AUTO),
        maxAfRegions = 0,
        flashAvailable = false,
        zoomRatioRange = null,
        heifSizes = emptyList(),
        rawSizes = emptyList(),
        opticalStabilizationModes = emptySet(),
        videoStabilizationModes = emptySet(),
        aeLockAvailable = false,
        awbLockAvailable = false,
        hdrScenes = false,
    )

    val media = MediaSupport(videoEncoder = true, audioEncoder = true, microphone = true)

    fun settings(
        iso: Long? = null,
        exposureNs: Long? = null,
        bias: Double? = null,
        aeLock: Boolean = false,
        focus: FocusModeMessage = FocusModeMessage.CONTINUOUS,
        focusDistance: Double? = null,
        afLock: Boolean = false,
        wb: WbPresetMessage? = null,
        kelvin: Long? = null,
        zoom: Double = 1.0,
        flash: FlashModeMessage = FlashModeMessage.OFF,
        torch: Boolean = false,
        stabilization: StabilizationModeMessage? = null,
    ) = ResolvedCaptureSettingsMessage(
        aeLock = aeLock, focusMode = focus, afLock = afLock, zoomRatio = zoom, flash = flash, torch = torch,
        iso = iso, exposureTimeNs = exposureNs, exposureBiasEv = bias, focusDistanceDiopters = focusDistance,
        whiteBalancePreset = wb, kelvin = kelvin, stabilization = stabilization,
    )
}
