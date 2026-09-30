package com.dorocam.doro_camera

import io.flutter.plugin.common.BinaryMessenger
import java.nio.ByteBuffer

/**
 * A BinaryMessenger for JVM tests: remembers the handler registered per channel and lets a test
 * play the role of Dart by delivering encoded messages to it.
 */
class FakeBinaryMessenger : BinaryMessenger {
    private val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler?>()

    val registeredChannels: Set<String>
        get() = handlers.filterValues { it != null }.keys

    override fun send(channel: String, message: ByteBuffer?) {
        error("Not used in these tests: Dart-bound messages are not simulated")
    }

    override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
        error("Not used in these tests: Dart-bound messages are not simulated")
    }

    override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
        handlers[channel] = handler
    }

    /** Delivers [message] to the native handler on [channel] and returns its reply (null if none). */
    fun deliver(channel: String, message: ByteBuffer): ByteBuffer? {
        val handler = handlers[channel] ?: error("No handler registered on $channel")
        var reply: ByteBuffer? = null
        message.rewind()
        handler.onMessage(message) { reply = it }
        return reply?.also { it.rewind() }
    }
}
