package com.dorocam.doro_camera

import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.hardware.camera2.params.ColorSpaceTransform
import android.hardware.camera2.params.MeteringRectangle
import android.hardware.camera2.params.RggbChannelVector
import android.os.Build

/** The thin Android glue between plain [RequestParams]/[ResultData] values and Camera2 objects. */
object RequestApplier {
    private val IDENTITY_TRANSFORM = ColorSpaceTransform(intArrayOf(1, 1, 0, 1, 0, 1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 1, 1, 1))

    /**
     * Copies [params] onto [builder]. [still] selects the AE mode used for the photo (flash modes) instead of the
     * preview's plain AE. [region] is the tap-to-focus/meter rectangle, if any.
     */
    fun apply(builder: CaptureRequest.Builder, params: RequestParams, data: CharacteristicsData, still: Boolean, region: Region?) {
        builder.set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
        builder.set(CaptureRequest.CONTROL_AE_MODE, if (still) params.stillAeMode else params.aeMode)
        if (params.manualExposure) {
            params.sensitivity?.let { builder.set(CaptureRequest.SENSOR_SENSITIVITY, it) }
            params.exposureTimeNs?.let { builder.set(CaptureRequest.SENSOR_EXPOSURE_TIME, it) }
        } else {
            builder.set(CaptureRequest.CONTROL_AE_EXPOSURE_COMPENSATION, params.aeCompensationIndex)
            if (data.aeLockAvailable) builder.set(CaptureRequest.CONTROL_AE_LOCK, params.aeLock)
        }
        builder.set(CaptureRequest.CONTROL_AF_MODE, params.afMode)
        params.focusDistance?.let { builder.set(CaptureRequest.LENS_FOCUS_DISTANCE, it) }
        builder.set(CaptureRequest.CONTROL_AWB_MODE, params.awbMode)
        if (data.awbLockAvailable) builder.set(CaptureRequest.CONTROL_AWB_LOCK, params.awbLock)
        params.colorGains?.let { gains ->
            builder.set(CaptureRequest.COLOR_CORRECTION_MODE, CameraMetadata.COLOR_CORRECTION_MODE_TRANSFORM_MATRIX)
            builder.set(CaptureRequest.COLOR_CORRECTION_GAINS, RggbChannelVector(gains[0], gains[1], gains[2], gains[3]))
            builder.set(CaptureRequest.COLOR_CORRECTION_TRANSFORM, IDENTITY_TRANSFORM)
        }
        if (Build.VERSION.SDK_INT >= 30 && data.zoomRatioRange != null) {
            builder.set(CaptureRequest.CONTROL_ZOOM_RATIO, params.zoomRatio)
        } else if (params.zoomRatio > 1.0f && data.activeArrayWidth > 0) {
            val crop = Geometry.zoomCrop(data.activeArrayWidth, data.activeArrayHeight, params.zoomRatio.toDouble())
            builder.set(CaptureRequest.SCALER_CROP_REGION, android.graphics.Rect(crop.x, crop.y, crop.x + crop.width, crop.y + crop.height))
        }
        builder.set(CaptureRequest.FLASH_MODE, if (still) CameraMetadata.FLASH_MODE_OFF else params.flashMode)
        params.opticalStabilization?.let { builder.set(CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE, it) }
        params.videoStabilization?.let { builder.set(CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE, it) }
        if (region != null) {
            val rect = MeteringRectangle(region.x, region.y, region.width, region.height, region.weight)
            if (data.maxAfRegions > 0) builder.set(CaptureRequest.CONTROL_AF_REGIONS, arrayOf(rect))
            if (data.maxAeRegions > 0) builder.set(CaptureRequest.CONTROL_AE_REGIONS, arrayOf(rect))
        }
    }

    fun read(result: TotalCaptureResult): ResultData {
        val gains = result.get(CaptureResult.COLOR_CORRECTION_GAINS)
        val zoom = if (Build.VERSION.SDK_INT >= 30) result.get(CaptureResult.CONTROL_ZOOM_RATIO) else null
        return ResultData(
            sensitivity = result.get(CaptureResult.SENSOR_SENSITIVITY),
            exposureTimeNs = result.get(CaptureResult.SENSOR_EXPOSURE_TIME),
            aeCompensationIndex = result.get(CaptureResult.CONTROL_AE_EXPOSURE_COMPENSATION),
            aperture = result.get(CaptureResult.LENS_APERTURE),
            focalLength = result.get(CaptureResult.LENS_FOCAL_LENGTH),
            focusDistance = result.get(CaptureResult.LENS_FOCUS_DISTANCE),
            afMode = result.get(CaptureResult.CONTROL_AF_MODE),
            afState = result.get(CaptureResult.CONTROL_AF_STATE),
            awbMode = result.get(CaptureResult.CONTROL_AWB_MODE),
            colorGains = gains?.let { listOf(it.red, it.greenEven, it.greenOdd, it.blue) },
            zoomRatio = zoom,
            cropWidth = result.get(CaptureResult.SCALER_CROP_REGION)?.width(),
            flashState = result.get(CaptureResult.FLASH_STATE),
            flashMode = result.get(CaptureResult.FLASH_MODE),
            aeLock = result.get(CaptureResult.CONTROL_AE_LOCK),
            awbLock = result.get(CaptureResult.CONTROL_AWB_LOCK),
            aeMode = result.get(CaptureResult.CONTROL_AE_MODE),
            opticalStabilization = result.get(CaptureResult.LENS_OPTICAL_STABILIZATION_MODE),
            videoStabilization = result.get(CaptureResult.CONTROL_VIDEO_STABILIZATION_MODE),
        )
    }

    /** Keys the AE state of the result, for "has the metering settled?" checks. */
    fun aeState(result: TotalCaptureResult): Int? = result.get(CaptureResult.CONTROL_AE_STATE)

    fun afState(result: TotalCaptureResult): Int? = result.get(CaptureResult.CONTROL_AF_STATE)

}
