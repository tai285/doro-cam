package com.dorocam.doro_camera

import android.hardware.camera2.CameraMetadata as M
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class SettingsMapperTest {
    private val full = Fixtures.full()
    private val limited = Fixtures.limited()
    private fun map(s: ResolvedCaptureSettingsMessage, d: CharacteristicsData = full, auto: AutoSnapshot? = null, video: Boolean = false) =
        SettingsMapper.map(s, d, auto, video)

    // [CAM-010] [CAM-011]
    @Test
    fun `manual ISO and shutter switch AE off and set both values within range`() {
        val p = map(Fixtures.settings(iso = 400, exposureNs = 8_000_000))
        assertEquals(M.CONTROL_AE_MODE_OFF, p.aeMode)
        assertEquals(400, p.sensitivity)
        assertEquals(8_000_000L, p.exposureTimeNs)
        assertTrue(p.manualExposure)
    }

    @Test
    fun `values outside the device range are clamped at the last line of defence`() {
        val p = map(Fixtures.settings(iso = 100_000, exposureNs = 1L))
        assertEquals(3200, p.sensitivity)
        assertEquals(100_000L, p.exposureTimeNs)
    }

    // docs/specs/camera.md rule 3
    @Test
    fun `when only ISO is manual the shutter keeps the metered value`() {
        val p = map(Fixtures.settings(iso = 800), auto = AutoSnapshot(iso = 100, exposureTimeNs = 20_000_000))
        assertEquals(800, p.sensitivity)
        assertEquals(20_000_000L, p.exposureTimeNs)
        val q = map(Fixtures.settings(exposureNs = 4_000_000), auto = AutoSnapshot(iso = 640, exposureTimeNs = 1))
        assertEquals(640, q.sensitivity)
        assertEquals(4_000_000L, q.exposureTimeNs)
    }

    @Test
    fun `without a metered snapshot documented defaults are used`() {
        val p = map(Fixtures.settings(iso = 200))
        assertEquals(SettingsMapper.DEFAULT_EXPOSURE_NS, p.exposureTimeNs)
        assertEquals(SettingsMapper.DEFAULT_ISO, map(Fixtures.settings(exposureNs = 5_000_000)).sensitivity)
    }

    // [CAM-005]
    @Test
    fun `a manual request on a device without manual sensor stays automatic`() {
        val p = map(Fixtures.settings(iso = 400, exposureNs = 8_000_000), limited)
        assertEquals(M.CONTROL_AE_MODE_ON, p.aeMode)
        assertNull(p.sensitivity)
        assertFalse(p.manualExposure)
    }

    // [CAM-012]
    @Test
    fun `exposure bias becomes a clamped step index and is ignored in manual exposure`() {
        assertEquals(3, map(Fixtures.settings(bias = 1.0)).aeCompensationIndex)
        assertEquals(12, map(Fixtures.settings(bias = 99.0)).aeCompensationIndex)
        assertEquals(-12, map(Fixtures.settings(bias = -99.0)).aeCompensationIndex)
        assertEquals(0, map(Fixtures.settings(bias = 1.0, iso = 100, exposureNs = 1_000_000)).aeCompensationIndex)
        assertEquals(0, map(Fixtures.settings(bias = 1.0), limited.copy(aeCompensationRange = 0 to 0)).aeCompensationIndex)
    }

    // [CAM-014]
    @Test
    fun `AE lock applies only with automatic exposure and when the device supports it`() {
        assertTrue(map(Fixtures.settings(aeLock = true)).aeLock)
        assertFalse(map(Fixtures.settings(aeLock = true, iso = 100, exposureNs = 1_000_000)).aeLock)
        assertFalse(map(Fixtures.settings(aeLock = true), limited).aeLock)
    }

    // [CAM-040]
    @Test
    fun `flash modes map to still AE modes while the preview stays plain AE, torch uses FLASH_MODE_TORCH`() {
        assertEquals(M.CONTROL_AE_MODE_ON_AUTO_FLASH, map(Fixtures.settings(flash = FlashModeMessage.AUTO)).stillAeMode)
        assertEquals(M.CONTROL_AE_MODE_ON_ALWAYS_FLASH, map(Fixtures.settings(flash = FlashModeMessage.ON)).stillAeMode)
        assertEquals(M.CONTROL_AE_MODE_ON, map(Fixtures.settings(flash = FlashModeMessage.ON)).aeMode)
        assertEquals(M.CONTROL_AE_MODE_ON, map(Fixtures.settings(flash = FlashModeMessage.ON), limited).stillAeMode)
        assertEquals(M.CONTROL_AE_MODE_OFF, map(Fixtures.settings(flash = FlashModeMessage.ON, iso = 100, exposureNs = 1_000_000)).stillAeMode)
        assertEquals(M.FLASH_MODE_TORCH, map(Fixtures.settings(torch = true)).flashMode)
        assertEquals(M.FLASH_MODE_OFF, map(Fixtures.settings(torch = true), limited).flashMode)
    }

    // [CAM-020] [CAM-021]
    @Test
    fun `focus modes map to AF modes, manual focus distance is clamped to the lens range`() {
        assertEquals(M.CONTROL_AF_MODE_CONTINUOUS_PICTURE, map(Fixtures.settings()).afMode)
        assertEquals(M.CONTROL_AF_MODE_CONTINUOUS_VIDEO, map(Fixtures.settings(), video = true).afMode)
        assertEquals(M.CONTROL_AF_MODE_AUTO, map(Fixtures.settings(focus = FocusModeMessage.AUTO)).afMode)
        val manual = map(Fixtures.settings(focus = FocusModeMessage.MANUAL, focusDistance = 4.0))
        assertEquals(M.CONTROL_AF_MODE_OFF, manual.afMode)
        assertEquals(4.0f, manual.focusDistance)
        assertEquals(10.0f, map(Fixtures.settings(focus = FocusModeMessage.MANUAL, focusDistance = 99.0)).focusDistance)
        assertEquals(0.0f, map(Fixtures.settings(focus = FocusModeMessage.MANUAL, focusDistance = -3.0)).focusDistance)
        assertEquals(0.0f, map(Fixtures.settings(focus = FocusModeMessage.MANUAL)).focusDistance)
    }

    @Test
    fun `an unsupported focus mode falls back to the best available one`() {
        // fixed-focus device: manual and auto are not available, AF off is all it has
        val p = map(Fixtures.settings(focus = FocusModeMessage.MANUAL, focusDistance = 2.0), limited)
        assertEquals(M.CONTROL_AF_MODE_OFF, p.afMode)
        assertNull(p.focusDistance)
        assertEquals(M.CONTROL_AF_MODE_AUTO, map(Fixtures.settings(), full.copy(afModes = setOf(M.CONTROL_AF_MODE_AUTO))).afMode)
        assertEquals(M.CONTROL_AF_MODE_CONTINUOUS_PICTURE, map(Fixtures.settings(), full.copy(afModes = setOf(M.CONTROL_AF_MODE_CONTINUOUS_PICTURE)), video = true).afMode)
    }

    // [CAM-030] [CAM-031]
    @Test
    fun `white balance presets map to AWB modes and Kelvin uses colour gains with AWB off`() {
        assertEquals(M.CONTROL_AWB_MODE_AUTO, map(Fixtures.settings()).awbMode)
        assertEquals(M.CONTROL_AWB_MODE_DAYLIGHT, map(Fixtures.settings(wb = WbPresetMessage.DAYLIGHT)).awbMode)
        assertEquals(M.CONTROL_AWB_MODE_INCANDESCENT, map(Fixtures.settings(wb = WbPresetMessage.TUNGSTEN)).awbMode)
        // a preset the device lacks stays on auto
        assertEquals(M.CONTROL_AWB_MODE_AUTO, map(Fixtures.settings(wb = WbPresetMessage.SHADE), limited).awbMode)
        val k = map(Fixtures.settings(kelvin = 3200, wb = WbPresetMessage.DAYLIGHT))
        assertEquals(M.CONTROL_AWB_MODE_OFF, k.awbMode)
        val gains = assertNotNull(k.colorGains)
        assertEquals(4, gains.size)
        // warm light (3200 K) is corrected by boosting blue relative to red
        assertTrue(gains[3] > gains[0])
        assertNull(map(Fixtures.settings(kelvin = 3200), limited).colorGains)
        assertEquals(M.CONTROL_AWB_MODE_AUTO, map(Fixtures.settings(kelvin = 3200), limited).awbMode)
    }

    @Test
    fun `every preset has a distinct AWB mode`() {
        val modes = WbPresetMessage.values().map { SettingsMapper.awbModeFor(it) }
        assertEquals(modes.size, modes.toSet().size)
    }

    // [CAM-008]
    @Test
    fun `zoom is clamped to the reported range`() {
        assertEquals(2.5f, map(Fixtures.settings(zoom = 2.5)).zoomRatio)
        assertEquals(8f, map(Fixtures.settings(zoom = 50.0)).zoomRatio)
        assertEquals(1f, map(Fixtures.settings(zoom = 0.1)).zoomRatio)
        assertEquals(4f, map(Fixtures.settings(zoom = 9.0), limited).zoomRatio)
    }

    // [VID-004]
    @Test
    fun `stabilization maps to the lens and video keys only when supported`() {
        val optical = map(Fixtures.settings(stabilization = StabilizationModeMessage.OPTICAL))
        assertEquals(M.LENS_OPTICAL_STABILIZATION_MODE_ON, optical.opticalStabilization)
        val standard = map(Fixtures.settings(stabilization = StabilizationModeMessage.STANDARD))
        assertEquals(M.CONTROL_VIDEO_STABILIZATION_MODE_ON, standard.videoStabilization)
        val off = map(Fixtures.settings(stabilization = StabilizationModeMessage.OFF))
        assertEquals(M.LENS_OPTICAL_STABILIZATION_MODE_OFF, off.opticalStabilization)
        assertEquals(M.CONTROL_VIDEO_STABILIZATION_MODE_OFF, off.videoStabilization)
        assertNull(map(Fixtures.settings()).opticalStabilization)
        assertNull(map(Fixtures.settings(stabilization = StabilizationModeMessage.OPTICAL), limited).opticalStabilization)
        assertNull(map(Fixtures.settings(stabilization = StabilizationModeMessage.STANDARD), limited).videoStabilization)
    }

    @Test
    fun `the request records what was asked so mismatches can be detected later`() {
        val p = map(Fixtures.settings(iso = 400, exposureNs = 8_000_000, focus = FocusModeMessage.MANUAL, focusDistance = 2.0, wb = WbPresetMessage.CLOUDY, kelvin = 5000, afLock = true))
        assertEquals(400, p.requestedIso)
        assertEquals(8_000_000L, p.requestedExposureNs)
        assertEquals(2.0f, p.requestedFocusDiopters)
        assertEquals(5000, p.requestedKelvin)
        assertEquals(WbPresetMessage.CLOUDY, p.requestedWbPreset)
        assertEquals(FocusModeMessage.MANUAL, p.requestedFocusMode)
        assertTrue(p.afLockRequested)
        assertNull(map(Fixtures.settings()).requestedFocusDiopters)
    }

    // ---- Kelvin ----

    @Test
    fun `Kelvin gains are at least 1, with the smallest exactly 1, and warm light boosts blue`() {
        for (k in listOf(2000, 2700, 3200, 4500, 5600, 6500, 8000, 10000)) {
            val g = KelvinGains.gainsFor(k)
            assertEquals(4, g.size)
            assertTrue(g.all { it >= 0.999f }, "gains at $k K: $g")
            assertEquals(1.0f, g.min(), 1e-4f)
            assertEquals(g[1], g[2])
        }
        val warm = KelvinGains.gainsFor(2700)
        val cool = KelvinGains.gainsFor(9000)
        assertTrue(warm[3] / warm[0] > 1.5f)
        assertTrue(cool[0] > cool[3])
    }

    @Test
    fun `estimating Kelvin from the gains recovers the temperature within a few hundred Kelvin`() {
        for (k in listOf(2500, 3200, 4000, 5000, 6500, 8000)) {
            val estimate = assertNotNull(KelvinGains.estimateKelvin(KelvinGains.gainsFor(k)))
            assertTrue(kotlin.math.abs(estimate - k) <= 250, "$k K estimated as $estimate")
        }
        assertNull(KelvinGains.estimateKelvin(listOf(1f, 1f)))
        assertNull(KelvinGains.estimateKelvin(listOf(0f, 1f, 1f, 1f)))
    }

    @Test
    fun `the light colour curve covers both branches of the approximation`() {
        val cold = KelvinGains.lightRgb(1500)
        assertTrue(cold.first >= cold.third)
        val daylight = KelvinGains.lightRgb(6600)
        assertEquals(255.0, daylight.third, 1e-9)
        val blue = KelvinGains.lightRgb(10000)
        assertTrue(blue.third >= blue.first)
        assertEquals(1.0, KelvinGains.lightRgb(1000).third, 1e-9) // t <= 19: clamped to the minimum
    }
}
