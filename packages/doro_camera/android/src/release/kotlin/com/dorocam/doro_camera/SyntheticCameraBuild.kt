package com.dorocam.doro_camera

/** Release builds never contain the synthetic test camera (ADR-0013). */
object SyntheticCameraBuild {
    const val isCompiledIn: Boolean = false
}
