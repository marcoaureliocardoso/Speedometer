package com.example.speedometer

import android.content.Context
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.view.Surface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.PI

class MainActivity : FlutterActivity(), SensorEventListener {
    private var headingEvents: EventChannel.EventSink? = null
    private var declinationDegrees = 0f
    private lateinit var sensorManager: SensorManager
    private var rotationVector: Sensor? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        rotationVector = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "speedometer/rotation_vector_heading/events"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                headingEvents = events
                val sensor = rotationVector
                if (sensor == null) {
                    events?.error("sensor_unavailable", "Sensor de orientação indisponível.", null)
                    return
                }
                sensorManager.registerListener(
                    this@MainActivity,
                    sensor,
                    SensorManager.SENSOR_DELAY_GAME
                )
            }

            override fun onCancel(arguments: Any?) {
                headingEvents = null
                sensorManager.unregisterListener(this@MainActivity)
            }
        })
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "speedometer/rotation_vector_heading/methods"
        ).setMethodCallHandler { call, result ->
            if (call.method == "isAvailable") {
                result.success(rotationVector != null)
                return@setMethodCallHandler
            }
            if (call.method != "setLocation") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val latitude = call.argument<Double>("latitude")
            val longitude = call.argument<Double>("longitude")
            if (latitude == null || longitude == null) {
                result.error("invalid_location", "Latitude e longitude são obrigatórias.", null)
                return@setMethodCallHandler
            }
            declinationDegrees = GeomagneticField(
                latitude.toFloat(),
                longitude.toFloat(),
                0f,
                System.currentTimeMillis()
            ).declination
            result.success(null)
        }
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_ROTATION_VECTOR) return
        val rotationMatrix = FloatArray(9)
        val remappedMatrix = FloatArray(9)
        val orientation = FloatArray(3)
        SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
        val axes = when (displayRotation()) {
            Surface.ROTATION_90 -> SensorManager.AXIS_Y to SensorManager.AXIS_MINUS_X
            Surface.ROTATION_180 -> SensorManager.AXIS_MINUS_X to SensorManager.AXIS_MINUS_Y
            Surface.ROTATION_270 -> SensorManager.AXIS_MINUS_Y to SensorManager.AXIS_X
            else -> SensorManager.AXIS_X to SensorManager.AXIS_Y
        }
        SensorManager.remapCoordinateSystem(
            rotationMatrix,
            axes.first,
            axes.second,
            remappedMatrix
        )
        SensorManager.getOrientation(remappedMatrix, orientation)
        val degrees = ((orientation[0] * 180 / PI + declinationDegrees + 360) % 360).toFloat()
        headingEvents?.success(mapOf("degrees" to degrees, "accuracy" to event.accuracy))
    }

    @Suppress("DEPRECATION")
    private fun displayRotation(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        display?.rotation ?: Surface.ROTATION_0
    } else {
        windowManager.defaultDisplay.rotation
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    override fun onDestroy() {
        sensorManager.unregisterListener(this)
        super.onDestroy()
    }
}
