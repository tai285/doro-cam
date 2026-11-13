package com.dorocam.doro_camera

import android.Manifest
import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import kotlinx.coroutines.CompletableDeferred

/** What the permission logic needs from Android, so the status rules are unit tested on the JVM. */
interface PermissionPlatform {
    fun isGranted(permission: String): Boolean
    fun shouldShowRationale(permission: String): Boolean
    fun wasRequestedBefore(permission: String): Boolean
    fun markRequested(permission: String)
    fun cameraDisabledByPolicy(): Boolean
    fun hasActivity(): Boolean
    fun request(permissions: Array<String>, code: Int)
    fun openSettings()
}

/**
 * Camera and microphone permission flow (CAM-052). The status rules:
 *  - granted;
 *  - restricted: a device policy disables the camera (no settings link makes sense);
 *  - denied with `permanentlyDenied`: the system dialog will not show again, so the UI must send the
 *    user to settings; Android only reveals this after we asked once and no rationale is offered.
 */
class PermissionController(private val platform: PermissionPlatform) : PermissionChecker {
    companion object {
        const val REQUEST_CODE = 0xD0C0
        const val CAMERA = Manifest.permission.CAMERA
        const val MICROPHONE = Manifest.permission.RECORD_AUDIO
    }

    private var pending: CompletableDeferred<Unit>? = null

    private fun status(permission: String): PermissionStatusMessage = when {
        platform.isGranted(permission) -> PermissionStatusMessage.GRANTED
        permission == CAMERA && platform.cameraDisabledByPolicy() -> PermissionStatusMessage.RESTRICTED
        platform.wasRequestedBefore(permission) -> PermissionStatusMessage.DENIED
        else -> PermissionStatusMessage.NOT_DETERMINED
    }

    private fun permanentlyDenied(permission: String): Boolean =
        !platform.isGranted(permission) && platform.wasRequestedBefore(permission) && !platform.shouldShowRationale(permission)

    override fun check(): PermissionsMessage = PermissionsMessage(
        camera = status(CAMERA),
        microphone = status(MICROPHONE),
        cameraPermanentlyDenied = permanentlyDenied(CAMERA),
        microphonePermanentlyDenied = permanentlyDenied(MICROPHONE),
    )

    /** Asks for whatever is not granted yet and returns the new status once the user has answered. */
    suspend fun request(camera: Boolean, microphone: Boolean): PermissionsMessage {
        val wanted = buildList {
            if (camera && !platform.isGranted(CAMERA)) add(CAMERA)
            if (microphone && !platform.isGranted(MICROPHONE)) add(MICROPHONE)
        }
        if (wanted.isEmpty()) return check()
        if (!platform.hasActivity()) throw CameraException("permission_denied", "No foreground activity to ask for permission")
        val waiter = CompletableDeferred<Unit>()
        pending?.cancel()
        pending = waiter
        platform.request(wanted.toTypedArray(), REQUEST_CODE)
        waiter.await()
        wanted.forEach(platform::markRequested)
        return check()
    }

    /** Called from `onRequestPermissionsResult`. Returns true when the result was ours. */
    fun onResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        pending?.complete(Unit)
        pending = null
        return true
    }

    fun openSettings() = platform.openSettings()
}

/** The real Android implementation. */
class AndroidPermissionPlatform(
    private val context: Context,
    private val activity: () -> Activity?,
) : PermissionPlatform {
    private val prefs get() = context.getSharedPreferences("doro_camera_permissions", Context.MODE_PRIVATE)

    override fun isGranted(permission: String) = context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    override fun shouldShowRationale(permission: String) = activity()?.shouldShowRequestPermissionRationale(permission) ?: false

    override fun wasRequestedBefore(permission: String) = prefs.getBoolean(permission, false)

    override fun markRequested(permission: String) {
        prefs.edit().putBoolean(permission, true).apply()
    }

    override fun cameraDisabledByPolicy(): Boolean =
        (context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager)?.getCameraDisabled(null) == true

    override fun hasActivity() = activity() != null

    override fun request(permissions: Array<String>, code: Int) {
        activity()?.requestPermissions(permissions, code)
    }

    override fun openSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }
}
