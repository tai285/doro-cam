package com.dorocam.doro_camera

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

private class FakeEnvironment(override val osVersion: String) : PlatformEnvironment

private const val PING_CHANNEL = "dev.flutter.pigeon.doro_camera.CameraHostApi.ping"

/** Encodes arguments the way Dart does and decodes the native reply, using the real Pigeon codec. */
private fun FakeBinaryMessenger.callPing(message: String): List<Any?> {
    val encoded = assertNotNull(CameraHostApi.codec.encodeMessage(listOf(message)))
    val reply = assertNotNull(deliver(PING_CHANNEL, encoded), "the native side must reply")
    @Suppress("UNCHECKED_CAST")
    return assertNotNull(CameraHostApi.codec.decodeMessage(reply) as? List<Any?>)
}

internal class DoroCameraPluginTest {
    // [CAM-004]
    @Test
    fun `ping echoes the message and reports the platform and OS version`() {
        val plugin = DoroCameraPlugin(FakeEnvironment("15"))

        val result = plugin.ping("hello")

        assertEquals("hello", result.echo)
        assertEquals("android", result.platform)
        assertEquals("15", result.osVersion)
        assertEquals(SyntheticCameraBuild.isCompiledIn, result.syntheticCameraCompiledIn)
    }

    @Test
    fun `ping keeps unusual text intact`() {
        val plugin = DoroCameraPlugin(FakeEnvironment("15"))
        val text = "Doro 相机 📷 — café"
        assertEquals(text, plugin.ping(text).echo)
        assertEquals("", plugin.ping("").echo)
    }

    @Test
    fun `attach registers the ping channel and detach removes it`() {
        val messenger = FakeBinaryMessenger()
        val plugin = DoroCameraPlugin(FakeEnvironment("15"))

        plugin.attach(messenger)
        assertEquals(setOf(PING_CHANNEL), messenger.registeredChannels)

        plugin.detach()
        assertTrue(messenger.registeredChannels.isEmpty())
    }

    @Test
    fun `detach without attach is harmless and detach is idempotent`() {
        val plugin = DoroCameraPlugin(FakeEnvironment("15"))
        plugin.detach()

        val messenger = FakeBinaryMessenger()
        plugin.attach(messenger)
        plugin.detach()
        plugin.detach()
        assertTrue(messenger.registeredChannels.isEmpty())
    }

    // [CAM-004]
    @Test
    fun `a ping delivered over the channel round-trips through the Pigeon codec`() {
        val messenger = FakeBinaryMessenger()
        DoroCameraPlugin(FakeEnvironment("14")).attach(messenger)

        val reply = messenger.callPing("over the wire")

        assertEquals(1, reply.size)
        val result = reply.single() as PingResultMessage
        assertEquals(
            PingResultMessage("over the wire", "android", "14", SyntheticCameraBuild.isCompiledIn),
            result,
        )
    }

    @Test
    fun `a detached plugin no longer answers`() {
        val messenger = FakeBinaryMessenger()
        val plugin = DoroCameraPlugin(FakeEnvironment("15"))
        plugin.attach(messenger)
        plugin.detach()

        assertFailsWith<IllegalStateException> { messenger.callPing("anyone there?") }
    }

    @Test
    fun `a FlutterError from the host becomes a code-message-details reply for Dart`() {
        val messenger = FakeBinaryMessenger()
        val failing = object : CameraHostApi {
            override fun ping(message: String): PingResultMessage =
                throw FlutterError("permission_denied", "Camera permission was denied", null)
        }
        CameraHostApi.setUp(messenger, failing)

        val reply = messenger.callPing("x")

        assertEquals(listOf<Any?>("permission_denied", "Camera permission was denied", null), reply)
    }

    @Test
    fun `an unexpected exception becomes an error reply without crashing the channel`() {
        val messenger = FakeBinaryMessenger()
        val failing = object : CameraHostApi {
            override fun ping(message: String): PingResultMessage = throw IllegalStateException("bug")
        }
        CameraHostApi.setUp(messenger, failing)

        val reply = messenger.callPing("x")

        assertEquals(3, reply.size)
        assertEquals("IllegalStateException", reply[0])
        assertTrue((reply[1] as String).contains("bug"))
    }

    @Test
    fun `PingResultMessage supports value equality`() {
        val a = PingResultMessage("e", "android", "15", false)
        assertEquals(a, PingResultMessage("e", "android", "15", false))
        assertEquals(a.hashCode(), PingResultMessage("e", "android", "15", false).hashCode())
        assertTrue(a != PingResultMessage("e", "android", "15", true))
    }
}
