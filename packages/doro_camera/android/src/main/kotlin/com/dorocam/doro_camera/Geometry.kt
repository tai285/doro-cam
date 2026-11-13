package com.dorocam.doro_camera

import android.os.PowerManager
import kotlin.math.max
import kotlin.math.min

/** A metering rectangle in active-array pixels with Camera2's weight (0..1000). */
data class Region(val x: Int, val y: Int, val width: Int, val height: Int, val weight: Int = 1000)

/** Pure geometry and mapping helpers of the Camera2 session, so they are unit tested without hardware. */
object Geometry {
    /**
     * Camera2's `JPEG_ORIENTATION` for the current device orientation: the clockwise rotation the saved
     * pixels need to look upright. [deviceOrientation] is the sensor-reported device rotation 0/90/180/270
     * (docs/specs/camera.md: capture follows the sensor, not the UI).
     */
    fun jpegOrientation(sensorOrientation: Int, deviceOrientation: Int, frontFacing: Boolean): Int {
        val device = ((deviceOrientation % 360) + 360) % 360
        val rotation = if (frontFacing) -device else device
        return ((sensorOrientation + rotation) % 360 + 360) % 360
    }

    /** Snaps an `OrientationEventListener` angle (0..359, or -1 unknown) to 0/90/180/270. */
    fun quantizeOrientation(angle: Int, previous: Int): Int {
        if (angle < 0) return previous
        // Hysteresis: stay put within 10 degrees of the boundary so the UI does not flicker.
        val candidate = (((angle + 45) / 90) * 90) % 360
        if (candidate == previous) return previous
        val distance = min((angle - previous + 360) % 360, (previous - angle + 360) % 360)
        return if (distance >= 55) candidate else previous
    }

    /**
     * Maps a tap on the *displayed* preview (x, y in 0..1, with the display upright in portrait) to a
     * metering region in active-array coordinates. The preview is the sensor image rotated by
     * [sensorOrientation] (and mirrored for the front camera), so the tap is rotated back.
     */
    fun meteringRegion(
        x: Double,
        y: Double,
        sensorOrientation: Int,
        frontFacing: Boolean,
        activeWidth: Int,
        activeHeight: Int,
        cropWidth: Int = activeWidth,
        cropHeight: Int = activeHeight,
        halfSize: Double = 0.08,
    ): Region {
        var px = x.coerceIn(0.0, 1.0)
        val py = y.coerceIn(0.0, 1.0)
        if (frontFacing) px = 1.0 - px
        // Undo the display rotation to get sensor-normalised coordinates.
        val (sx, sy) = when ((sensorOrientation % 360 + 360) % 360) {
            90 -> py to (1.0 - px)
            180 -> (1.0 - px) to (1.0 - py)
            270 -> (1.0 - py) to px
            else -> px to py
        }
        val offsetX = (activeWidth - cropWidth) / 2
        val offsetY = (activeHeight - cropHeight) / 2
        val cx = offsetX + sx * cropWidth
        val cy = offsetY + sy * cropHeight
        val half = max(halfSize * min(cropWidth, cropHeight), 1.0)
        val left = (cx - half).toInt().coerceIn(0, activeWidth - 1)
        val top = (cy - half).toInt().coerceIn(0, activeHeight - 1)
        val right = (cx + half).toInt().coerceIn(left + 1, activeWidth)
        val bottom = (cy + half).toInt().coerceIn(top + 1, activeHeight)
        return Region(left, top, right - left, bottom - top)
    }

    /** Centred crop rectangle for digital zoom on devices without `CONTROL_ZOOM_RATIO` (API < 30). */
    fun zoomCrop(activeWidth: Int, activeHeight: Int, zoom: Double): Region {
        val z = max(zoom, 1.0)
        val w = (activeWidth / z).toInt().coerceAtLeast(1)
        val h = (activeHeight / z).toInt().coerceAtLeast(1)
        return Region((activeWidth - w) / 2, (activeHeight - h) / 2, w, h)
    }

    /** Thermal status from `PowerManager` to the contract's four states. */
    fun thermalState(status: Int): ThermalStateMessage = when {
        status >= PowerManager.THERMAL_STATUS_CRITICAL -> ThermalStateMessage.CRITICAL
        status >= PowerManager.THERMAL_STATUS_SEVERE -> ThermalStateMessage.SERIOUS
        status >= PowerManager.THERMAL_STATUS_MODERATE -> ThermalStateMessage.FAIR
        else -> ThermalStateMessage.NOMINAL
    }

    /** Picks the preview size: same aspect as the photo, the largest not exceeding [maxPixels]; else the largest within it. */
    fun choosePreviewSize(options: List<SizeMessage>, photo: SizeMessage, maxPixels: Long = 1920L * 1080L): SizeMessage? {
        val fitting = options.filter { it.width * it.height <= maxPixels }
        if (fitting.isEmpty()) return options.minByOrNull { it.width * it.height }
        val photoAspect = photo.width.toDouble() / photo.height
        val same = fitting.filter { kotlin.math.abs(it.width.toDouble() / it.height - photoAspect) < 0.02 }
        return (same.ifEmpty { fitting }).maxByOrNull { it.width * it.height }
    }

    /** Picks the photo size: the requested one if listed, else the largest (CAM-003). */
    fun choosePhotoSize(options: List<SizeMessage>, requested: SizeMessage?): SizeMessage? =
        if (requested != null && requested in options) requested else options.maxByOrNull { it.width * it.height }
}
