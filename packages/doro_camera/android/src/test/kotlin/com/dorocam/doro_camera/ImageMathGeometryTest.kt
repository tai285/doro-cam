package com.dorocam.doro_camera

import android.os.PowerManager
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class ImageMathTest {
    private fun px(r: Int, g: Int, b: Int, a: Int = 255) = (a shl 24) or (r shl 16) or (g shl 8) or b
    private fun r(p: Int) = (p shr 16) and 0xFF
    private fun g(p: Int) = (p shr 8) and 0xFF
    private fun b(p: Int) = p and 0xFF

    // [CAM-044]
    @Test
    fun `aspect ratios parse only when valid`() {
        assertEquals(1.5, ImageMath.parseAspect("3:2"))
        assertEquals(1.0, ImageMath.parseAspect("1:1"))
        assertNull(ImageMath.parseAspect(null))
        assertNull(ImageMath.parseAspect("3x2"))
        assertNull(ImageMath.parseAspect("0:2"))
        assertNull(ImageMath.parseAspect("a:b"))
        assertNull(ImageMath.parseAspect("1:2:3"))
    }

    // [CAM-044]
    @Test
    fun `crop is the largest centred rectangle with the requested aspect, matched to the image orientation`() {
        // 4:3 landscape to 16:9 trims height
        assertEquals(CropRect(0, 375, 4000, 2250), ImageMath.cropFor(4000, 3000, "16:9"))
        // 4:3 to 1:1 trims width
        assertEquals(CropRect(500, 0, 3000, 3000), ImageMath.cropFor(4000, 3000, "1:1"))
        // portrait image with "3:2" means 2:3
        assertEquals(CropRect(0, 250, 3000, 4500).let { CropRect(it.left, it.top, it.width, it.height) }, ImageMath.cropFor(3000, 5000, "3:2"))
        // already the right shape, or no aspect: no crop
        assertNull(ImageMath.cropFor(3000, 2000, "3:2"))
        assertNull(ImageMath.cropFor(3000, 2000, null))
        assertNull(ImageMath.cropFor(3000, 2000, "nonsense"))
        // landscape image with a portrait-style ratio is flipped to landscape
        assertEquals(CropRect(0, 375, 4000, 2250), ImageMath.cropFor(4000, 3000, "9:16"))
    }

    @Test
    fun `fitting to a long edge never enlarges`() {
        assertEquals(2048 to 1536, ImageMath.fitLongEdge(4000, 3000, 2048))
        assertEquals(384 to 512, ImageMath.fitLongEdge(3000, 4000, 512))
        assertEquals(100 to 50, ImageMath.fitLongEdge(100, 50, 512))
    }

    // [PRF-002]
    @Test
    fun `an identity LUT leaves pixels unchanged`() {
        val lut = ImageMath.identityLut(17)
        val pixels = intArrayOf(px(0, 0, 0), px(255, 255, 255), px(12, 200, 77), px(128, 64, 250, a = 10))
        val copy = pixels.copyOf()
        ImageMath.applyLut(pixels, lut, 17)
        for (i in pixels.indices) {
            assertTrue(kotlin.math.abs(r(pixels[i]) - r(copy[i])) <= 1 && kotlin.math.abs(g(pixels[i]) - g(copy[i])) <= 1 && kotlin.math.abs(b(pixels[i]) - b(copy[i])) <= 1, "pixel $i")
            assertEquals(copy[i] ushr 24, pixels[i] ushr 24, "alpha kept")
        }
    }

    // [PRF-003]
    @Test
    fun `a LUT that inverts the channels is applied with interpolation`() {
        val size = 5
        val lut = ImageMath.identityLut(size)
        for (i in lut.indices) lut[i] = (255 - (lut[i].toInt() and 0xFF)).toByte()
        val pixels = intArrayOf(px(0, 0, 0), px(255, 255, 255), px(100, 150, 200))
        ImageMath.applyLut(pixels, lut, size)
        assertEquals(px(255, 255, 255), pixels[0])
        assertEquals(px(0, 0, 0), pixels[1])
        assertTrue(kotlin.math.abs(r(pixels[2]) - 155) <= 2 && kotlin.math.abs(g(pixels[2]) - 105) <= 2 && kotlin.math.abs(b(pixels[2]) - 55) <= 2)
    }

    @Test
    fun `LUT validation checks size and length`() {
        assertTrue(ImageMath.validLut(ImageMath.identityLut(8), 8))
        assertFalse(ImageMath.validLut(null, 8))
        assertFalse(ImageMath.validLut(ImageMath.identityLut(8), null))
        assertFalse(ImageMath.validLut(ImageMath.identityLut(8), 9))
        assertFalse(ImageMath.validLut(ByteArray(3), 1))
    }

    // [PRF-006]
    @Test
    fun `vignette darkens corners more than the centre and strength zero changes nothing`() {
        val w = 9
        val h = 9
        val pixels = IntArray(w * h) { px(200, 200, 200) }
        ImageMath.applyVignette(pixels, w, h, 0.0)
        assertTrue(pixels.all { it == px(200, 200, 200) })
        ImageMath.applyVignette(pixels, w, h, 0.8)
        val centre = r(pixels[4 * w + 4])
        val corner = r(pixels[0])
        assertTrue(centre > corner, "centre $centre corner $corner")
        assertEquals(200, centre)
    }

    @Test
    fun `a band of a large image gets the same vignette as the whole image`() {
        val w = 8
        val h = 8
        val whole = IntArray(w * h) { px(180, 180, 180) }
        ImageMath.applyVignette(whole, w, h, 0.6)
        val band = IntArray(w * 3) { px(180, 180, 180) }
        ImageMath.applyVignette(band, w, h, 0.6, row0 = 5)
        for (i in band.indices) assertEquals(whole[5 * w + i], band[i])
    }

    // [PRF-006]
    @Test
    fun `grain is deterministic for a seed, differs between seeds and stays in range`() {
        fun grained(seed: Long) = IntArray(64) { px(128, 128, 128) }.also { ImageMath.applyGrain(it, 0.5, seed) }
        assertTrue(grained(1).contentEquals(grained(1)))
        assertFalse(grained(1).contentEquals(grained(2)))
        assertTrue(grained(1).any { it != px(128, 128, 128) })
        val extreme = IntArray(32) { px(255, 0, 255) }.also { ImageMath.applyGrain(it, 1.0, 3) }
        assertTrue(extreme.all { r(it) in 0..255 && g(it) in 0..255 && b(it) in 0..255 })
        val untouched = IntArray(4) { px(1, 2, 3) }.also { ImageMath.applyGrain(it, 0.0, 3) }
        assertTrue(untouched.all { it == px(1, 2, 3) })
    }

    @Test
    fun `the grain hash is uniform enough`() {
        val values = (0 until 2000L).map { ImageMath.hash(7, it) }
        assertTrue(values.all { it in 0.0..1.0 })
        val mean = values.average()
        assertTrue(mean in 0.45..0.55, "mean $mean")
        assertNotEquals(ImageMath.hash(1, 5), ImageMath.hash(1, 6))
    }

    @Test
    fun `decoding is sub-sampled so huge sensors cannot exhaust memory`() {
        assertEquals(1, RenditionWriter.sampleSizeFor(4000, 3000))
        assertEquals(2, RenditionWriter.sampleSizeFor(9000, 7000))
        assertEquals(4, RenditionWriter.sampleSizeFor(16000, 12000))
    }
}

