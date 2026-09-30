package com.dorocam.doro_camera

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Runs only for the debug variant: the synthetic test camera is present there (ADR-0013). */
internal class SyntheticCameraBuildDebugTest {
    // [NFR-016]
    @Test
    fun `debug builds contain the synthetic camera and report it`() {
        assertTrue(SyntheticCameraBuild.isCompiledIn)
        assertEquals("dorocam.synthetic-camera.v1", SyntheticCameraBuild.marker)
    }

    // [NFR-016]
    @Test
    fun `ping reports the synthetic camera as compiled in for debug builds`() {
        val plugin = DoroCameraPlugin(object : PlatformEnvironment {
            override val osVersion = "15"
        })
        assertTrue(plugin.ping("x").syntheticCameraCompiledIn)
    }
}
