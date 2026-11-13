package com.dorocam.doro_camera

import android.graphics.BitmapFactory
import android.util.Log
import androidx.exifinterface.media.ExifInterface
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.rule.GrantPermissionRule
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Runs the real Camera2 code paths on the Android Emulator's camera HAL (ADR-0013). Every control is only
 * exercised when the camera REPORTS the capability, exactly like the app (CAM-005); the capability dump is
 * logged under the tag DoroCapabilities so docs/specs/capability-matrix.md can record the emulator column.
 */
@RunWith(AndroidJUnit4::class)
class RealCameraInstrumentedTest {
    @get:Rule
    val permissions: GrantPermissionRule = GrantPermissionRule.grant(android.Manifest.permission.CAMERA, android.Manifest.permission.RECORD_AUDIO)

    private val rig = Rig()

    @After
    fun tearDown() = runBlocking {
        rig.service.closeAll()
        rig.cleanup()
    }

    private fun backCamera(): CameraDescriptorMessage {
        val cameras = rig.hardwareCameras()
        assumeTrue("the device has no camera", cameras.isNotEmpty())
        return cameras.firstOrNull { it.facing == CameraFacingMessage.BACK } ?: cameras.first()
    }

    private suspend fun open(id: String, live: Boolean = false, audio: Boolean = true) =
        rig.service.openSession(SessionConfigMessage(cameraId = id, photoFormat = PhotoFormatMessage.JPEG, live = live, audio = audio))

    // [CAM-004]
    @Test
    fun listsCamerasAndProbesCapabilitiesFromTheHardware() {
        val cameras = rig.hardwareCameras()
        assertTrue("expected at least one hardware camera", cameras.isNotEmpty())
        for (camera in cameras) {
            val caps = rig.service.capabilities(camera.id)
            Log.i(
                "DoroCapabilities",
                "camera=${camera.id} facing=${camera.facing} lens=${camera.lensKind} level=${caps.hardwareLevel} iso=${caps.iso?.let { "${it.min}..${it.max}" }} " +
                    "shutterNs=${caps.exposureTimeNs?.let { "${it.min}..${it.max}" }} bias=${caps.exposureBias?.let { "${it.range.min}..${it.range.max}/${it.step}" }} " +
                    "apertures=${caps.apertures} focusAuto=${caps.focus.auto} focusCont=${caps.focus.continuous} tap=${caps.focus.tapToFocus} " +
                    "manualFocus=${caps.focus.manual?.let { "${it.minFocusDistanceDiopters}/${it.calibration}" }} wb=${caps.whiteBalance.presets} kelvin=${caps.whiteBalance.kelvin?.let { "${it.min}..${it.max}" }} " +
                    "zoom=${caps.zoom.min}..${caps.zoom.max} flash=${caps.flash} torch=${caps.torch} formats=${caps.photoFormats} " +
                    "sizes=${caps.photoSizes.take(3).map { "${it.width}x${it.height}" }} live=${caps.live.supported}/${caps.live.audio} video=${caps.video.options.map { "${it.size.width}x${it.size.height}@${it.fps}" }}",
            )
            assertEquals(camera.id, caps.cameraId)
            assertTrue("hardware level must be reported", caps.hardwareLevel != "UNKNOWN")
            assertTrue("a camera must offer photo sizes", caps.photoSizes.isNotEmpty())
            assertTrue(PhotoFormatMessage.JPEG in caps.photoFormats)
            // The probe never exposes manual ISO without MANUAL_SENSOR-grade ranges.
            caps.iso?.let { assertTrue(it.min in 1 until it.max) }
            caps.exposureTimeNs?.let { assertTrue(it.min in 1 until it.max) }
        }
    }

    // [CAM-001]
    @Test
    fun opensTheBackCameraAndDeliversPreviewFrames() = runBlocking {
        val info = open(backCamera().id)
        assertEquals(CameraSourceMessage.HARDWARE, info.source)
        assertTrue(info.previewSize.width > 0 && info.previewSize.height > 0)
        assertTrue(info.photoSize.width * info.photoSize.height >= info.previewSize.width * info.previewSize.height)
        assertTrue("preview frames must flow into the texture", rig.textures.single().waitForFrames(10))
        rig.service.closeSession(info.sessionId)
        rig.service.closeSession(info.sessionId) // idempotent
        assertEquals(0, rig.service.openSessionCount)
    }

