package com.dorocam.doro_camera

import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraMetadata
import android.os.Build

/** Copies the values the probe needs out of a real `CameraCharacteristics` (nothing is assumed per device model). */
object CharacteristicsReader {
    fun read(id: String, c: CameraCharacteristics): CharacteristicsData {
        val map = c.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        fun sizes(format: Int): List<SizeMessage> =
            map?.getOutputSizes(format)?.map { SizeMessage(it.width.toLong(), it.height.toLong()) }.orEmpty()

        val surfaceSizes = map?.getOutputSizes(SurfaceTexture::class.java)?.map { SizeMessage(it.width.toLong(), it.height.toLong()) }.orEmpty()
        val minDurations = buildMap {
            for (size in map?.getOutputSizes(SurfaceTexture::class.java).orEmpty()) {
                put(SizeMessage(size.width.toLong(), size.height.toLong()), map?.getOutputMinFrameDuration(SurfaceTexture::class.java, size) ?: 0L)
            }
        }
        val heif = if (Build.VERSION.SDK_INT >= 28) sizes(ImageFormat.HEIC) else emptyList()
        val sensorSize = c.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
        val active = c.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
        val sensitivity = c.get(CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE)
        val exposure = c.get(CameraCharacteristics.SENSOR_INFO_EXPOSURE_TIME_RANGE)
        val comp = c.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_RANGE)
        val step = c.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_STEP)
        val zoomRange = if (Build.VERSION.SDK_INT >= 30) c.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE) else null
        val capabilities = c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)?.toSet().orEmpty()
        val fpsRanges = c.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)?.map { it.lower to it.upper }.orEmpty()

        return CharacteristicsData(
            id = id,
            lensFacing = c.get(CameraCharacteristics.LENS_FACING),
            sensorOrientation = c.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0,
            hardwareLevel = c.get(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL),
            capabilities = capabilities,
            sensitivityRange = sensitivity?.let { it.lower to it.upper },
            exposureTimeRangeNs = exposure?.let { it.lower to it.upper },
            aeCompensationRange = comp?.let { it.lower to it.upper },
            aeCompensationStep = step?.toDouble() ?: 0.0,
            aeLockAvailable = c.get(CameraCharacteristics.CONTROL_AE_LOCK_AVAILABLE) == true,
            awbLockAvailable = c.get(CameraCharacteristics.CONTROL_AWB_LOCK_AVAILABLE) == true,
            apertures = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_APERTURES)?.toList().orEmpty(),
            focalLengths = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.toList().orEmpty(),
            minimumFocusDistanceDiopters = c.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE),
            focusCalibration = c.get(CameraCharacteristics.LENS_INFO_FOCUS_DISTANCE_CALIBRATION),
            afModes = c.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)?.toSet().orEmpty(),
            awbModes = c.get(CameraCharacteristics.CONTROL_AWB_AVAILABLE_MODES)?.toSet().orEmpty(),
            maxAfRegions = c.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AF) ?: 0,
            maxAeRegions = c.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AE) ?: 0,
            flashAvailable = c.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true,
            sensorWidthMm = sensorSize?.width,
            sensorHeightMm = sensorSize?.height,
            maxDigitalZoom = c.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1f,
            zoomRatioRange = zoomRange?.let { it.lower to it.upper },
            activeArrayWidth = active?.width() ?: 0,
            activeArrayHeight = active?.height() ?: 0,
            physicalIds = if (Build.VERSION.SDK_INT >= 28) c.physicalCameraIds.toList() else emptyList(),
            jpegSizes = sizes(ImageFormat.JPEG),
            heifSizes = heif,
            rawSizes = sizes(ImageFormat.RAW_SENSOR),
            surfaceSizes = surfaceSizes,
            minFrameDurationNs = minDurations,
            aeTargetFpsRanges = fpsRanges,
            opticalStabilizationModes = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION)?.toSet().orEmpty(),
            videoStabilizationModes = c.get(CameraCharacteristics.CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES)?.toSet().orEmpty(),
            hdrScenes = c.get(CameraCharacteristics.CONTROL_AVAILABLE_SCENE_MODES)?.contains(CameraMetadata.CONTROL_SCENE_MODE_HDR) == true,
        )
    }

    fun timestampSourceIsRealtime(c: CameraCharacteristics): Boolean =
        c.get(CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE) == CameraMetadata.SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME
}
