package com.dorocam.doro_camera

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Paths of the renditions produced from an original. */
data class Renditions(val rendered: File, val thumbnail: File, val display: File)

/**
 * Produces the `rendered`, `display` and `thumbnail` JPEGs from the untouched original
 * (docs/architecture/camera.md capture pipeline, steps 4-5): decode, rotate upright, crop to the chosen aspect,
 * apply the look, encode. The original is never modified (PRF-002); if anything here fails the caller keeps
 * the original and reports `renderFailed` so rendering can be retried later.
 */
class RenditionWriter {
    companion object {
        const val DISPLAY_LONG_EDGE = 2048
        const val THUMBNAIL_LONG_EDGE = 512
        /** Decoded images above this size are sub-sampled so a 100 MP sensor cannot exhaust memory. */
        const val MAX_DECODE_PIXELS = 36_000_000L
        private const val BAND_PIXELS = 1_000_000

        fun sampleSizeFor(width: Int, height: Int, maxPixels: Long = MAX_DECODE_PIXELS): Int {
            var sample = 1
            while ((width.toLong() / sample) * (height.toLong() / sample) > maxPixels) sample *= 2
            return sample
        }
    }

    fun write(original: File, orientationDegrees: Int, request: CaptureRequestMessage): Renditions {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(original.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw CameraException("capture_failed", "The captured image could not be decoded")
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSizeFor(bounds.outWidth, bounds.outHeight)
            inMutable = true
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        var bitmap = BitmapFactory.decodeFile(original.path, options)
            ?: throw CameraException("capture_failed", "The captured image could not be decoded")

        if (orientationDegrees % 360 != 0) {
            val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, Matrix().apply { postRotate(orientationDegrees.toFloat()) }, true)
            if (rotated !== bitmap) bitmap.recycle()
            bitmap = rotated
        }
        val spec = request.render
        ImageMath.cropFor(bitmap.width, bitmap.height, spec?.aspectRatio)?.let { crop ->
            val cropped = Bitmap.createBitmap(bitmap, crop.left, crop.top, crop.width, crop.height)
            if (cropped !== bitmap) bitmap.recycle()
            bitmap = cropped
        }
        if (!bitmap.isMutable) bitmap = bitmap.copy(Bitmap.Config.ARGB_8888, true)
        if (spec != null) applyLook(bitmap, spec, seed = request.memoryId.hashCode().toLong())

        val renderedFile = AtomicFiles.target(request.outputDir, request.renderedName)
        writeJpeg(bitmap, renderedFile, request)

        val (dw, dh) = ImageMath.fitLongEdge(bitmap.width, bitmap.height, DISPLAY_LONG_EDGE)
        val display = if (dw == bitmap.width) bitmap else Bitmap.createScaledBitmap(bitmap, dw, dh, true)
        val displayFile = AtomicFiles.target(request.outputDir, request.displayName)
        writeJpeg(display, displayFile, request, quality = 85)

        val (tw, th) = ImageMath.fitLongEdge(display.width, display.height, THUMBNAIL_LONG_EDGE)
        val thumb = if (tw == display.width) display else Bitmap.createScaledBitmap(display, tw, th, true)
        val thumbFile = AtomicFiles.target(request.outputDir, request.thumbnailName)
        writeJpeg(thumb, thumbFile, request, quality = 80, withMetadata = false)

        if (thumb !== display) thumb.recycle()
        if (display !== bitmap) display.recycle()
        bitmap.recycle()
        return Renditions(renderedFile, thumbFile, displayFile)
    }

    private fun applyLook(bitmap: Bitmap, spec: RenderSpecMessage, seed: Long) {
        val width = bitmap.width
        val height = bitmap.height
        val lut = spec.lut
        val lutSize = spec.lutSize?.toInt()
        val useLut = ImageMath.validLut(lut, lutSize)
        if (!useLut && spec.grain <= 0.0 && spec.vignette <= 0.0) return
        val rowsPerBand = (BAND_PIXELS / width).coerceAtLeast(1)
        val buffer = IntArray(rowsPerBand * width)
        var y = 0
        while (y < height) {
            val rows = minOf(rowsPerBand, height - y)
            bitmap.getPixels(buffer, 0, width, 0, y, width, rows)
            val band = if (rows == rowsPerBand) buffer else buffer.copyOf(rows * width)
            if (useLut) ImageMath.applyLut(band, lut!!, lutSize!!)
            ImageMath.applyVignette(band, width, height, spec.vignette, row0 = y)
            ImageMath.applyGrain(band, spec.grain, seed, from = y * width)
            bitmap.setPixels(band, 0, width, 0, y, width, rows)
            y += rows
        }
    }

    private fun writeJpeg(bitmap: Bitmap, target: File, request: CaptureRequestMessage, quality: Int? = null, withMetadata: Boolean = true) {
        val temp = AtomicFiles.tempFor(target)
        try {
            java.io.FileOutputStream(temp).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality ?: request.jpegQuality.toInt().coerceIn(50, 100), out)
                out.flush()
                out.fd.sync()
            }
            if (withMetadata) writeExif(temp, request)
            AtomicFiles.commit(temp, target)
        } catch (e: java.io.IOException) {
            temp.delete()
            throw AtomicFiles.ioToCamera(e)
        }
    }

    /** Capture time and memory id always; GPS only when the app passed a location (PRIV-001). */
    private fun writeExif(file: File, request: CaptureRequestMessage) {
        val exif = ExifInterface(file.path)
        val whenMs = request.timestampEpochMs ?: System.currentTimeMillis()
        val format = SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.US).apply { timeZone = TimeZone.getDefault() }
        exif.setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, format.format(Date(whenMs)))
        exif.setAttribute(ExifInterface.TAG_SOFTWARE, "Doro Cam")
        exif.setAttribute(ExifInterface.TAG_USER_COMMENT, "doro:memoryId=${request.memoryId}")
        exif.setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL.toString())
        request.location?.let { exif.setLatLong(it.latitude, it.longitude) }
        exif.saveAttributes()
    }
}