internal class GeometryTest {
    // [CAM-053] capture follows the sensor orientation
    @Test
    fun `JPEG orientation combines sensor orientation with the device rotation, mirrored for the front camera`() {
        assertEquals(90, Geometry.jpegOrientation(90, 0, false))
        assertEquals(180, Geometry.jpegOrientation(90, 90, false))
        assertEquals(0, Geometry.jpegOrientation(90, 270, false))
        assertEquals(270, Geometry.jpegOrientation(270, 0, true))
        assertEquals(180, Geometry.jpegOrientation(270, 90, true))
        assertEquals(90, Geometry.jpegOrientation(90, 360, false))
        assertEquals(0, Geometry.jpegOrientation(90, -90, false))
    }

    @Test
    fun `orientation snaps to quarter turns with hysteresis`() {
        assertEquals(0, Geometry.quantizeOrientation(10, 0))
        assertEquals(0, Geometry.quantizeOrientation(50, 0)) // not far enough to flip yet
        assertEquals(90, Geometry.quantizeOrientation(60, 0))
        assertEquals(90, Geometry.quantizeOrientation(100, 90))
        assertEquals(0, Geometry.quantizeOrientation(355, 0))
        assertEquals(270, Geometry.quantizeOrientation(-1, 270)) // unknown angle keeps the previous value
        assertEquals(180, Geometry.quantizeOrientation(180, 90))
    }

    // [CAM-020]
    @Test
    fun `a tap maps back through the sensor rotation into active array coordinates`() {
        // Sensor rotated 90: the top-left of the display is the bottom-left of the sensor image... verified per corner.
        val tl = Geometry.meteringRegion(0.0, 0.0, 90, false, 4000, 3000, halfSize = 0.01)
        assertTrue(tl.x < 200 && tl.y > 2700, "top-left of a 90-degree sensor is the sensor's bottom-left: $tl")
        val br = Geometry.meteringRegion(1.0, 1.0, 90, false, 4000, 3000, halfSize = 0.01)
        assertTrue(br.x > 3800 && br.y < 200, "bottom-right: $br")
        val centre = Geometry.meteringRegion(0.5, 0.5, 90, false, 4000, 3000)
        assertTrue(kotlin.math.abs(centre.x + centre.width / 2 - 2000) <= 2 && kotlin.math.abs(centre.y + centre.height / 2 - 1500) <= 2)
        val zero = Geometry.meteringRegion(0.0, 0.0, 0, false, 4000, 3000, halfSize = 0.01)
        assertTrue(zero.x < 100 && zero.y < 100)
        val r180 = Geometry.meteringRegion(0.0, 0.0, 180, false, 4000, 3000, halfSize = 0.01)
        assertTrue(r180.x > 3800 && r180.y > 2800)
        val r270 = Geometry.meteringRegion(0.0, 0.0, 270, false, 4000, 3000, halfSize = 0.01)
        assertTrue(r270.x > 3800 && r270.y < 200, "270: $r270")
    }

