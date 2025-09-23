package ai.keex.flashlights_client

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.media.AudioAttributes
import android.media.MediaMetadataRetriever
import android.media.SoundPool
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import ai.keex.flashlights_client.KeepAliveService
import android.net.wifi.WifiManager
import android.content.Context.WIFI_SERVICE
import kotlin.math.roundToInt
import android.util.Log
import android.os.Handler
import android.os.Looper
import android.content.res.AssetFileDescriptor
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private lateinit var primerAudio: PrimerToneManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        primerAudio = PrimerToneManager(applicationContext)
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
                "initializePrimerLibrary" -> {
                    primerAudio.initialize { outcome ->
                        outcome.onSuccess { payload ->
                            result.success(payload)
                        }.onFailure { error ->
                            result.error("INIT_FAILED", error.message, null)
                        }
                    }
                }
                "playPrimerTone" -> {
                    val fileName = call.argument<String>("fileName")
                    if (fileName == null) {
                        result.error("INVALID_ARGUMENTS", "fileName missing", null)
                        return@setMethodCallHandler
                    }
                    val volume = (call.argument<Number>("volume") ?: 1.0).toFloat()
                    primerAudio.play(fileName, volume)
                    result.success(null)
                }
                "stopPrimerTone" -> {
                    primerAudio.stopAll()
                    result.success(null)
                }
                "diagnostics" -> {
                    result.success(primerAudio.diagnostics())
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

    override fun onDestroy() {
        multicastLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        multicastLock = null
        if (::primerAudio.isInitialized) {
            primerAudio.release()
        }
        super.onDestroy()
    }
}

