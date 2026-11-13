package com.dorocam.doro_camera

import android.graphics.BitmapFactory
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.rule.GrantPermissionRule
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The synthetic test camera (ADR-0013) end to end: deterministic frames and a known flash/beep schedule make
 * exposure, motion timing and A/V sync verifiable without hardware. It declares only the controls it simulates.
 */
@RunWith(AndroidJUnit4::class)
class SyntheticCameraInstrumentedTest {
    @get:Rule
    val permissions: GrantPermissionRule = GrantPermissionRule.grant(android.Manifest.permission.CAMERA, android.Manifest.permission.RECORD_AUDIO)

    private val rig = Rig()
    private val wide get() = SyntheticBackend.WIDE

    @Before
    fun reset() {
        SyntheticControl.ignoreManualRequests = false
    }

    @After
    fun tearDown() = runBlocking {
        SyntheticControl.ignoreManualRequests = false
        rig.service.closeAll()
        rig.cleanup()
    }

    private suspend fun open(id: String = wide, live: Boolean = false) =
        rig.service.openSession(SessionConfigMessage(cameraId = id, photoFormat = PhotoFormatMessage.JPEG, live = live, audio = true))

    private fun settings(iso: Long? = null, exposureNs: Long? = null, bias: Double? = null, kelvin: Long? = null, zoom: Double = 1.0) =
        ResolvedCaptureSettingsMessage(aeLock = false, focusMode = FocusModeMessage.CONTINUOUS, afLock = false, zoomRatio = zoom, flash = FlashModeMessage.OFF, torch = false, iso = iso, exposureTimeNs = exposureNs, exposureBiasEv = bias, kelvin = kelvin)

    // ADR-0013: it is listed with source synthetic, and the real HAL cameras are still there too
    @Test
    fun isListedAsSyntheticAlongsideTheRealCameras() {
        assertTrue(SyntheticCameraBuild.isCompiledIn)
        val synthetic = rig.syntheticCameras()
        assertEquals(listOf("synthetic:wide", "synthetic:tele"), synthetic.map { it.id })
        assertTrue(synthetic.all { it.source == CameraSourceMessage.SYNTHETIC })
        assertEquals(LensKindMessage.WIDE, synthetic[0].lensKind)
        assertEquals(LensKindMessage.TELE, synthetic[1].lensKind)
    }

    // [CAM-005] it declares only what it really simulates
    @Test
    fun declaresOnlyTheControlsItSimulates() {
        val caps = rig.service.capabilities(wide)
        assertNotNull(caps.iso)
        assertNotNull(caps.exposureTimeNs)
        assertNotNull(caps.exposureBias)
        assertNotNull(caps.whiteBalance.kelvin)
        assertFalse(caps.focus.auto || caps.focus.continuous || caps.focus.tapToFocus)
        assertEquals(null, caps.focus.manual)
        assertTrue(caps.flash.isEmpty() && !caps.torch)
        assertEquals(listOf(1.8), caps.apertures)
        assertEquals("SYNTHETIC", caps.hardwareLevel)
    }

    @Test
    fun refusesAFocusRequestBecauseItHasNoFocus() = runBlocking {
        val info = open()
        val error = runCatching { rig.service.focusAt(info.sessionId, 0.5, 0.5) }.exceptionOrNull()
        assertTrue(error is CameraException && error.code == "unsupported_configuration")
    }

    // [CAM-001]
    @Test
    fun deliversPreviewFramesAndTheSessionIsMarkedSynthetic() = runBlocking {
        val info = open()
        assertEquals(CameraSourceMessage.SYNTHETIC, info.source)
        assertTrue(rig.textures.single().waitForFrames(10))
    }

    // [CAM-010] [CAM-011] [CAM-012] [CAM-050]: the effect of every simulated control is confirmed in the result
    @Test
    fun everySimulatedControlHasItsEffectConfirmedInTheCaptureResult() = runBlocking {
        val info = open()
        val applied = rig.service.applySettings(info.sessionId, settings(iso = 800, exposureNs = 4_000_000, zoom = 2.0))
        assertEquals(800L, applied.iso)
        assertEquals(4_000_000L, applied.exposureTimeNs)
        assertEquals(2.0, applied.zoomRatio, 1e-9)
        assertTrue(applied.mismatches.isEmpty())
        val result = rig.service.capture(info.sessionId, rig.request("fx"))
        assertEquals(800L, result.applied.iso)
        assertEquals(4_000_000L, result.applied.exposureTimeNs)
        assertEquals(2.0, result.applied.zoomRatio, 1e-9)
        assertEquals(CameraSourceMessage.SYNTHETIC, result.source)

        val kelvin = rig.service.applySettings(info.sessionId, settings(kelvin = 3200))
        assertEquals("manual", kelvin.whiteBalanceMode)
        assertEquals(3200L, kelvin.estimatedKelvin)
        val bias = rig.service.applySettings(info.sessionId, settings(bias = 1.0))
        assertEquals(1.0, bias.exposureBiasEv!!, 1e-9)
        // out-of-range values are clamped by the device and the applied value says so
        val clamped = rig.service.applySettings(info.sessionId, settings(iso = 1_000_000))
        assertEquals(3200L, clamped.iso)
    }

