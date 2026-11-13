package com.dorocam.doro_camera

import android.hardware.camera2.CameraMetadata as M
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class CapabilityProbeTest {
    private val full = Fixtures.full()
    private val limited = Fixtures.limited()

    // [CAM-004]
    @Test
    fun `a full device exposes manual ISO and shutter only because MANUAL_SENSOR and valid ranges exist`() {
        assertEquals(IntRangeMessage(50, 3200), CapabilityProbe.isoRange(full))
        assertEquals(IntRangeMessage(100_000, 1_000_000_000), CapabilityProbe.exposureRange(full))
    }

    // [CAM-005]
    @Test
    fun `without MANUAL_SENSOR the ranges are hidden even when the HAL reports numbers`() {
        assertNull(CapabilityProbe.isoRange(limited))
        assertNull(CapabilityProbe.exposureRange(limited))
    }

    @Test
    fun `invalid ranges are never exposed`() {
        assertNull(CapabilityProbe.isoRange(full.copy(sensitivityRange = 100 to 100)))
        assertNull(CapabilityProbe.isoRange(full.copy(sensitivityRange = null)))
        assertNull(CapabilityProbe.isoRange(full.copy(sensitivityRange = 0 to 100)))
        assertNull(CapabilityProbe.exposureRange(full.copy(exposureTimeRangeNs = 5L to 5L)))
        assertNull(CapabilityProbe.exposureRange(full.copy(exposureTimeRangeNs = null)))
    }

    // [CAM-012]
    @Test
    fun `exposure bias is expressed in EV and absent when the step or range is zero`() {
        val bias = assertNotNull(CapabilityProbe.exposureBias(full))
        assertEquals(-4.0, bias.range.min, 1e-9)
        assertEquals(4.0, bias.range.max, 1e-9)
        assertEquals(1.0 / 3.0, bias.step, 1e-9)
        assertNull(CapabilityProbe.exposureBias(full.copy(aeCompensationRange = 0 to 0)))
        assertNull(CapabilityProbe.exposureBias(full.copy(aeCompensationStep = 0.0)))
        assertNull(CapabilityProbe.exposureBias(full.copy(aeCompensationRange = null)))
    }

    // [CAM-021]
    @Test
    fun `manual focus needs a positive minimum focus distance and reports the calibration`() {
        val manual = assertNotNull(CapabilityProbe.manualFocus(full))
        assertEquals(10.0, manual.minFocusDistanceDiopters, 1e-9)
        assertEquals(FocusCalibrationMessage.APPROXIMATE, manual.calibration)
        assertNull(CapabilityProbe.manualFocus(limited))
        assertNull(CapabilityProbe.manualFocus(full.copy(minimumFocusDistanceDiopters = null)))
        assertEquals(FocusCalibrationMessage.CALIBRATED, CapabilityProbe.manualFocus(full.copy(focusCalibration = M.LENS_INFO_FOCUS_DISTANCE_CALIBRATION_CALIBRATED))?.calibration)
        assertEquals(FocusCalibrationMessage.UNCALIBRATED, CapabilityProbe.manualFocus(full.copy(focusCalibration = null))?.calibration)
    }

    // [CAM-020]
    @Test
    fun `focus modes follow the AF modes and regions`() {
        val f = CapabilityProbe.focus(full)
        assertTrue(f.auto && f.continuous && f.tapToFocus)
        val none = CapabilityProbe.focus(limited)
        assertFalse(none.auto || none.continuous || none.tapToFocus)
        assertFalse(CapabilityProbe.focus(full.copy(maxAfRegions = 0)).tapToFocus)
    }

    // [CAM-030] [CAM-031]
    @Test
    fun `white balance lists the available presets and Kelvin only with manual post processing`() {
        val wb = CapabilityProbe.whiteBalance(full)
        assertEquals(
            listOf(WbPresetMessage.AUTO, WbPresetMessage.DAYLIGHT, WbPresetMessage.CLOUDY, WbPresetMessage.SHADE, WbPresetMessage.TUNGSTEN, WbPresetMessage.FLUORESCENT),
            wb.presets,
        )
        assertEquals(IntRangeMessage(2000, 10000), wb.kelvin)
        val ltd = CapabilityProbe.whiteBalance(limited)
        assertEquals(listOf(WbPresetMessage.AUTO), ltd.presets)
        assertNull(ltd.kelvin)
        assertNull(CapabilityProbe.whiteBalance(full.copy(awbModes = full.awbModes - M.CONTROL_AWB_MODE_OFF)).kelvin)
    }

    // [CAM-008]
    @Test
    fun `zoom uses the zoom ratio range when present, else digital zoom`() {
        assertEquals(ZoomCapabilitiesMessage(1.0, 8.0, listOf(1.0)), CapabilityProbe.zoom(full))
        assertEquals(ZoomCapabilitiesMessage(1.0, 4.0, listOf(1.0)), CapabilityProbe.zoom(limited))
        assertEquals(1.0, CapabilityProbe.zoom(limited.copy(maxDigitalZoom = 0.5f)).max, 1e-9)
    }

    // [CAM-046]
    @Test
    fun `photo formats come from the real stream configuration`() {
        assertEquals(listOf(PhotoFormatMessage.HEIF, PhotoFormatMessage.JPEG, PhotoFormatMessage.DNG), CapabilityProbe.photoFormats(full))
        assertEquals(listOf(PhotoFormatMessage.JPEG), CapabilityProbe.photoFormats(limited))
        // RAW sizes without the RAW capability are not offered.
        assertFalse(PhotoFormatMessage.DNG in CapabilityProbe.photoFormats(full.copy(capabilities = full.capabilities - M.REQUEST_AVAILABLE_CAPABILITIES_RAW)))
    }

    // [VID-004]
    @Test
    fun `stabilization modes are listed only when the device supports them`() {
        val s = CapabilityProbe.stabilization(full)
        assertEquals(listOf(StabilizationModeMessage.OFF, StabilizationModeMessage.OPTICAL), s.photo)
        assertEquals(listOf(StabilizationModeMessage.OFF, StabilizationModeMessage.STANDARD, StabilizationModeMessage.OPTICAL), s.video)
        val none = CapabilityProbe.stabilization(limited)
        assertEquals(listOf(StabilizationModeMessage.OFF), none.photo)
        assertEquals(listOf(StabilizationModeMessage.OFF), none.video)
    }

    // [VID-002]
    @Test
    fun `video sizes list only the frame rates the sensor can deliver`() {
        val video = CapabilityProbe.video(full, Fixtures.media)
        val byWidth = video.options.associate { it.size.width to it.fps }
        assertEquals(listOf(24L, 30L), byWidth[3840]) // 4K min frame duration 33 ms: no 60
        assertEquals(listOf(24L, 30L, 60L), byWidth[1920])
        assertTrue(video.audio)
        assertTrue(CapabilityProbe.video(full, MediaSupport(false, false, false)).options.isEmpty())
        assertFalse(CapabilityProbe.video(full, MediaSupport(true, true, false)).audio)
    }

    // [MOT-002]
    @Test
    fun `LIVE needs an encoder and a size up to 1080p, and reports audio only with a microphone`() {
        val live = CapabilityProbe.live(full, Fixtures.media)
        assertTrue(live.supported && live.audio)
        assertEquals(3000, live.maxPreBufferMs)
        assertEquals(SizeMessage(1920, 1080), CapabilityProbe.defaultMotionSize(full))
        assertFalse(CapabilityProbe.live(full, MediaSupport(false, false, false)).supported)
        assertEquals(0, CapabilityProbe.live(full, MediaSupport(false, false, false)).maxPreBufferMs)
        assertFalse(CapabilityProbe.live(full, MediaSupport(true, true, false)).audio)
        assertFalse(CapabilityProbe.live(full.copy(surfaceSizes = listOf(SizeMessage(4000, 3000))), Fixtures.media).supported)
    }

    @Test
    fun `hardware level names`() {
        assertEquals("LEGACY", CapabilityProbe.hardwareLevelName(M.INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY))
        assertEquals("LIMITED", CapabilityProbe.hardwareLevelName(M.INFO_SUPPORTED_HARDWARE_LEVEL_LIMITED))
        assertEquals("FULL", CapabilityProbe.hardwareLevelName(M.INFO_SUPPORTED_HARDWARE_LEVEL_FULL))
        assertEquals("LEVEL_3", CapabilityProbe.hardwareLevelName(M.INFO_SUPPORTED_HARDWARE_LEVEL_3))
        assertEquals("EXTERNAL", CapabilityProbe.hardwareLevelName(M.INFO_SUPPORTED_HARDWARE_LEVEL_EXTERNAL))
        assertEquals("UNKNOWN", CapabilityProbe.hardwareLevelName(null))
    }

    // [CAM-004]
    @Test
    fun `the assembled capabilities carry flash, torch, apertures and sorted photo sizes`() {
        val caps = CapabilityProbe.capabilities(full, Fixtures.media)
        assertEquals("0", caps.cameraId)
        assertEquals(listOf(1.8), caps.apertures.map { Math.round(it * 10) / 10.0 })
        assertEquals(listOf(FlashModeMessage.OFF, FlashModeMessage.AUTO, FlashModeMessage.ON), caps.flash)
        assertTrue(caps.torch && caps.hdr)
        assertEquals(SizeMessage(4000, 3000), caps.photoSizes.first())
        assertEquals("FULL", caps.hardwareLevel)
        val ltd = CapabilityProbe.capabilities(limited, Fixtures.media)
        assertTrue(ltd.flash.isEmpty() && !ltd.torch && !ltd.hdr)
        assertNull(ltd.iso)
    }

    // [CAM-007]
    @Test
    fun `35 mm equivalent focal length from the sensor size`() {
        // 6.4 x 4.8 mm sensor, 4.2 mm lens: 4.2 * 43.27 / 8.0 = 22.7
        assertEquals(22.7, CapabilityProbe.focalLength35mmEq(4.2f, 6.4f, 4.8f))
        assertNull(CapabilityProbe.focalLength35mmEq(null, 6.4f, 4.8f))
        assertNull(CapabilityProbe.focalLength35mmEq(4.2f, null, 4.8f))
        assertNull(CapabilityProbe.focalLength35mmEq(0f, 6.4f, 4.8f))
        assertNull(CapabilityProbe.focalLength35mmEq(4.2f, 0f, 0f))
    }

    // [CAM-006]
    @Test
    fun `lens kind is classified from the equivalent focal length and facing`() {
        assertEquals(LensKindMessage.FRONT, CapabilityProbe.lensKind(M.LENS_FACING_FRONT, 26.0))
        assertEquals(LensKindMessage.OTHER, CapabilityProbe.lensKind(M.LENS_FACING_BACK, null))
        assertEquals(LensKindMessage.ULTRA_WIDE, CapabilityProbe.lensKind(M.LENS_FACING_BACK, 14.0))
        assertEquals(LensKindMessage.WIDE, CapabilityProbe.lensKind(M.LENS_FACING_BACK, 26.0))
        assertEquals(LensKindMessage.OTHER, CapabilityProbe.lensKind(M.LENS_FACING_BACK, 50.0))
        assertEquals(LensKindMessage.TELE, CapabilityProbe.lensKind(M.LENS_FACING_BACK, 77.0))
    }

    @Test
    fun `descriptors flag logical cameras, facing, source and a readable label`() {
        val d = CapabilityProbe.descriptor(full.copy(capabilities = full.capabilities + M.REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA, physicalIds = listOf("2", "3")))
        assertTrue(d.isLogical)
        assertEquals(listOf("2", "3"), d.physicalIds)
        assertEquals(CameraFacingMessage.BACK, d.facing)
        assertEquals(CameraSourceMessage.HARDWARE, d.source)
        assertEquals(90, d.sensorOrientation)
        assertEquals("Back camera", d.label)
        assertEquals("Front camera", CapabilityProbe.descriptor(limited).label)
        assertEquals(CameraFacingMessage.EXTERNAL, CapabilityProbe.facing(M.LENS_FACING_EXTERNAL))
        assertEquals("External camera", CapabilityProbe.descriptor(full.copy(lensFacing = M.LENS_FACING_EXTERNAL)).label)
        assertTrue(CapabilityProbe.descriptor(full.copy(focalLengths = listOf(2.0f))).label.endsWith("(ultra-wide)"))
        assertTrue(CapabilityProbe.descriptor(full.copy(focalLengths = listOf(12.0f))).label.endsWith("(telephoto)"))
        assertEquals("Custom", CapabilityProbe.descriptor(full, "Custom").label)
    }
}
