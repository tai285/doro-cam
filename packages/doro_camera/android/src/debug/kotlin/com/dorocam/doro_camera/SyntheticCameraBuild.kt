package com.dorocam.doro_camera

import android.content.Context

/**
 * Debug and test builds contain the synthetic test camera (ADR-0013). This file exists only in the
 * `debug` source set. The marker string lets CI prove that release artifacts do NOT contain it:
 * the debug APK must contain the marker and the release APK must not.
 */
object SyntheticCameraBuild {
    const val isCompiledIn: Boolean = true

    /** Unique, greppable text. Never reuse it anywhere outside the debug source set. */
    val marker: String = "dorocam.synthetic-camera.v1"

    fun createBackend(context: Context, orientation: OrientationSource): CameraBackend? = SyntheticBackend(context, orientation)
}
