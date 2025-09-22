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
import java.io.File
import java.io.FileOutputStream

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
                    val fileName = call.argument<String>("fileName")
                    if (fileName == null) {
                        result.error("INVALID_ARGUMENTS", "fileName missing", null)
                        return@setMethodCallHandler
                    }
                    val volume = (call.argument<Number>("volume") ?: 1.0).toFloat()
                    val assetKey = call.argument<String>("assetKey")
                    val bytes = call.argument<ByteArray>("bytes")
                    playPrimerTone(fileName, volume, assetKey, bytes)
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

    private fun playPrimerTone(
        fileName: String,
        volume: Float,
        assetKeyArg: String?,
        bytes: ByteArray?
    ) {
        try {
            var trimmed = fileName.trim()
            val parts = trimmed.split("/")
            if (parts.isNotEmpty()) {
                trimmed = parts.last()
            }
            val lower = trimmed.lowercase()
            var canonical = when {
                lower.startsWith("short") -> "Short" + trimmed.substring(5)
                lower.startsWith("long") -> "Long" + trimmed.substring(4)
                else -> trimmed
            }
            if (!canonical.lowercase().endsWith(".mp3")) {
                canonical += ".mp3"
            }
            val assetKey = assetKeyArg ?: "available-sounds/primerTones/$canonical"

            primerPlayer?.release()
            primerPlayer = null

            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )

            if (bytes != null) {
                val cacheRoot = File(applicationContext.cacheDir, "primerTones")
                if (!cacheRoot.exists()) {
                    cacheRoot.mkdirs()
                }
                val cacheFile = File(cacheRoot, canonical)
                if (!cacheFile.exists() || cacheFile.length().toInt() != bytes.size) {
                    FileOutputStream(cacheFile).use { output ->
                        output.write(bytes)
                    }
                }
                mp.setDataSource(cacheFile.absolutePath)
            } else {
                val flutterLoader = FlutterInjector.instance().flutterLoader()
                val lookupKey = flutterLoader.getLookupKeyForAsset(assetKey)
                applicationContext.assets.openFd(lookupKey).use { descriptor ->
                    mp.setDataSource(descriptor.fileDescriptor, descriptor.startOffset, descriptor.length)
                }
            }

            val clampedVolume = volume.coerceIn(0f, 1f)
            mp.setVolume(clampedVolume, clampedVolume)
            mp.prepare()
            mp.start()
            primerPlayer = mp
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
