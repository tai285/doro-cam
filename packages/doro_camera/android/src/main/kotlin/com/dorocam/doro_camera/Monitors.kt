package com.dorocam.doro_camera

import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.view.OrientationEventListener
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executor

/** Device orientation from the accelerometer, quantised to 0/90/180/270. Capture follows this, not the UI. */
interface OrientationSource {
    val degrees: Int
    fun addListener(listener: (Int) -> Unit)
    fun removeListener(listener: (Int) -> Unit)
}

class OrientationMonitor(context: Context) : OrientationSource {
    @Volatile override var degrees: Int = 0
        private set
    private val listeners = CopyOnWriteArrayList<(Int) -> Unit>()
    private val sensor = object : OrientationEventListener(context) {
        override fun onOrientationChanged(orientation: Int) {
            val next = Geometry.quantizeOrientation(orientation, degrees)
            if (next != degrees) {
                degrees = next
                listeners.forEach { it(next) }
            }
        }
    }

    override fun addListener(listener: (Int) -> Unit) {
        listeners.add(listener)
        if (listeners.size == 1 && sensor.canDetectOrientation()) sensor.enable()
    }

    override fun removeListener(listener: (Int) -> Unit) {
        listeners.remove(listener)
        if (listeners.isEmpty()) sensor.disable()
    }
}

/** Thermal state forwarded to sessions (NFR-012); API 29+, otherwise always nominal. */
interface ThermalSource {
    val state: ThermalStateMessage
    fun addListener(listener: (ThermalStateMessage) -> Unit)
    fun removeListener(listener: (ThermalStateMessage) -> Unit)
}

class ThermalMonitor(context: Context, private val executor: Executor) : ThermalSource {
    private val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
    private val listeners = CopyOnWriteArrayList<(ThermalStateMessage) -> Unit>()
    private var registered = false
    private val platformListener = if (Build.VERSION.SDK_INT >= 29) {
        PowerManager.OnThermalStatusChangedListener { status -> listeners.forEach { it(Geometry.thermalState(status)) } }
    } else {
        null
    }

    override val state: ThermalStateMessage
        get() = if (Build.VERSION.SDK_INT >= 29 && power != null) Geometry.thermalState(power.currentThermalStatus) else ThermalStateMessage.NOMINAL

    override fun addListener(listener: (ThermalStateMessage) -> Unit) {
        listeners.add(listener)
        if (!registered && Build.VERSION.SDK_INT >= 29 && power != null && platformListener != null) {
            power.addThermalStatusListener(executor, platformListener)
            registered = true
        }
    }

    override fun removeListener(listener: (ThermalStateMessage) -> Unit) {
        listeners.remove(listener)
        if (listeners.isEmpty() && registered && Build.VERSION.SDK_INT >= 29 && power != null && platformListener != null) {
            power.removeThermalStatusListener(platformListener)
            registered = false
        }
    }
}