    // [CAM-003] [CAM-050] [NFR-002]
    @Test
    fun capturesAPhotoAtTheLargestSizeAndReportsTheAppliedSettings() = runBlocking {
        val camera = backCamera()
        val caps = rig.service.capabilities(camera.id)
        val info = open(camera.id)
        rig.textures.single().waitForFrames(5)
        val result = rig.service.capture(info.sessionId, rig.request("shot1"))

        val original = File(result.originalPath)
        assertTrue(original.exists() && original.length() > 1000)
        assertEquals("image/jpeg", result.originalMime)
        val largest = caps.photoSizes.maxByOrNull { it.width * it.height }!!
        assertEquals(largest.width, result.width)
        assertEquals(largest.height, result.height)
        val decoded = BitmapFactory.decodeFile(original.path)
        assertNotNull("the original must be a valid JPEG", decoded)
        assertEquals(result.width.toInt(), decoded.width)

        // renditions
        assertFalse("renditions must not fail", result.renderFailed)
        val rendered = BitmapFactory.decodeFile(result.renderedPath)
        val display = BitmapFactory.decodeFile(result.displayPath)
        val thumb = BitmapFactory.decodeFile(result.thumbnailPath)
        assertTrue(maxOf(display.width, display.height) <= 2048)
        assertTrue(maxOf(thumb.width, thumb.height) <= 512)
        assertTrue("rendered keeps the original shape once upright", rendered.width * rendered.height > display.width * display.height / 2)

        // CAM-050: the applied values come from the capture result
        assertNotNull(result.applied.exposureTimeNs)
        assertNotNull(result.applied.focalLengthMm)
        assertTrue(result.applied.zoomRatio >= 1.0)
        assertEquals(CameraSourceMessage.HARDWARE, result.source)
        assertFalse(result.mirrored)
        assertTrue(result.orientationDegrees in listOf(0L, 90L, 180L, 270L))
        // NFR-002: no temp files left behind
        assertTrue(rig.outDir.list()!!.none { it.endsWith(AtomicFiles.TEMP_SUFFIX) })
        assertTrue(File(result.originalPath).name == "shot1-original.jpg")
    }

    // [CAM-044]
    @Test
    fun theAspectRatioCropsOnlyTheRenditionNeverTheOriginal() = runBlocking {
        val info = open(backCamera().id)
        rig.textures.single().waitForFrames(5)
        val result = rig.service.capture(info.sessionId, rig.request("square", aspect = "1:1"))
        val original = BitmapFactory.decodeFile(result.originalPath)
        val rendered = BitmapFactory.decodeFile(result.renderedPath)
        assertEquals(result.width.toInt(), original.width) // uncropped
        assertEquals(rendered.width, rendered.height) // 1:1
    }

    // [CAM-010] [CAM-011] [CAM-050]
    @Test
    fun manualIsoAndShutterAreAppliedAndReportedByTheDeviceWhenSupported() = runBlocking {
        val camera = backCamera()
        val caps = rig.service.capabilities(camera.id)
        assumeTrue("manual exposure not reported by this camera", caps.iso != null && caps.exposureTimeNs != null)
        val info = open(camera.id)
        val iso = caps.iso!!.min + (caps.iso!!.max - caps.iso!!.min) / 4
        val exposure = caps.exposureTimeNs!!.min + (caps.exposureTimeNs!!.max - caps.exposureTimeNs!!.min).coerceAtMost(100_000_000) / 4
        val applied = rig.service.applySettings(info.sessionId, ResolvedCaptureSettingsMessage(aeLock = false, focusMode = FocusModeMessage.CONTINUOUS, afLock = false, zoomRatio = 1.0, flash = FlashModeMessage.OFF, torch = false, iso = iso, exposureTimeNs = exposure))
        Log.i("DoroCapabilities", "manual exposure requested iso=$iso exposure=$exposure applied iso=${applied.iso} exposure=${applied.exposureTimeNs} mismatches=${applied.mismatches}")
        val result = rig.service.capture(info.sessionId, rig.request("manual"))
        assertNotNull(result.applied.iso)
        assertNotNull(result.applied.exposureTimeNs)
        // CAM-050: either the device honoured the request (no mismatches) or says precisely which field it ignored
        assertTrue(applied.mismatches.all { it in listOf("iso", "exposureTime") })
        if (applied.mismatches.isEmpty()) {
            assertTrue(kotlin.math.abs(applied.iso!! - iso) <= iso * 0.05 + 1)
            assertTrue(kotlin.math.abs(applied.exposureTimeNs!! - exposure) <= exposure * 0.10 + 1)
            assertTrue(result.applied.mismatches.isEmpty())
        }
    }

