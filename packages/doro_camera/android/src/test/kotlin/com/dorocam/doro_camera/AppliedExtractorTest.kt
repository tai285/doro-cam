package com.dorocam.doro_camera

import android.hardware.camera2.CameraMetadata as M
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class AppliedExtractorTest {
    private val full = Fixtures.full()

    private fun request(s: ResolvedCaptureSettingsMessage) = SettingsMapper.map(s, full)
    private fun honoured(p: RequestParams) = ResultData(
        sensitivity = p.sensitivity ?: 123,
        exposureTimeNs = p.exposureTimeNs ?: 9_000_000,
        aeCompensationIndex = p.aeCompensationIndex,
        aperture = 1.8f,
        focalLength = 4.2f,
        focusDistance = p.focusDistance ?: 0.5f,
        afMode = p.afMode,
        awbMode = p.awbMode,
        colorGains = p.colorGains,
        zoomRatio = p.zoomRatio,
        aeLock = p.aeLock,
        aeMode = p.aeMode,
    )

    // [CAM-050]
    @Test
    fun `applied values are the ones the result reports, not the request`() {
        val r = ResultData(sensitivity = 640, exposureTimeNs = 12_345_000, aeCompensationIndex = 3, aperture = 1.8f, focalLength = 4.2f, zoomRatio = 1.0f, aeMode = M.CONTROL_AE_MODE_ON)
        val a = AppliedExtractor.extract(request(Fixtures.settings(iso = 100, exposureNs = 1_000_000)), r, full)
        assertEquals(640L, a.iso)
        assertEquals(12_345_000L, a.exposureTimeNs)
        assertEquals(1.0, a.exposureBiasEv!!, 1e-9)
        assertEquals(1.8, a.aperture!!, 1e-6)
        assertEquals(4.2, a.focalLengthMm!!, 1e-6)
    }

    // [CAM-050]
    @Test
    fun `a device that honours manual exposure reports no mismatches`() {
        val p = request(Fixtures.settings(iso = 400, exposureNs = 8_000_000))
        assertEquals(emptyList(), AppliedExtractor.extract(p, honoured(p), full).mismatches)
    }

    // docs/specs/camera.md acceptance: a device that ignores requests is detected
    @Test
    fun `ignored manual ISO and shutter are reported as mismatches`() {
        val p = request(Fixtures.settings(iso = 400, exposureNs = 8_000_000))
        val ignored = honoured(p).copy(sensitivity = 100, exposureTimeNs = 30_000_000)
        assertEquals(listOf("iso", "exposureTime"), AppliedExtractor.mismatches(p, ignored, full))
        assertEquals(listOf("iso", "exposureTime"), AppliedExtractor.mismatches(p, ResultData(), full).filter { it != "zoom" })
    }

    @Test
    fun `hardware rounding within tolerance is not a mismatch`() {
        val p = request(Fixtures.settings(iso = 400, exposureNs = 8_000_000))
        val rounded = honoured(p).copy(sensitivity = 405, exposureTimeNs = 8_400_000)
        assertEquals(emptyList(), AppliedExtractor.mismatches(p, rounded, full))
    }

    @Test
    fun `exposure bias mismatch is reported in automatic exposure only`() {
        val p = request(Fixtures.settings(bias = 1.0))
        assertEquals(listOf("exposureBias"), AppliedExtractor.mismatches(p, honoured(p).copy(aeCompensationIndex = 0), full))
        assertEquals(emptyList(), AppliedExtractor.mismatches(p, honoured(p), full))
        assertEquals(listOf("exposureBias"), AppliedExtractor.mismatches(p, honoured(p).copy(aeCompensationIndex = null), full))
    }

    @Test
    fun `AE and AF lock mismatches`() {
        val p = request(Fixtures.settings(aeLock = true, afLock = true))
        val r = honoured(p).copy(aeLock = false, afState = null)
        assertEquals(listOf("aeLock", "afLock"), AppliedExtractor.mismatches(p, r, full))
        val locked = honoured(p).copy(aeLock = true, afState = M.CONTROL_AF_STATE_FOCUSED_LOCKED)
        assertEquals(emptyList(), AppliedExtractor.mismatches(p, locked, full))
        assertTrue(AppliedExtractor.extract(p, locked, full).afLocked)
        val notFocused = honoured(p).copy(aeLock = true, afState = M.CONTROL_AF_STATE_NOT_FOCUSED_LOCKED)
        assertTrue(AppliedExtractor.extract(p, notFocused, full).afLocked)
    }

    @Test
    fun `manual focus mismatch when the lens did not go where asked`() {
        val p = request(Fixtures.settings(focus = FocusModeMessage.MANUAL, focusDistance = 4.0))
        assertEquals(emptyList(), AppliedExtractor.mismatches(p, honoured(p), full))
        assertEquals(listOf("focusDistance"), AppliedExtractor.mismatches(p, honoured(p).copy(focusDistance = 1.0f), full))
        assertEquals(listOf("focusDistance"), AppliedExtractor.mismatches(p, honoured(p).copy(afMode = M.CONTROL_AF_MODE_AUTO), full))
        assertEquals(listOf("focusDistance"), AppliedExtractor.mismatches(p, honoured(p).copy(focusDistance = null), full))
        assertTrue(AppliedExtractor.extract(p, honoured(p), full).afLocked)
    }

    @Test
    fun `Kelvin and preset white balance mismatches`() {
        val k = request(Fixtures.settings(kelvin = 3200))
        assertEquals(emptyList(), AppliedExtractor.mismatches(k, honoured(k), full))
        assertEquals(listOf("kelvin"), AppliedExtractor.mismatches(k, honoured(k).copy(awbMode = M.CONTROL_AWB_MODE_AUTO), full))
        assertEquals(listOf("kelvin"), AppliedExtractor.mismatches(k, honoured(k).copy(colorGains = null), full))
        assertEquals(listOf("kelvin"), AppliedExtractor.mismatches(k, honoured(k).copy(colorGains = listOf(1f, 1f, 1f, 1f)), full))
        val preset = request(Fixtures.settings(wb = WbPresetMessage.DAYLIGHT))
        assertEquals(emptyList(), AppliedExtractor.mismatches(preset, honoured(preset), full))
        assertEquals(listOf("whiteBalance"), AppliedExtractor.mismatches(preset, honoured(preset).copy(awbMode = M.CONTROL_AWB_MODE_AUTO), full))
    }

    @Test
    fun `an estimated Kelvin appears only for manual gains and is labelled as an estimate by name`() {
        val k = request(Fixtures.settings(kelvin = 5000))
        val applied = AppliedExtractor.extract(k, honoured(k), full)
        assertEquals("manual", applied.whiteBalanceMode)
        assertNotNull(applied.whiteBalanceGains)
        assertTrue(kotlin.math.abs(applied.estimatedKelvin!! - 5000) <= 250)
        val auto = AppliedExtractor.extract(request(Fixtures.settings()), honoured(request(Fixtures.settings())), full)
        assertNull(auto.estimatedKelvin)
        assertEquals("auto", auto.whiteBalanceMode)
    }

    // [CAM-008]
    @Test
    fun `zoom comes from the zoom ratio, or from the crop region on older devices, or defaults to 1`() {
        assertEquals(2.0, AppliedExtractor.zoomRatio(ResultData(zoomRatio = 2.0f), full), 1e-9)
        assertEquals(2.0, AppliedExtractor.zoomRatio(ResultData(cropWidth = 2000), full), 1e-9)
        assertEquals(1.0, AppliedExtractor.zoomRatio(ResultData(), full), 1e-9)
        assertEquals(1.0, AppliedExtractor.zoomRatio(ResultData(cropWidth = 0), full), 1e-9)
        val p = request(Fixtures.settings(zoom = 3.0))
        assertEquals(listOf("zoom"), AppliedExtractor.mismatches(p, honoured(p).copy(zoomRatio = 1.0f), full))
    }

    @Test
    fun `mappings of AF, AWB, stabilization and flash states`() {
        assertEquals(FocusModeMessage.MANUAL, AppliedExtractor.focusMode(M.CONTROL_AF_MODE_OFF))
        assertEquals(FocusModeMessage.AUTO, AppliedExtractor.focusMode(M.CONTROL_AF_MODE_AUTO))
        assertEquals(FocusModeMessage.AUTO, AppliedExtractor.focusMode(M.CONTROL_AF_MODE_MACRO))
        assertEquals(FocusModeMessage.CONTINUOUS, AppliedExtractor.focusMode(M.CONTROL_AF_MODE_CONTINUOUS_VIDEO))
        assertNull(AppliedExtractor.focusMode(null))
        assertNull(AppliedExtractor.focusMode(99))
        val names = listOf(
            M.CONTROL_AWB_MODE_OFF to "manual", M.CONTROL_AWB_MODE_AUTO to "auto", M.CONTROL_AWB_MODE_DAYLIGHT to "daylight",
            M.CONTROL_AWB_MODE_CLOUDY_DAYLIGHT to "cloudy", M.CONTROL_AWB_MODE_SHADE to "shade", M.CONTROL_AWB_MODE_INCANDESCENT to "tungsten",
            M.CONTROL_AWB_MODE_FLUORESCENT to "fluorescent", M.CONTROL_AWB_MODE_WARM_FLUORESCENT to "other",
        )
        names.forEach { (mode, name) -> assertEquals(name, AppliedExtractor.whiteBalanceMode(mode)) }
        assertNull(AppliedExtractor.whiteBalanceMode(null))
        assertEquals(StabilizationModeMessage.OPTICAL, AppliedExtractor.stabilization(ResultData(opticalStabilization = M.LENS_OPTICAL_STABILIZATION_MODE_ON)))
        assertEquals(StabilizationModeMessage.STANDARD, AppliedExtractor.stabilization(ResultData(videoStabilization = M.CONTROL_VIDEO_STABILIZATION_MODE_ON)))
        assertEquals(StabilizationModeMessage.OFF, AppliedExtractor.stabilization(ResultData(opticalStabilization = M.LENS_OPTICAL_STABILIZATION_MODE_OFF)))
        assertNull(AppliedExtractor.stabilization(ResultData()))
        assertEquals(FlashModeMessage.AUTO, AppliedExtractor.flash(ResultData(aeMode = M.CONTROL_AE_MODE_ON_AUTO_FLASH)))
        assertEquals(FlashModeMessage.ON, AppliedExtractor.flash(ResultData(aeMode = M.CONTROL_AE_MODE_ON_ALWAYS_FLASH)))
        assertEquals(FlashModeMessage.OFF, AppliedExtractor.flash(ResultData(aeMode = M.CONTROL_AE_MODE_ON)))
        assertNull(AppliedExtractor.flash(ResultData()))
        assertTrue(AppliedExtractor.extract(null, ResultData(flashState = M.FLASH_STATE_FIRED), full).flashFired == true)
        assertFalse(AppliedExtractor.extract(null, ResultData(flashState = M.FLASH_STATE_READY), full).flashFired == true)
        assertNull(AppliedExtractor.extract(null, ResultData(), full).flashFired)
        assertEquals(emptyList(), AppliedExtractor.mismatches(null, ResultData(), full))
    }
}