    // The picture really changes with exposure: more ISO x shutter is brighter
    @Test
    fun exposureChangesTheActualPixels() = runBlocking {
        val info = open()
        rig.service.applySettings(info.sessionId, settings(iso = 50, exposureNs = 1_000_000))
        val dark = meanLuma(rig.service.capture(info.sessionId, rig.request("dark")).originalPath)
        rig.service.applySettings(info.sessionId, settings())
        val normal = meanLuma(rig.service.capture(info.sessionId, rig.request("normal")).originalPath)
        rig.service.applySettings(info.sessionId, settings(iso = 3200, exposureNs = 100_000_000))
        val bright = meanLuma(rig.service.capture(info.sessionId, rig.request("bright")).originalPath)
        assertTrue("dark $dark < normal $normal", dark < normal - 5)
        assertTrue("normal $normal < bright $bright", normal < bright - 5)
    }

    // docs/specs/camera.md: a device that ignores requests is detected (the persistent-mismatch path)
    @Test
    fun aSourceThatIgnoresRequestsReportsMismatches() = runBlocking {
        val info = open()
        SyntheticControl.ignoreManualRequests = true
        val applied = rig.service.applySettings(info.sessionId, settings(iso = 800, exposureNs = 4_000_000))
        assertEquals(listOf("iso", "exposureTime"), applied.mismatches)
        assertEquals(100L, applied.iso) // what it really used
        val result = rig.service.capture(info.sessionId, rig.request("ignored"))
        assertEquals(listOf("iso", "exposureTime"), result.applied.mismatches)
    }

    // [CAM-003] [PRF-003] [PRF-006]
    @Test
    fun theLookIsAppliedOnlyToTheRenditionAndTheOriginalStaysUntouched() = runBlocking {
        val info = open()
        val plain = rig.service.capture(info.sessionId, rig.request("plain"))
        val request = rig.request("looked").copy(render = RenderSpecMessage(grain = 0.0, vignette = 0.9, lut = invertLut(), lutSize = 9, aspectRatio = null))
        val looked = rig.service.capture(info.sessionId, request)
        val originalLuma = meanLuma(looked.originalPath)
        val renderedLuma = meanLuma(looked.renderedPath!!)
        assertEquals(meanLuma(plain.originalPath), originalLuma, 12.0) // original is not graded
        assertTrue("inverting LUT must change the rendition: original $originalLuma rendered $renderedLuma", kotlin.math.abs(renderedLuma - originalLuma) > 25)
        val vignettePlain = BitmapFactory.decodeFile(plain.renderedPath)
        val corner = vignettePlain.getPixel(2, 2)
        assertNotNull(corner)
    }

    private fun invertLut(): ByteArray {
        val lut = ImageMath.identityLut(9)
        for (i in lut.indices) lut[i] = (255 - (lut[i].toInt() and 0xFF)).toByte()
        return lut
    }

    // [CAM-044]
    @Test
    fun aspectCropAppliesToRenditionsOnly() = runBlocking {
        val info = open()
        val result = rig.service.capture(info.sessionId, rig.request("sq", aspect = "1:1"))
        assertEquals(1600, BitmapFactory.decodeFile(result.originalPath).width)
        val rendered = BitmapFactory.decodeFile(result.renderedPath)
        assertEquals(rendered.width, rendered.height)
    }

