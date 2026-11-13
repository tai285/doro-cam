package com.dorocam.doro_camera

import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** A crop rectangle in pixels. */
data class CropRect(val left: Int, val top: Int, val width: Int, val height: Int)

/**
 * Pixel math for the rendered rendition (ADR-0004, PRF-003): a 3D LUT, vignette, grain and the crop for
 * the chosen aspect ratio. It works on ARGB `IntArray`s so it is exact, deterministic and unit tested on
 * the JVM; the Android glue only decodes, calls this and encodes.
 */
object ImageMath {
    /** `W:H` such as `3:2` to a ratio, or null if it is not a valid positive ratio. */
    fun parseAspect(text: String?): Double? {
        if (text == null) return null
        val parts = text.split(':')
        if (parts.size != 2) return null
        val w = parts[0].trim().toDoubleOrNull() ?: return null
        val h = parts[1].trim().toDoubleOrNull() ?: return null
        return if (w > 0 && h > 0) w / h else null
    }

    /** Largest centred crop of a [width] x [height] image with the aspect of [aspectText]; null = no crop. */
    fun cropFor(width: Int, height: Int, aspectText: String?, portrait: Boolean = height > width): CropRect? {
        var ratio = parseAspect(aspectText) ?: return null
        // The user thinks of "3:2" as the long side over the short side; match it to the image orientation.
        if (portrait && ratio > 1.0) ratio = 1.0 / ratio
        if (!portrait && ratio < 1.0) ratio = 1.0 / ratio
        val current = width.toDouble() / height
        if (kotlin.math.abs(current - ratio) < 0.001) return null
        return if (current > ratio) {
            val w = (height * ratio).toInt().coerceAtLeast(1)
            CropRect((width - w) / 2, 0, w, height)
        } else {
            val h = (width / ratio).toInt().coerceAtLeast(1)
            CropRect(0, (height - h) / 2, width, h)
        }
    }

    /** Size that fits [width] x [height] inside a square of [longEdge], never enlarging. */
    fun fitLongEdge(width: Int, height: Int, longEdge: Int): Pair<Int, Int> {
        val long = max(width, height)
        if (long <= longEdge) return width to height
        val scale = longEdge.toDouble() / long
        return max(1, (width * scale).toInt()) to max(1, (height * scale).toInt())
    }

    /** An identity cube LUT with [size] points per axis (R fastest), 3 bytes per entry. */
    fun identityLut(size: Int): ByteArray {
        val out = ByteArray(size * size * size * 3)
        var i = 0
        for (b in 0 until size) for (g in 0 until size) for (r in 0 until size) {
            out[i++] = (r * 255 / (size - 1)).toByte()
            out[i++] = (g * 255 / (size - 1)).toByte()
            out[i++] = (b * 255 / (size - 1)).toByte()
        }
        return out
    }

    fun validLut(lut: ByteArray?, size: Int?): Boolean = lut != null && size != null && size in 2..65 && lut.size == size * size * size * 3

    private fun lutAt(lut: ByteArray, size: Int, r: Int, g: Int, b: Int, channel: Int): Int =
        lut[((b * size + g) * size + r) * 3 + channel].toInt() and 0xFF