    // [CAM-012]
    @Test
    fun exposureCompensationIsReportedBackWhenSupported() = runBlocking {
        val camera = backCamera()
        val bias = rig.service.capabilities(camera.id).exposureBias
        assumeTrue("exposure compensation not reported", bias != null)
        val info = open(camera.id)
        val ev = bias!!.step * 3
        val applied = rig.service.applySettings(info.sessionId, ResolvedCaptureSettingsMessage(aeLock = false, focusMode = FocusModeMessage.CONTINUOUS, afLock = false, zoomRatio = 1.0, flash = FlashModeMessage.OFF, torch = false, exposureBiasEv = ev))
        assertNotNull(applied.exposureBiasEv)
        assertEquals(ev, applied.exposureBiasEv!!, bias.step / 2)
    }

    // [CAM-008]
    @Test
    fun zoomIsAppliedWithinTheReportedRange() = runBlocking {
        val camera = backCamera()
        val zoom = rig.service.capabilities(camera.id).zoom
        assumeTrue("no zoom range", zoom.max > 1.0)
        val info = open(camera.id)
        val target = minOf(2.0, zoom.max)
        val applied = rig.service.applySettings(info.sessionId, ResolvedCaptureSettingsMessage(aeLock = false, focusMode = FocusModeMessage.CONTINUOUS, afLock = false, zoomRatio = target, flash = FlashModeMessage.OFF, torch = false))
        assertEquals(target, applied.zoomRatio, target * 0.05)
        // asking beyond the range is clamped natively, and the applied value says so
        val clamped = rig.service.applySettings(info.sessionId, ResolvedCaptureSettingsMessage(aeLock = false, focusMode = FocusModeMessage.CONTINUOUS, afLock = false, zoomRatio = zoom.max * 5, flash = FlashModeMessage.OFF, torch = false))
        assertTrue(clamped.zoomRatio <= zoom.max * 1.05)
    }

    // [CAM-030] [CAM-031]
    @Test
    fun whiteBalancePresetsAndKelvinAreAppliedWhenSupported() = runBlocking {
        val camera = backCamera()
        val wb = rig.service.capabilities(camera.id).whiteBalance
        assumeTrue("only auto white balance reported", wb.presets.size > 1 || wb.kelvin != null)
        val info = open(camera.id)
        val preset = wb.presets.firstOrNull { it != WbPresetMessage.AUTO }
        if (preset != null) {
            val applied = rig.service.applySettings(info.sessionId, ResolvedCaptureSettingsMessage(aeLock = false, focusMode = FocusModeMessage.CONTINUOUS, afLock = false, zoomRatio = 1.0, flash = FlashModeMessage.OFF, torch = false, whiteBalancePreset = preset))
            assertEquals(preset.name.lowercase(), applied.whiteBalanceMode)
        }
        if (wb.kelvin != null) {
            val applied = rig.service.applySettings(info.sessionId, ResolvedCaptureSettingsMessage(aeLock = false, focusMode = FocusModeMessage.CONTINUOUS, afLock = false, zoomRatio = 1.0, flash = FlashModeMessage.OFF, torch = false, kelvin = 3200))
            Log.i("DoroCapabilities", "kelvin 3200 applied mode=${applied.whiteBalanceMode} gains=${applied.whiteBalanceGains} estimate=${applied.estimatedKelvin} mismatches=${applied.mismatches}")
            assertEquals("manual", applied.whiteBalanceMode)
            assertNotNull(applied.whiteBalanceGains)
        }
    }