    // [MOT-002] [MOT-003] [MOT-009]: pre-roll + post-roll, audio in the same container, A/V in sync
    @Test
    fun motionCaptureHasPreRollPostRollAudioAndVideoInSync() = runBlocking {
        val info = open(live = true)
        assertTrue("LIVE must start on the synthetic camera", info.liveActive)
        assertTrue(info.audioActive)
        Thread.sleep(3200) // fill the pre-roll window
        val result = rig.service.capture(info.sessionId, rig.request("motion", live = true))
        val motion = result.motion
        assertTrue(result.liveIncluded && motion != null)
        motion!!
        assertTrue(File(motion.path).exists())
        assertTrue(motion.hasAudio)
        assertTrue("pre-roll ${motion.preRollMs} ms must be at least the 1500 ms asked", motion.preRollMs >= 1500)
        assertTrue("pre-roll ${motion.preRollMs} ms stays bounded by the window", motion.preRollMs <= 3200)
        assertTrue("post-roll ${motion.postRollMs} ms", motion.postRollMs in 1000..2500)
        assertEquals(motion.preRollMs, motion.keyFrameTimeMs)

        val facts = ClipInspector.facts(motion.path)
        assertTrue(facts.hasVideoTrack && facts.hasAudioTrack)
        assertTrue("clip ${facts.durationMs} ms vs reported ${motion.durationMs} ms", kotlin.math.abs(facts.durationMs - motion.durationMs) <= 300)

        // A/V sync: the flash (picture) and the beep (sound) are generated at the same instants, once per second.
        val flashes = ClipInspector.flashOnsetsMs(motion.path, facts.durationMs)
        val beeps = ClipInspector.beepOnsetsMs(motion.path)
        android.util.Log.i("DoroSync", "flashes=$flashes beeps=$beeps pre=${motion.preRollMs} dur=${facts.durationMs}")
        assertTrue("need at least two flashes in the clip: $flashes", flashes.size >= 2)
        assertTrue("need at least two beeps in the clip: $beeps", beeps.size >= 2)
        // each flash must have a beep within 60 ms, and flashes are one second apart
        for (flash in flashes) {
            val closest = beeps.minByOrNull { kotlin.math.abs(it - flash) }!!
            assertTrue("flash at $flash ms vs nearest beep at $closest ms (beeps $beeps)", near(flash, closest, 60))
        }
        assertTrue("flashes one second apart: $flashes", near(flashes[1] - flashes[0], 1000, 80))
        assertTrue("first video and audio sample start together", near(facts.firstVideoPtsUs / 1000, facts.firstAudioPtsUs / 1000, 80))
    }

    // [MOT-003] without audio the motion is silent and says so
    @Test
    fun motionWithoutAudioIsSilent() = runBlocking {
        val info = rig.service.openSession(SessionConfigMessage(cameraId = wide, photoFormat = PhotoFormatMessage.JPEG, live = true, audio = false))
        assertTrue(info.liveActive)
        assertFalse(info.audioActive)
        Thread.sleep(2200)
        val motion = rig.service.capture(info.sessionId, rig.request("silent", live = true)).motion!!
        assertFalse(motion.hasAudio)
        assertFalse(ClipInspector.facts(motion.path).hasAudioTrack)
    }

    // [MOT-009] [NFR-012]: nothing is buffered while LIVE is off, and it can be turned on and off
    @Test
    fun liveCanBeToggledAndCapturesWithoutLiveHaveNoMotion() = runBlocking {
        val info = open(live = false)
        assertFalse(info.liveActive)
        val none = rig.service.capture(info.sessionId, rig.request("off", live = true))
        assertFalse(none.liveIncluded)
        assertEquals(null, none.motion)
        rig.service.setLive(info.sessionId, true)
        Thread.sleep(2800)
        val on = rig.service.capture(info.sessionId, rig.request("on", live = true))
        assertTrue(on.liveIncluded)
        rig.service.setLive(info.sessionId, false)
        Thread.sleep(800)
        assertFalse(rig.service.capture(info.sessionId, rig.request("off2", live = true)).liveIncluded)
    }

    // [NFR-012] suspending stops the encoders; resuming restarts buffering
    @Test
    fun suspendingStopsLiveBufferingAndResumingRestartsIt() = runBlocking {
        val info = open(live = true)
        Thread.sleep(2200)
        rig.service.suspendSession(info.sessionId)
        val whileSuspended = runCatching { rig.service.capture(info.sessionId, rig.request("s")) }.exceptionOrNull()
        assertTrue(whileSuspended is CameraException && whileSuspended.code == "camera_disconnected")
        rig.service.resumeSession(info.sessionId)
        Thread.sleep(2500)
        assertTrue(rig.service.capture(info.sessionId, rig.request("r", live = true)).liveIncluded)
        assertTrue(rig.events.any { it.kind == SessionEventKindMessage.RESUMED })
    }

