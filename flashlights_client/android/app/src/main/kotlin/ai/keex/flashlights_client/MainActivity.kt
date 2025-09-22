package ai.keex.flashlights_client

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.media.AudioAttributes
import android.media.MediaPlayer
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import ai.keex.flashlights_client.KeepAliveService
import android.net.wifi.WifiManager
import android.content.Context.WIFI_SERVICE
import kotlin.math.roundToInt
import android.util.Log

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var primerPlayer: MediaPlayer? = null

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
                    Log.e(TAG, "Torch channel error", e)
                    result.error("TORCH_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ai.keex.flashlights/client"
        ).setMethodCallHandler { call, result ->
            if (call.method == "startService") {
                KeepAliveService.start(this)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ai.keex.flashlights/network"
        ).setMethodCallHandler { call, result ->
            if (call.method == "acquireMulticastLock") {
                acquireMulticastLock()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ai.keex.flashlights/audioNative"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "playPrimerTone" -> {
                    val assetKey = call.argument<String>("assetKey")
                    if (assetKey == null) {
                        result.error("INVALID_ARGUMENTS", "assetKey missing", null)
                        return@setMethodCallHandler
                    }
                    val volume = (call.argument<Number>("volume") ?: 1.0).toFloat()
                    playPrimerTone(assetKey, volume)
                    result.success(null)
                }
                "stopPrimerTone" -> {
                    stopPrimerTone()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setTorchLevel(level: Double) {
        val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager

        try {
            val cameraId = cm.cameraIdList.firstOrNull { id ->
                val chars = cm.getCameraCharacteristics(id)
                chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            } ?: throw IllegalStateException("No camera with flash available")

            if (level <= 0.0) {
                cm.setTorchMode(cameraId, false)
                return
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val max = cm.getCameraCharacteristics(cameraId)
                    .get(CameraCharacteristics.FLASH_INFO_STRENGTH_MAXIMUM_LEVEL) ?: 1
                val intLevel = (level * max).roundToInt().coerceIn(1, max)
                cm.turnOnTorchWithStrengthLevel(cameraId, intLevel)
            } else {
                cm.setTorchMode(cameraId, true)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set torch level to $level", e)
            throw e
        }
    }

    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return

        val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as? WifiManager
            ?: return
        val lock = wifiManager.createMulticastLock("FlashlightsMulticast").apply {
            setReferenceCounted(true)
            acquire()
        }
        multicastLock = lock
    }

    private fun playPrimerTone(assetKey: String, volume: Float) {
        try {
            val flutterLoader = FlutterInjector.instance().flutterLoader()
            val lookupKey = flutterLoader.getLookupKeyForAsset(assetKey)

            val assetManager = applicationContext.assets
            val descriptor = assetManager.openFd(lookupKey)

            try {
                primerPlayer?.release()
                primerPlayer = MediaPlayer().apply {
                    setDataSource(descriptor.fileDescriptor, descriptor.startOffset, descriptor.length)
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                            .build()
                    )
                    val clampedVolume = volume.coerceIn(0f, 1f)
                    setVolume(clampedVolume, clampedVolume)
                    prepare()
                    start()
                }
            } finally {
                descriptor.close()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopPrimerTone() {
        primerPlayer?.stop()
        primerPlayer?.release()
        primerPlayer = null
    }

    override fun onDestroy() {
        multicastLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        multicastLock = null
        stopPrimerTone()
        super.onDestroy()
    }
}

private const val TAG = "FlashlightsClient"
