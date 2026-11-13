package com.dorocam.doro_camera

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class MotionTest {
    private fun video(ms: Long, key: Boolean = false) = EncodedSample(true, ms * 1000, key, ByteArray(100))
    private fun audio(ms: Long) = EncodedSample(false, ms * 1000, true, ByteArray(10))

    /** 30 fps video with a key frame every second, audio every 23 ms, from 0 to [endMs]. */
    private fun fill(buffer: MotionRingBuffer, endMs: Long) {
        var t = 0L
        while (t <= endMs) {
            buffer.append(video(t, key = (t / 33) % 30 == 0L))
            t += 33
        }
        var a = 0L
        while (a <= endMs) {
            buffer.append(audio(a))
            a += 23
        }
    }

    // [MOT-009] [NFR-012]
    @Test
    fun `the window never holds much more than asked and always starts on a key frame`() {
        val ring = MotionRingBuffer(windowUs = 3_000_000)
        var t = 0L
        while (t <= 20_000) {
            ring.append(video(t, key = (t / 33) % 30 == 0L))
            ring.append(audio(t))
            t += 33
        }
        val snap = assertNotNull(ring.snapshot(20_000_000, 3_000_000))
        assertTrue(snap.video.first().keyFrame)
        assertTrue(snap.preRollUs in 3_000_000..4_100_000, "pre-roll ${snap.preRollUs}")
        assertTrue(ring.bytes < 1_000_000, "memory stays bounded: ${ring.bytes}")
        assertTrue(ring.videoCount < 200)
    }

    // [MOT-002]
    @Test
    fun `a snapshot starts at the newest key frame at or before shutter minus pre-roll`() {
        val ring = MotionRingBuffer(windowUs = 10_000_000)
        fill(ring, 5000)
        // key frames near 990, 1980, ... 33-ms grid: keys at multiples of 1000 only when divisible; use explicit ones
        val snap = assertNotNull(ring.snapshot(shutterUs = 4_000_000, preRollUs = 1_500_000))
        assertTrue(snap.startUs <= 2_500_000)
        assertTrue(snap.video.first().keyFrame)
        assertTrue(snap.video.all { it.ptsUs in snap.startUs..4_000_000 })
        assertTrue(snap.audio.all { it.ptsUs in snap.startUs..4_000_000 })
        assertEquals(4_000_000 - snap.startUs, snap.preRollUs)
        assertTrue(snap.preRollUs >= 1_500_000)
    }

    @Test
    fun `with less history than requested the clip starts at the first key frame`() {
        val ring = MotionRingBuffer(windowUs = 10_000_000)
        fill(ring, 1500)
        val snap = assertNotNull(ring.snapshot(shutterUs = 1_500_000, preRollUs = 3_000_000))
        assertEquals(0L, snap.startUs)
    }

    @Test
    fun `no key frame yet means no snapshot`() {
        val ring = MotionRingBuffer(windowUs = 3_000_000)
        assertNull(ring.snapshot(1_000_000, 500_000))
        ring.append(video(0, key = false))
        assertNull(ring.snapshot(1_000_000, 500_000))
        ring.clear()
        assertEquals(0, ring.videoCount)
        assertEquals(0, ring.audioCount)
        assertEquals(0L, ring.bytes)
    }

    @Test
    fun `samples after the shutter are not part of the pre-roll snapshot`() {
        val ring = MotionRingBuffer(windowUs = 10_000_000)
        fill(ring, 3000)
        val snap = assertNotNull(ring.snapshot(shutterUs = 2_000_000, preRollUs = 500_000))
        assertTrue(snap.video.none { it.ptsUs > 2_000_000 })
    }

    // [MOT-002]
    @Test
    fun `assembling interleaves video and audio by time, rebases nothing yet and reports clip facts`() {
        val snap = MotionSnapshot(
            video = listOf(video(1000, true), video(1033), video(1066)),
            audio = listOf(audio(1010), audio(1040)),
            startUs = 1_000_000,
            preRollUs = 66_000,
        )
        val post = listOf(video(1100), audio(1070), audio(1100))
        val clip = ClipAssembler.assemble(snap, post, shutterUs = 1_066_000)
        assertEquals(listOf(1000L, 1010L, 1033L, 1040L, 1066L, 1070L, 1100L, 1100L).sorted(), clip.samples.map { it.ptsUs / 1000 })
        assertEquals(1_000_000, clip.startUs)
        assertEquals(100_000, clip.durationUs)
        assertEquals(66_000, clip.shutterOffsetUs)
        assertTrue(clip.hasAudio)
        // video precedes audio at equal timestamps
        val equal = clip.samples.filter { it.ptsUs == 1_100_000L }
        assertTrue(equal.first().isVideo && !equal.last().isVideo)
    }

    @Test
    fun `a clip without audio samples says so`() {
        val snap = MotionSnapshot(listOf(video(0, true), video(33)), emptyList(), 0, 0)
        assertEquals(false, ClipAssembler.assemble(snap, emptyList(), 0).hasAudio)
    }

    @Test
    fun `clock alignment is the identity for realtime sources and learns the smallest offset otherwise`() {
        var now = 0L
        val realtime = ClockAligner(true) { now }
        realtime.observeFrame(5_000_000)
        assertEquals(1234L, realtime.toSharedUs(1234))

        val unknown = ClockAligner(false) { now }
        now = 10_000_000
        unknown.observeFrame(2_000_000_000) // frame time 2_000_000 us -> offset 8_000_000
        assertEquals(10_000_000L, unknown.toSharedUs(2_000_000))
        now = 10_050_000
        unknown.observeFrame(2_030_000_000) // offset 8_020_000: larger (more latency), ignored
        assertEquals(10_000_000L, unknown.toSharedUs(2_000_000))
        now = 10_020_000
        unknown.observeFrame(2_030_000_000) // offset 7_990_000: smaller, wins
        assertEquals(9_990_000L, unknown.toSharedUs(2_000_000))
    }
}