    // [VID-001] [VID-002]
    @Test
    fun recordsVideoAtASupportedSizeWithAudioInSync() = runBlocking {
        val info = open()
        val caps = rig.service.capabilities(wide)
        val option = caps.video.options.first()
        val target = File(rig.outDir, "video.mp4")
        rig.service.startVideo(info.sessionId, VideoRequestMessage(outputPath = target.path, audio = true, size = option.size, fps = option.fps.first()))
        Thread.sleep(3500)
        val result = rig.service.stopVideo(info.sessionId)
        assertTrue(target.exists())
        assertTrue(result.hasAudio)
        val facts = ClipInspector.facts(target.path)
        assertTrue(facts.hasVideoTrack && facts.hasAudioTrack)
        assertTrue("duration ${facts.durationMs}", facts.durationMs in 3000..4500)
        val flashes = ClipInspector.flashOnsetsMs(target.path, facts.durationMs)
        val beeps = ClipInspector.beepOnsetsMs(target.path)
        assertTrue("flashes $flashes beeps $beeps", flashes.size >= 2 && beeps.size >= 2)
        // A flash or beep already underway at the first sample began before the clip and cannot be timed, so edge onsets are skipped.
        for (flash in flashes) assertTrue("flash $flash ms has no beep near it: $beeps", beeps.any { near(it, flash, 80) })
        for (beep in beeps.filter { it > 150 }) assertTrue("beep $beep ms has no flash near it: $flashes", flashes.any { near(it, beep, 80) })
        assertTrue(rig.outDir.list()!!.none { it.endsWith(AtomicFiles.TEMP_SUFFIX) })
    }

    // [VID-002] unsupported combinations are refused with a typed error
    @Test
    fun unsupportedVideoSizesAndFrameRatesAreRefused() = runBlocking {
        val info = open()
        val badSize = runCatching { rig.service.startVideo(info.sessionId, VideoRequestMessage(outputPath = File(rig.outDir, "a.mp4").path, audio = false, size = SizeMessage(333, 222))) }.exceptionOrNull()
        assertTrue(badSize is CameraException && badSize.code == "unsupported_configuration")
        val option = rig.service.capabilities(wide).video.options.first()
        val badFps = runCatching { rig.service.startVideo(info.sessionId, VideoRequestMessage(outputPath = File(rig.outDir, "b.mp4").path, audio = false, size = option.size, fps = 240)) }.exceptionOrNull()
        assertTrue(badFps is CameraException && badFps.code == "unsupported_configuration")
        val noStop = runCatching { rig.service.stopVideo(info.sessionId) }.exceptionOrNull()
        assertTrue(noStop is CameraException)
    }

    // [CAM-051] a second lens (telephoto) is a different camera id with its own honest facts
    @Test
    fun theTelephotoLensIsASeparateCamera() = runBlocking {
        val tele = rig.service.listCameras().first { it.id == SyntheticBackend.TELE }
        assertEquals(56.0, tele.focalLength35mmEq!!, 0.01)
        val info = open(SyntheticBackend.TELE)
        val result = rig.service.capture(info.sessionId, rig.request("tele"))
        assertEquals(9.0, result.applied.focalLengthMm!!, 0.01)
    }

    @Test
    fun eventsReportStateTransitionsInOrder() = runBlocking {
        val info = open()
        rig.service.capture(info.sessionId, rig.request("ev"))
        rig.service.closeSession(info.sessionId)
        val states = rig.events.filter { it.kind == SessionEventKindMessage.STATE }.mapNotNull { it.state }
        assertEquals(listOf(SessionStateMessage.PREVIEWING, SessionStateMessage.CAPTURING, SessionStateMessage.PREVIEWING, SessionStateMessage.CLOSED), states)
    }

    @Test
    fun capturingWhileRecordingIsRefusedAndLocationGoesIntoExifOnlyWhenGiven() = runBlocking {
        val info = open()
        val option = rig.service.capabilities(wide).video.options.first()
        rig.service.startVideo(info.sessionId, VideoRequestMessage(outputPath = File(rig.outDir, "r.mp4").path, audio = false, size = option.size))
        val refused = runCatching { rig.service.capture(info.sessionId, rig.request("during")) }.exceptionOrNull()
        assertTrue(refused is CameraException)
        Thread.sleep(1200) // a recording needs a moment of footage to be a valid file
        rig.service.stopVideo(info.sessionId)
        val without = rig.service.capture(info.sessionId, rig.request("nogps"))
        val withGps = rig.service.capture(info.sessionId, rig.request("gps").copy(location = LocationMessage(3.139, 101.6869)))
        assertEquals(null, androidx.exifinterface.media.ExifInterface(without.renderedPath!!).latLong)
        val fix = androidx.exifinterface.media.ExifInterface(withGps.renderedPath!!).latLong
        assertNotNull(fix)
        assertEquals(3.139, fix!![0], 0.001)
        assertEquals(101.6869, fix[1], 0.001)
    }
}
