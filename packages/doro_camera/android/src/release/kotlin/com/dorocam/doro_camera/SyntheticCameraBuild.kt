package com.dorocam.doro_camera

import android.content.Context

/** Release builds never contain the synthetic test camera (ADR-0013). */
object SyntheticCameraBuild {
    const val isCompiledIn: Boolean = false

    @Suppress("UNUSED_PARAMETER")
    fun createBackend(context: Context, orientation: OrientationSource): CameraBackend? = null
}