    // [CAM-021]
    @Test
    fun manualFocusMovesTheLensWhenSupported() = runBlocking {
        val camera = backCamera()
        val manual = rig.service.capabilities(camera.id).focus.manual
        assumeTrue("no manual focus", manual != null)
        val info = open(camera.id)
        val target = manual!!.minFocusDistanceDiopters / 2
        val applied = rig.service.applySettings(info.sessionId, ResolvedCaptureSettingsMessage(aeLock = false, focusMode = FocusModeMessage.MANUAL, afLock = false, zoomRatio = 1.0, flash = FlashModeMessage.OFF, torch = false, focusDistanceDiopters = target))
        Log.i("DoroCapabilities", "manual focus target=$target applied=${applied.focusDistanceDiopters} mismatches=${applied.mismatches}")
        assertEquals(FocusModeMessage.MANUAL, applied.focusMode)
    }

    // [CAM-020]
    @Test
    fun tapToFocusRunsWithoutErrorsWhenSupported() = runBlocking {
        val camera = backCamera()
        assumeTrue("no tap to focus", rig.service.capabilities(camera.id).focus.tapToFocus)
        val info = open(camera.id)
        rig.service.focusAt(info.sessionId, 0.5, 0.5)
        rig.service.focusAt(info.sessionId, 0.1, 0.9)
        assertTrue(rig.textures.single().waitForFrames(5))
    }

    // [CAM-014]
    @Test
    fun exposureLockIsReportedWhenSupported() = runBlocking {
        val camera = backCamera()
        val info = open(camera.id)
        val applied = rig.service.applySettings(info.sessionId, ResolvedCaptureSettingsMessage(aeLock = true, focusMode = FocusModeMessage.CONTINUOUS, afLock = false, zoomRatio = 1.0, flash = FlashModeMessage.OFF, torch = false))
        // Whether the lock is honoured is reported through aeLocked/mismatches, never silently assumed.
        assertTrue(applied.aeLocked || "aeLock" in applied.mismatches || !hasAeLock(camera.id))
    }

    private fun hasAeLock(cameraId: String): Boolean {
        val manager = rig.context.getSystemService(android.content.Context.CAMERA_SERVICE) as android.hardware.camera2.CameraManager
        return CharacteristicsReader.read(cameraId, manager.getCameraCharacteristics(cameraId)).aeLockAvailable
    }

    // [CAM-053]
    @Test
    fun suspendingStopsThePreviewAndResumingRestartsIt() = runBlocking {
        val info = open(backCamera().id)
        val texture = rig.textures.single()
        assertTrue(texture.waitForFrames(5))
        rig.service.suspendSession(info.sessionId)
        val atSuspend = texture.frames.get()
        Thread.sleep(800)
        assertTrue("no frames while suspended", texture.frames.get() - atSuspend <= 2)
        val captureWhileSuspended = runCatching { rig.service.capture(info.sessionId, rig.request("late")) }.exceptionOrNull()
        assertTrue(captureWhileSuspended is CameraException && captureWhileSuspended.code == "camera_disconnected")
        rig.service.resumeSession(info.sessionId)
        val atResume = texture.frames.get()
        assertTrue(texture.waitForFrames(atResume + 5))
        val result = rig.service.capture(info.sessionId, rig.request("after-resume"))
        assertTrue(File(result.originalPath).exists())
        assertTrue(rig.events.any { it.kind == SessionEventKindMessage.STATE && it.state == SessionStateMessage.SUSPENDED })
    }