    @Test
    fun `the front camera preview is mirrored so the tap is mirrored back`() {
        val back = Geometry.meteringRegion(0.1, 0.5, 0, false, 4000, 3000, halfSize = 0.01)
        val front = Geometry.meteringRegion(0.1, 0.5, 0, true, 4000, 3000, halfSize = 0.01)
        assertTrue(back.x < 600 && front.x > 3400)
    }

    @Test
    fun `regions stay inside the sensor, also at the edges and when zoomed`() {
        for ((x, y) in listOf(0.0 to 0.0, 1.0 to 1.0, 0.0 to 1.0, 1.0 to 0.0, -5.0 to 7.0)) {
            val r = Geometry.meteringRegion(x, y, 90, false, 4000, 3000)
            assertTrue(r.x >= 0 && r.y >= 0 && r.x + r.width <= 4000 && r.y + r.height <= 3000 && r.width >= 1 && r.height >= 1, "$x,$y -> $r")
        }
        val zoomed = Geometry.meteringRegion(0.5, 0.5, 0, false, 4000, 3000, cropWidth = 2000, cropHeight = 1500)
        assertTrue(kotlin.math.abs(zoomed.x + zoomed.width / 2 - 2000) <= 2)
        assertTrue(zoomed.width < 400)
    }

    @Test
    fun `digital zoom crops the centre`() {
        assertEquals(Region(1000, 750, 2000, 1500), Geometry.zoomCrop(4000, 3000, 2.0))
        assertEquals(Region(0, 0, 4000, 3000), Geometry.zoomCrop(4000, 3000, 0.5))
    }

    // [NFR-012]
    @Test
    fun `thermal status maps onto the four contract states`() {
        assertEquals(ThermalStateMessage.NOMINAL, Geometry.thermalState(PowerManager.THERMAL_STATUS_NONE))
        assertEquals(ThermalStateMessage.NOMINAL, Geometry.thermalState(PowerManager.THERMAL_STATUS_LIGHT))
        assertEquals(ThermalStateMessage.FAIR, Geometry.thermalState(PowerManager.THERMAL_STATUS_MODERATE))
        assertEquals(ThermalStateMessage.SERIOUS, Geometry.thermalState(PowerManager.THERMAL_STATUS_SEVERE))
        assertEquals(ThermalStateMessage.CRITICAL, Geometry.thermalState(PowerManager.THERMAL_STATUS_CRITICAL))
        assertEquals(ThermalStateMessage.CRITICAL, Geometry.thermalState(PowerManager.THERMAL_STATUS_SHUTDOWN))
    }

    @Test
    fun `preview size prefers the photo aspect up to 1080p, photo size defaults to the largest`() {
        val sizes = listOf(SizeMessage(1920, 1080), SizeMessage(1600, 1200), SizeMessage(1280, 720), SizeMessage(640, 480), SizeMessage(4000, 3000))
        assertEquals(SizeMessage(1600, 1200), Geometry.choosePreviewSize(sizes, SizeMessage(4000, 3000)))
        assertEquals(SizeMessage(1920, 1080), Geometry.choosePreviewSize(sizes, SizeMessage(1920, 1080)))
        assertEquals(SizeMessage(1280, 720), Geometry.choosePreviewSize(listOf(SizeMessage(1280, 720), SizeMessage(2000, 2000)), SizeMessage(4000, 3000)))
        assertEquals(SizeMessage(5000, 5000), Geometry.choosePreviewSize(listOf(SizeMessage(5000, 5000)), SizeMessage(4000, 3000)))
        assertNull(Geometry.choosePreviewSize(emptyList(), SizeMessage(1, 1)))
        assertEquals(SizeMessage(4000, 3000), Geometry.choosePhotoSize(listOf(SizeMessage(1920, 1080), SizeMessage(4000, 3000)), null))
        assertEquals(SizeMessage(1920, 1080), Geometry.choosePhotoSize(listOf(SizeMessage(1920, 1080), SizeMessage(4000, 3000)), SizeMessage(1920, 1080)))
        assertEquals(SizeMessage(4000, 3000), Geometry.choosePhotoSize(listOf(SizeMessage(1920, 1080), SizeMessage(4000, 3000)), SizeMessage(1, 1)))
        assertNull(Geometry.choosePhotoSize(emptyList(), null))
    }
}
