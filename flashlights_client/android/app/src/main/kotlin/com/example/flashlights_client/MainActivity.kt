package com.example.flashlights_client

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ai.keex.flashlights/torch"
        ).setMethodCallHandler { call, result ->
            if (call.method == "setTorchLevel") {
                val level = call.arguments as Double
                try {
                    setTorchLevel(level)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("TORCH_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun setTorchLevel(level: Double) {
        val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraId = cm.cameraIdList.firstOrNull { id ->
            val chars = cm.getCameraCharacteristics(id)
            chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        } ?: return

        if (level <= 0.0) {
            cm.setTorchMode(cameraId, false)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val max = cm.getCameraCharacteristics(cameraId)
                .get(CameraCharacteristics.FLASH_INFO_STRENGTH_MAXIMUM_LEVEL) ?: 1
            var intLevel = (level * max).roundToInt().coerceIn(1, max)
            cm.turnOnTorchWithStrengthLevel(cameraId, intLevel)
        } else {
            cm.setTorchMode(cameraId, true)
        }
    }
}