    // [CAM-053] docs/specs/camera.md: camera_in_use
    @Test
    fun anotherClientTakingTheCameraInterruptsTheSessionAndItCanResume() = runBlocking {
        val camera = backCamera()
        val first = open(camera.id)
        assertTrue(rig.textures[0].waitForFrames(5))
        // A second session on the same camera steals it: the first is disconnected by the camera service.
        val second = open(camera.id)
        assertTrue(rig.textures[1].waitForFrames(5))
        val deadline = System.currentTimeMillis() + 5000
        while (System.currentTimeMillis() < deadline && rig.events.none { it.sessionId == first.sessionId && it.kind == SessionEventKindMessage.INTERRUPTED }) Thread.sleep(100)
        val interrupted = rig.events.firstOrNull { it.sessionId == first.sessionId && it.kind == SessionEventKindMessage.INTERRUPTED }
        assertNotNull("the first session must be told it was interrupted", interrupted)
        assertTrue(interrupted!!.errorCode in listOf("camera_in_use", "camera_disconnected"))
        val result = runCatching { rig.service.capture(first.sessionId, rig.request("interrupted")) }.exceptionOrNull()
        assertTrue("capture must fail cleanly, not crash", result is CameraException)
        // no partial files
        assertTrue(rig.outDir.listFiles().orEmpty().none { it.name.startsWith("interrupted") })
        rig.service.closeSession(second.sessionId)
    }

    // [NFR-002] storage problems become a typed error and leave no partial capture
    @Test
    fun anUnwritableOutputDirectoryFailsCleanlyWithoutPartialFiles() = runBlocking {
        val info = open(backCamera().id)
        rig.textures.single().waitForFrames(5)
        val locked = File(rig.outDir, "locked").also { it.mkdirs() }
        locked.setWritable(false)
        val request = rig.request("blocked").copy(outputDir = locked.path)
        val error = runCatching { rig.service.capture(info.sessionId, request) }.exceptionOrNull()
        locked.setWritable(true)
        assertTrue("expected a CameraException, got $error", error is CameraException)
        assertTrue(locked.list()!!.isEmpty())
    }

    @Test
    fun badRequestsAreRejectedBeforeTouchingTheCamera() = runBlocking {
        val info = open(backCamera().id)
        val traversal = runCatching { rig.service.capture(info.sessionId, rig.request("x").copy(originalName = "../evil.jpg")) }.exceptionOrNull()
        assertTrue(traversal is CameraException && traversal.code == "unsupported_configuration")
        val missingDir = runCatching { rig.service.capture(info.sessionId, rig.request("x").copy(outputDir = File(rig.outDir, "nope").path)) }.exceptionOrNull()
        assertTrue(missingDir is CameraException && missingDir.code == "unsupported_configuration")
        assertTrue(rig.service.capabilities(backCamera().id).photoSizes.isNotEmpty()) // still healthy
    }

    // [CAM-004] the front camera too
    @Test
    fun theFrontCameraCapturesAndIsNotMirroredInTheFile() = runBlocking {
        val front = rig.hardwareCameras().firstOrNull { it.facing == CameraFacingMessage.FRONT }
        assumeTrue("no front camera", front != null)
        val info = open(front!!.id)
        rig.textures.single().waitForFrames(5)
        val result = rig.service.capture(info.sessionId, rig.request("front"))
        assertFalse(result.mirrored)
        assertTrue(File(result.originalPath).exists())
        val exif = ExifInterface(result.originalPath)
        Log.i("DoroCapabilities", "front exif orientation=${exif.getAttribute(ExifInterface.TAG_ORIENTATION)} reported=${result.orientationDegrees}")
        assertTrue(result.orientationDegrees in listOf(0L, 90L, 180L, 270L))
    }

    // [MOT-002] [MOT-009] [NFR-012]
    @Test
    fun liveBuffersOnlyWhileOnAndReportsHonestlyWhetherItStarted() = runBlocking {
        val camera = backCamera()
        val caps = rig.service.capabilities(camera.id)
        assumeTrue("LIVE not supported on this camera", caps.live.supported)
        val info = open(camera.id, live = true)
        Log.i("DoroCapabilities", "live requested active=${info.liveActive} audio=${info.audioActive}")
        if (!info.liveActive) {
            // The device cannot run preview + photo + encoder together: it must say so and still capture a photo.
            assertTrue(rig.events.any { it.kind == SessionEventKindMessage.ERROR })
            val result = rig.service.capture(info.sessionId, rig.request("nolive", live = true))
            assertFalse(result.liveIncluded)
            return@runBlocking
        }
        assertTrue(rig.textures.single().waitForFrames(10))
        Thread.sleep(2500) // let the pre-roll fill
        val result = rig.service.capture(info.sessionId, rig.request("live", live = true))
        val motion = result.motion
        assertTrue("LIVE was active, so the capture must include motion", result.liveIncluded && motion != null)
        val facts = ClipInspector.facts(motion!!.path)
        assertTrue(facts.hasVideoTrack)
        assertTrue("clip duration ${facts.durationMs} should span pre and post roll", facts.durationMs >= 2000)
        assertTrue(motion.preRollMs >= 1000)
        assertEquals(motion.keyFrameTimeMs, motion.preRollMs)
        assertTrue(File(result.originalPath).exists())
        // turning LIVE off stops the pipeline: the next capture has no motion
        rig.service.setLive(info.sessionId, false)
        Thread.sleep(1500)
        val plain = rig.service.capture(info.sessionId, rig.request("plain", live = true))
        assertFalse(plain.liveIncluded)
    }