private class PrimerToneManager(context: Context) {
    private val appContext = context.applicationContext
    private val assetManager = appContext.assets
    private val flutterLoader = FlutterInjector.instance().flutterLoader()
    private val cacheDirectory: File = File(appContext.cacheDir, "primerTones").apply {
        if (!exists()) {
            mkdirs()
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val soundPool: SoundPool = SoundPool.Builder()
        .setMaxStreams(MAX_SOUND_STREAMS)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        )
        .build()

    private val lock = Any()
    private val soundIds: MutableMap<String, Int> = mutableMapOf()
    private val durationsMs: MutableMap<String, Long> = mutableMapOf()
    private val activeStreams = Collections.synchronizedSet(mutableSetOf<Int>())
    private val cleanupTasks = ConcurrentHashMap<Int, Runnable>()
    private var totalBytes: Long = 0
    private var totalDurationMs: Long = 0
    private var initialised = false
    private var initialising = false
    private val pendingCallbacks = mutableListOf<(Result<Map<String, Any?>>) -> Unit>()

    fun initialize(callback: (Result<Map<String, Any?>>) -> Unit) {
        val startInitialisation: Boolean
        synchronized(lock) {
            if (initialised) {
                callback(Result.success(diagnosticsLocked()))
                return
            }
            pendingCallbacks.add(callback)
            if (initialising) {
                return
            }
            initialising = true
            startInitialisation = true
        }

        if (startInitialisation) {
            executor.execute {
                val outcome = runCatching { performInitialization() }
                val callbacks = mutableListOf<(Result<Map<String, Any?>>) -> Unit>()
                synchronized(lock) {
                    initialising = false
                    if (outcome.isSuccess) {
                        initialised = true
                    }
                    callbacks.addAll(pendingCallbacks)
                    pendingCallbacks.clear()
                }
                callbacks.forEach { cb ->
                    handler.post { cb(outcome) }
                }
            }
        }
    }

    fun play(fileName: String, volume: Float) {
        val canonical = canonicalName(fileName)
        val soundId: Int
        val duration: Long
        synchronized(lock) {
            if (!initialised) {
                Log.w(TAG, "PrimerToneManager play requested before initialisation complete")
                return
            }
            soundId = soundIds[canonical] ?: run {
                Log.w(TAG, "PrimerToneManager missing sound for $fileName")
                return
            }
            duration = durationsMs[canonical] ?: 0L
        }

        val clamped = volume.coerceIn(0f, 1f)
        val streamId = soundPool.play(soundId, clamped, clamped, /* priority */ 1, /* loop */ 0, /* rate */ 1f)
        if (streamId == 0) {
            Log.w(TAG, "SoundPool returned streamId=0 for $canonical")
            return
        }

        activeStreams.add(streamId)
        val cleanupDelay = if (duration > 0) duration + STREAM_CLEANUP_PADDING_MS else DEFAULT_STREAM_DURATION_MS
        val cleanup = Runnable {
            activeStreams.remove(streamId)
            cleanupTasks.remove(streamId)
        }
        cleanupTasks[streamId] = cleanup
        handler.postDelayed(cleanup, cleanupDelay)
    }

    fun stopAll() {
        val toStop = mutableListOf<Int>()
        synchronized(lock) {
            toStop.addAll(activeStreams)
            activeStreams.clear()
            cleanupTasks.values.forEach { handler.removeCallbacks(it) }
            cleanupTasks.clear()
        }
        toStop.forEach { soundPool.stop(it) }
        soundPool.autoPause()
    }

    fun diagnostics(): Map<String, Any?> = synchronized(lock) { diagnosticsLocked() }

    fun release() {
        soundPool.setOnLoadCompleteListener(null)
        synchronized(lock) {
            cleanupTasks.values.forEach { handler.removeCallbacks(it) }
            cleanupTasks.clear()
            activeStreams.clear()
            pendingCallbacks.clear()
            initialised = false
            initialising = false
        }
        soundPool.release()
        executor.shutdownNow()
    }

    private fun performInitialization(): Map<String, Any?> {
        val assetKeys = loadPrimerAssetKeys()
        if (assetKeys.isEmpty()) {
            synchronized(lock) {
                soundIds.clear()
                durationsMs.clear()
                totalBytes = 0
                totalDurationMs = 0
            }
            return diagnosticsLocked()
        }

        val pending = preparePendingSounds(assetKeys)
        val latch = CountDownLatch(pending.size)
        val loadStatuses = ConcurrentHashMap<Int, Int>()
        val lookup = ConcurrentHashMap<Int, PendingSound>()

        soundPool.setOnLoadCompleteListener { _, sampleId, status ->
            loadStatuses[sampleId] = status
            lookup.remove(sampleId)
            latch.countDown()
        }

        for (spec in pending) {
            val soundId = when {
                spec.afd != null -> soundPool.load(spec.afd, PRIORITY_NORMAL)
                spec.file != null -> soundPool.load(spec.file.absolutePath, PRIORITY_NORMAL)
                else -> 0
            }
            spec.soundId = soundId
            if (soundId == 0) {
                latch.countDown()
            } else {
                lookup[soundId] = spec
            }
        }

        if (pending.isNotEmpty()) {
            latch.await()
        }

        soundPool.setOnLoadCompleteListener(null)
        pending.forEach { it.afd?.close() }

        var loadedCount = 0
        synchronized(lock) {
            soundIds.clear()
            durationsMs.clear()
            totalBytes = 0
            totalDurationMs = 0
            activeStreams.clear()
            cleanupTasks.values.forEach { handler.removeCallbacks(it) }
            cleanupTasks.clear()

            for (spec in pending) {
                val status = loadStatuses[spec.soundId]
                if (spec.soundId != 0 && status == STATUS_SUCCESS) {
                    soundIds[spec.canonical] = spec.soundId
                    durationsMs[spec.canonical] = spec.durationMs
                    if (spec.bytes > 0) {
                        totalBytes += spec.bytes
                    }
                    totalDurationMs += spec.durationMs
                    loadedCount += 1
                } else if (spec.soundId != 0) {
                    soundPool.unload(spec.soundId)
                }
            }
        }

        return diagnostics().toMutableMap().apply {
            this["count"] = loadedCount
        }
    }

    private fun diagnosticsLocked(): HashMap<String, Any?> {
        return hashMapOf(
            "initialised" to initialised,
            "sounds" to soundIds.size,
            "activeStreams" to activeStreams.size,
            "totalDurationMs" to totalDurationMs,
            "totalBytes" to totalBytes,
            "maxStreams" to MAX_SOUND_STREAMS
        )
    }

    private fun loadPrimerAssetKeys(): List<String> = try {
        val manifestKey = flutterLoader.getLookupKeyForAsset("AssetManifest.json")
        val json = assetManager.open(manifestKey).bufferedReader().use { it.readText() }
        val manifest = JSONObject(json)
        val keys = mutableListOf<String>()
        val iterator = manifest.keys()
        while (iterator.hasNext()) {
            val key = iterator.next()
            if (key.startsWith("available-sounds/primerTones/") && key.lowercase().endsWith(".mp3")) {
                keys.add(key)
            }
        }
        keys.sort()
        keys
    } catch (e: Exception) {
        Log.e(TAG, "Failed to parse AssetManifest for primer tones", e)
        emptyList()
    }

    private fun preparePendingSounds(assetKeys: List<String>): List<PendingSound> {
        val pending = mutableListOf<PendingSound>()
        for (assetKey in assetKeys) {
            val canonical = canonicalName(assetKey)
            if (canonical.isEmpty()) continue
            val lookupKey = flutterLoader.getLookupKeyForAsset(assetKey)
            try {
                val afd = assetManager.openFd(lookupKey)
                val duration = extractDuration(afd)
                val bytes = if (afd.length >= 0) afd.length else 0L
                pending += PendingSound(canonical, afd, null, bytes, duration)
            } catch (openError: IOException) {
                try {
                    val file = materialiseAsset(lookupKey, canonical)
                    val duration = extractDuration(file)
                    pending += PendingSound(canonical, null, file, file.length(), duration)
                } catch (cacheError: IOException) {
                    Log.e(TAG, "Failed to cache primer $assetKey", cacheError)
                }
            }
        }
        return pending
    }

    private fun materialiseAsset(lookupKey: String, canonical: String): File {
        val target = File(cacheDirectory, canonical)
        if (target.exists()) {
            return target
        }
        assetManager.open(lookupKey).use { input ->
            FileOutputStream(target).use { output ->
                input.copyTo(output)
            }
        }
        return target
    }

    private fun extractDuration(afd: AssetFileDescriptor): Long {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        } catch (e: Exception) {
            Log.w(TAG, "Duration lookup failed for descriptor", e)
            0L
        } finally {
            retriever.release()
        }
    }