    /** Applies a cube LUT with trilinear interpolation, in place. Alpha is left untouched. */
    fun applyLut(pixels: IntArray, lut: ByteArray, size: Int, from: Int = 0, to: Int = pixels.size) {
        val scale = (size - 1) / 255.0
        for (i in from until to) {
            val p = pixels[i]
            val rf = ((p shr 16) and 0xFF) * scale
            val gf = ((p shr 8) and 0xFF) * scale
            val bf = (p and 0xFF) * scale
            val r0 = min(rf.toInt(), size - 2)
            val g0 = min(gf.toInt(), size - 2)
            val b0 = min(bf.toInt(), size - 2)
            val dr = rf - r0
            val dg = gf - g0
            val db = bf - b0
            var out = p and (0xFF shl 24)
            for (channel in 0..2) {
                val c000 = lutAt(lut, size, r0, g0, b0, channel)
                val c100 = lutAt(lut, size, r0 + 1, g0, b0, channel)
                val c010 = lutAt(lut, size, r0, g0 + 1, b0, channel)
                val c110 = lutAt(lut, size, r0 + 1, g0 + 1, b0, channel)
                val c001 = lutAt(lut, size, r0, g0, b0 + 1, channel)
                val c101 = lutAt(lut, size, r0 + 1, g0, b0 + 1, channel)
                val c011 = lutAt(lut, size, r0, g0 + 1, b0 + 1, channel)
                val c111 = lutAt(lut, size, r0 + 1, g0 + 1, b0 + 1, channel)
                val c00 = c000 + (c100 - c000) * dr
                val c10 = c010 + (c110 - c010) * dr
                val c01 = c001 + (c101 - c001) * dr
                val c11 = c011 + (c111 - c011) * dr
                val c0 = c00 + (c10 - c00) * dg
                val c1 = c01 + (c11 - c01) * dg
                val v = (c0 + (c1 - c0) * db + 0.5).toInt().coerceIn(0, 255)
                out = out or (v shl (16 - 8 * channel))
            }
            pixels[i] = out
        }
    }

    /**
     * Darkens towards the corners, in place. [strength] 0..1; 0 changes nothing. [row0] is the image row of
     * the first pixel of [pixels], so a band of a large image gets the same result as the whole image.
     */
    fun applyVignette(pixels: IntArray, width: Int, height: Int, strength: Double, row0: Int = 0) {
        if (strength <= 0.0) return
        val cx = (width - 1) / 2.0
        val cy = (height - 1) / 2.0
        val maxDistance = sqrt(cx * cx + cy * cy).coerceAtLeast(1.0)
        val rows = pixels.size / width
        for (y in 0 until rows) {
            val dy = (row0 + y) - cy
            for (x in 0 until width) {
                val dx = x - cx
                val d = sqrt(dx * dx + dy * dy) / maxDistance
                val factor = 1.0 - strength * d * d
                val i = y * width + x
                val p = pixels[i]
                val r = (((p shr 16) and 0xFF) * factor).toInt().coerceIn(0, 255)
                val g = (((p shr 8) and 0xFF) * factor).toInt().coerceIn(0, 255)
                val b = ((p and 0xFF) * factor).toInt().coerceIn(0, 255)
                pixels[i] = (p and (0xFF shl 24)) or (r shl 16) or (g shl 8) or b
            }
        }
    }

    /** Adds deterministic film grain (same seed, same output), in place. [strength] 0..1. */
    fun applyGrain(pixels: IntArray, strength: Double, seed: Long = 1L, from: Int = 0) {
        if (strength <= 0.0) return
        val amplitude = strength * 40.0
        for (i in pixels.indices) {
            val noise = (hash(seed, (from + i).toLong()) - 0.5) * 2.0 * amplitude
            val p = pixels[i]
            val r = (((p shr 16) and 0xFF) + noise).toInt().coerceIn(0, 255)
            val g = (((p shr 8) and 0xFF) + noise).toInt().coerceIn(0, 255)
            val b = ((p and 0xFF) + noise).toInt().coerceIn(0, 255)
            pixels[i] = (p and (0xFF shl 24)) or (r shl 16) or (g shl 8) or b
        }
    }

    /** A cheap, reproducible hash to 0..1 (splitmix-style). */
    internal fun hash(seed: Long, index: Long): Double {
        var z = seed + index * -7046029254386353131L
        z = (z xor (z ushr 30)) * -4658895280553007687L
        z = (z xor (z ushr 27)) * -7723592293110705685L
        z = z xor (z ushr 31)
        return (z ushr 11).toDouble() / (1L shl 53).toDouble()
    }
}