    // [VID-001]
    @Test
    fun recordsAVideoWithAudioInOneContainer() = runBlocking {
        val camera = backCamera()
        val video = rig.service.capabilities(camera.id).video
        assumeTrue("no video encoder or sizes", video.options.isNotEmpty())
        val info = open(camera.id)
        rig.textures.single().waitForFrames(5)
        val smallest = video.options.minByOrNull { it.size.width * it.size.height }!!
        val target = File(rig.outDir, "clip.mp4")
        rig.service.startVideo(info.sessionId, VideoRequestMessage(outputPath = target.path, audio = true, size = smallest.size, fps = smallest.fps.first()))
        assertTrue(rig.events.any { it.kind == SessionEventKindMessage.STATE && it.state == SessionStateMessage.RECORDING })
        Thread.sleep(2500)
        val result = rig.service.stopVideo(info.sessionId)
        assertTrue(target.exists() && target.length() > 1000)
        val facts = ClipInspector.facts(target.path)
        assertTrue(facts.hasVideoTrack)
        assertTrue("duration ${facts.durationMs}", facts.durationMs in 1500..4500)
        assertTrue("recorded size ${facts.width}x${facts.height}", maxOf(facts.width, facts.height) == maxOf(smallest.size.width, smallest.size.height).toInt())
        assertTrue("reported ${result.durationMs} ms vs file ${facts.durationMs} ms", kotlin.math.abs(result.durationMs - facts.durationMs) <= 400)
        assertTrue(rig.outDir.list()!!.none { it.endsWith(AtomicFiles.TEMP_SUFFIX) })
        // a photo can be taken again afterwards
        assertTrue(File(rig.service.capture(info.sessionId, rig.request("after-video")).originalPath).exists())
    }

    // docs/specs/camera.md: unsupported sizes are refused, not faked
    @Test
    fun anUnsupportedVideoSizeIsRefused() = runBlocking {
        val camera = backCamera()
        assumeTrue(rig.service.capabilities(camera.id).video.options.isNotEmpty())
        val info = open(camera.id)
        val error = runCatching {
            rig.service.startVideo(info.sessionId, VideoRequestMessage(outputPath = File(rig.outDir, "x.mp4").path, audio = false, size = SizeMessage(123, 45)))
        }.exceptionOrNull()
        assertTrue(error is CameraException && error.code == "unsupported_configuration")
    }

    // [NFR-012] thermal handling
    @Test
    fun aCriticalThermalStateSuspendsTheCameraAndSaysWhy() = runBlocking {
        val info = open(backCamera().id)
        rig.textures.single().waitForFrames(5)
        rig.thermal.set(ThermalStateMessage.CRITICAL)
        val deadline = System.currentTimeMillis() + 5000
        while (System.currentTimeMillis() < deadline && rig.events.none { it.errorCode == "thermal_shutdown" }) Thread.sleep(100)
        assertTrue(rig.events.any { it.kind == SessionEventKindMessage.THERMAL && it.thermal == ThermalStateMessage.CRITICAL })
        assertTrue(rig.events.any { it.kind == SessionEventKindMessage.ERROR && it.errorCode == "thermal_shutdown" })
        val error = runCatching { rig.service.capture(info.sessionId, rig.request("hot")) }.exceptionOrNull()
        assertTrue(error is CameraException)
    }
}
