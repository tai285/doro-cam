package com.dorocam.doro_camera

/**
 * What the plugin needs to know about the device. A seam so JVM unit tests can run without the
 * Android runtime (docs/architecture/camera.md, testability seams).
 */
interface PlatformEnvironment {
    /** Android release version, for example `15`. */
    val osVersion: String
}

/** The real device. */
object SystemPlatformEnvironment : PlatformEnvironment {
    override val osVersion: String
        get() = android.os.Build.VERSION.RELEASE
}