    private fun extractDuration(file: File): Long {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        } catch (e: Exception) {
            Log.w(TAG, "Duration lookup failed for file ${file.name}", e)
            0L
        } finally {
            retriever.release()
        }
    }

    private fun canonicalName(value: String): String {
        var trimmed = value.trim()
        val parts = trimmed.split("/")
        if (parts.isNotEmpty()) {
            trimmed = parts.last()
        }
        val lower = trimmed.lowercase()
        trimmed = when {
            lower.startsWith("short") -> "Short" + trimmed.substring(5)
            lower.startsWith("long") -> "Long" + trimmed.substring(4)
            else -> trimmed
        }
        return if (trimmed.lowercase().endsWith(".mp3")) trimmed else "$trimmed.mp3"
    }

    private data class PendingSound(
        val canonical: String,
        val afd: AssetFileDescriptor?,
        val file: File?,
        val bytes: Long,
        val durationMs: Long,
        var soundId: Int = 0
    )

    companion object {
        private const val PRIORITY_NORMAL = 1
        private const val STATUS_SUCCESS = 0
        private const val MAX_SOUND_STREAMS = 24
        private const val STREAM_CLEANUP_PADDING_MS = 32L
        private const val DEFAULT_STREAM_DURATION_MS = 4000L
    }
}

private const val TAG = "FlashlightsClient"
