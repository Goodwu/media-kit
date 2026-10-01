package com.example.media_kit_hdr_lab

import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.view.PixelCopy
import android.view.MotionEvent
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.util.Log
import com.alexmercerind.media_kit_android_dataspace_vendor.LyaPqDataSpaceExt
import com.alexmercerind.media_kit_android_dataspace_vendor.MediaKitAndroidDataspaceVendorPlugin
import com.alexmercerind.media_kit_video.platformview.PlatformVideoView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private var firstFrameProbeGeneration = 0
    private var lastTouchDownNs = 0L
    private var lastTouchUpNs = 0L

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> lastTouchDownNs = SystemClock.elapsedRealtimeNanos()
            MotionEvent.ACTION_UP -> lastTouchUpNs = SystemClock.elapsedRealtimeNanos()
        }
        return super.dispatchTouchEvent(event)
    }

    private fun startFirstFrameProbe(platformVideo: Boolean): Map<String, Any> {
        check(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) { "PixelCopy requires API 26" }
        val generation = ++firstFrameProbeGeneration
        val startedNs = SystemClock.elapsedRealtimeNanos()
        val touchDownNs = lastTouchDownNs.takeIf { startedNs - it in 0L..2_000_000_000L }
        val touchUpNs = lastTouchUpNs.takeIf { startedNs - it in 0L..2_000_000_000L }
        val handler = Handler(Looper.getMainLooper())
        var samples = 0
        var nonblackLogged = false
        var contentLogged = false
        var selectedIdentity = 0
        Log.i("FirstFramePixelCopy", "start generation=$generation ns=$startedNs " +
            "touchDownNs=$touchDownNs touchUpNs=$touchUpNs " +
            "target=${if (platformVideo) "platform" else "flutter"}")

        fun sample() {
            if (generation != firstFrameProbeGeneration || contentLogged ||
                SystemClock.elapsedRealtimeNanos() - startedNs > 9_000_000_000L) {
                Log.i("FirstFramePixelCopy", "finish generation=$generation samples=$samples " +
                    "nonblack=$nonblackLogged content=$contentLogged")
                return
            }
            val target = if (platformVideo) findPlatformVideoSurface(window.decorView)
                else findFlutterSurface(window.decorView)
            if (target == null || !target.holder.surface.isValid ||
                target.width < 400 || target.height < 250 ||
                (platformVideo && (window.decorView.width <= window.decorView.height ||
                    target.width < window.decorView.width / 2))) {
                handler.postDelayed({ sample() }, 40)
                return
            }
            val identity = System.identityHashCode(target)
            if (identity != selectedIdentity) {
                selectedIdentity = identity
                Log.i("FirstFramePixelCopy", "target_selected generation=$generation " +
                    "viewIdentity=$identity parent=${target.parent?.javaClass?.name} " +
                    "size=${target.width}x${target.height}")
            }
            // The native P5 fixture opens on a nearly uniform sky. Sample
            // its whole video Surface so a center crop cannot miss the first
            // recognizable picture; keep the Flutter crop free of page UI.
            val rect = if (platformVideo) Rect(0, 0, target.width, target.height)
                else Rect(
                    target.width / 2 - 200, target.height / 4 - 125,
                    target.width / 2 + 200, target.height / 4 + 125
                )
            if (rect.left < 0 || rect.top < 0 || rect.right > target.width ||
                rect.bottom > target.height) {
                handler.postDelayed({ sample() }, 40)
                return
            }
            val bitmap = Bitmap.createBitmap(64, 40, Bitmap.Config.ARGB_8888)
            try {
                PixelCopy.request(target.holder.surface, rect, bitmap, { status ->
                    val capturedNs = SystemClock.elapsedRealtimeNanos()
                    if (status != PixelCopy.SUCCESS) {
                        Log.w("FirstFramePixelCopy", "copy_failed generation=$generation " +
                            "status=$status samples=$samples")
                        bitmap.recycle()
                        handler.postDelayed({ sample() }, 40)
                        return@request
                    }
                    val pixels = IntArray(bitmap.width * bitmap.height)
                    bitmap.getPixels(pixels, 0, bitmap.width, 0, 0,
                        bitmap.width, bitmap.height)
                    bitmap.recycle()
                    var sum = 0.0
                    var sumSquares = 0.0
                    for (pixel in pixels) {
                        val r = (pixel ushr 16) and 255
                        val g = (pixel ushr 8) and 255
                        val b = pixel and 255
                        val brightness = (r + g + b) / 3.0
                        sum += brightness
                        sumSquares += brightness * brightness
                    }
                    samples++
                    val mean = sum / pixels.size
                    val spread = kotlin.math.sqrt(
                        (sumSquares / pixels.size - mean * mean).coerceAtLeast(0.0))
                    val elapsedMs = (capturedNs - startedNs) / 1_000_000.0
                    if (samples == 1) {
                        Log.i("FirstFramePixelCopy", "baseline generation=$generation " +
                            "elapsedMs=$elapsedMs mean=$mean spread=$spread " +
                            "target=${target.javaClass.name} rect=$rect")
                    }
                    if (!nonblackLogged && mean > 1.0 && spread > 1.0) {
                        nonblackLogged = true
                        Log.i("FirstFramePixelCopy", "first_nonblack generation=$generation " +
                            "elapsedMs=$elapsedMs sample=$samples mean=$mean spread=$spread")
                    }
                    if (!contentLogged && mean > 20.0 && spread > 10.0) {
                        contentLogged = true
                        val touchToContentMs = touchUpNs?.let {
                            (capturedNs - it) / 1_000_000.0
                        }
                        val touchDownToContentMs = touchDownNs?.let {
                            (capturedNs - it) / 1_000_000.0
                        }
                        Log.i("FirstFramePixelCopy", "first_content generation=$generation " +
                            "elapsedMs=$elapsedMs touchToContentMs=$touchToContentMs " +
                            "touchDownToContentMs=$touchDownToContentMs " +
                            "sample=$samples mean=$mean spread=$spread " +
                            "target=${target.javaClass.name} rect=$rect")
                    }
                    handler.postDelayed({ sample() }, 80)
                }, handler)
            } catch (error: Exception) {
                bitmap.recycle()
                Log.w("FirstFramePixelCopy", "copy_exception generation=$generation $error")
                handler.postDelayed({ sample() }, 40)
            }
        }
        sample()
        return mapOf("generation" to generation, "startedElapsedRealtimeNs" to startedNs)
    }

    private fun readSystemProperty(key: String): String {
        val process = ProcessBuilder("/system/bin/getprop", key).start()
        if (!process.waitFor(2, TimeUnit.SECONDS)) {
            process.destroyForcibly()
            throw IllegalStateException("getprop timed out: $key")
        }
        if (process.exitValue() != 0) {
            throw IllegalStateException("getprop failed: $key")
        }
        return process.inputStream.bufferedReader().use { it.readText().trim() }
    }

    private fun findFlutterSurface(view: View): SurfaceView? {
        if (view is SurfaceView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                findFlutterSurface(view.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    private fun findPlatformVideoSurface(view: View): SurfaceView? {
        var best: SurfaceView? = null
        if (view is SurfaceView && view.javaClass.name == "android.view.SurfaceView" &&
            view.isShown) best = view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val candidate = findPlatformVideoSurface(view.getChildAt(i)) ?: continue
                // The fullscreen PlatformView is inserted after Flutter's
                // SurfaceView; equal-sized views must select the newer one.
                if (best == null || candidate.width * candidate.height >=
                    best.width * best.height) best = candidate
            }
        }
        return best
    }

    private fun pixelHash(bitmap: Bitmap): String {
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        var hash = 2166136261L
        for (pixel in pixels) hash = ((hash xor pixel.toLong()) * 16777619L) and 0xffffffffL
        return hash.toString(16)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The vendor dataspace fallback (LYA-AL00 private ABI) registers
        // itself through the media_kit_android_dataspace_vendor plugin
        // during super.configureFlutterEngine, gated by the plugin's
        // read-only applicability check. For diagnostics, hdr_lab takes the
        // single core slot over with a wrapper that chains the three probes
        // onto the same extension point; apply stays delegated to the
        // vendor extension. takeOverSlot() tells the plugin the app now
        // owns the slot so engine detach will not clear the wrapper.
        // PluginRegistry.get returns the non-generic FlutterPlugin type in
        // this embedding; narrow it back to the vendor plugin explicitly.
        val vendorPlugin = flutterEngine.plugins
            .get(MediaKitAndroidDataspaceVendorPlugin::class.java) as?
            MediaKitAndroidDataspaceVendorPlugin
        val vendorExt = vendorPlugin?.registeredExtension() ?: LyaPqDataSpaceExt()
        vendorPlugin?.takeOverSlot()
        PlatformVideoView.setSurfaceDataSpaceExt(LyaDiagnosticsDataSpaceExt(vendorExt))
        CapabilitiesChannel.register(this, flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "media_kit_hdr_lab/engine_control")
            .setMethodCallHandler { call, result ->
                if (call.method != "DestroyEngineNow") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // Reply before destroying: the engine owns the messenger this
                // reply travels on, and the Dart side may already be torn down.
                result.success(null)
                // Never destroy the engine reentrantly from inside a channel
                // dispatch. Post the destroy so the current platform message
                // finishes and queued Dart continuations settle first; tearing
                // down mid-dispatch races native producers against freed
                // engine state.
                Handler(Looper.getMainLooper()).postDelayed(
                    {
                        Log.i("EngineControl", "destroy_begin")
                        flutterEngine.destroy()
                        Log.i("EngineControl", "destroy_complete")
                    },
                    50,
                )
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "media_kit_hdr_lab/p5_runtime_gate")
            .setMethodCallHandler { call, result ->
                if (call.method != "ReadProperties") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val values = mapOf(
                            "debug.media_kit.p5_rpu_probe" to
                                readSystemProperty("debug.media_kit.p5_rpu_probe"),
                            "debug.media_kit.p5_raw_yuv" to
                                readSystemProperty("debug.media_kit.p5_raw_yuv"),
                            "debug.media_kit.firstframe_prebind" to
                                readSystemProperty("debug.media_kit.firstframe_prebind")
                        )
                        runOnUiThread { result.success(values) }
                    } catch (error: Exception) {
                        runOnUiThread {
                            result.error("P5_PROPERTIES_UNAVAILABLE", error.toString(), null)
                        }
                    }
                }.start()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "media_kit_hdr_lab/flutter_surface_probe")
            .setMethodCallHandler { call, result ->
                if (call.method == "SetShortEdges") {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        val attributes = window.attributes
                        attributes.layoutInDisplayCutoutMode =
                            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                        window.attributes = attributes
                    }
                    result.success(null)
                    return@setMethodCallHandler
                }
                if (call.method == "StartFirstFrameProbe") {
                    try {
                        result.success(startFirstFrameProbe(call.argument<String>("target") == "platform"))
                    } catch (error: Exception) {
                        result.error("PROBE_FAILED", error.toString(), null)
                    }
                    return@setMethodCallHandler
                }
                if (call.method == "GetThermalStatus") {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val power = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(power.currentThermalStatus)
                    } else {
                        result.success(null)
                    }
                    return@setMethodCallHandler
                }
                if (call.method != "CopyVideoPixels") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    result.error("UNSUPPORTED", "PixelCopy requires API 26", null)
                    return@setMethodCallHandler
                }
                val surface = findFlutterSurface(window.decorView)
                val rect = Rect(0, 370, 1440, 1090)
                val bitmap = Bitmap.createBitmap(144, 72, Bitmap.Config.ARGB_8888)
                val callback = PixelCopy.OnPixelCopyFinishedListener { status ->
                    if (status == PixelCopy.SUCCESS) {
                        result.success("${if (surface == null) "window" else "surface"}:${pixelHash(bitmap)}")
                    } else {
                        result.error("COPY_FAILED", "PixelCopy status $status", null)
                    }
                    bitmap.recycle()
                }
                if (surface == null) {
                    Log.w("FlutterSurfaceProbe", "No SurfaceView in decor: ${window.decorView.javaClass.name}; using Window PixelCopy")
                    PixelCopy.request(window, rect, bitmap, callback, Handler(Looper.getMainLooper()))
                } else {
                    PixelCopy.request(surface, rect, bitmap, callback, Handler(Looper.getMainLooper()))
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "media_kit_hdr_lab/p5_codec_probe")
            .setMethodCallHandler { call, result ->
                if (call.method != "Run") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val maxFrames = call.argument<Int>("maxFrames") ?: 250
                val surfaceMode = call.argument<Boolean>("surfaceMode") ?: false
                val cpuRead = call.argument<Boolean>("cpuRead") ?: false
                val gpuImport = call.argument<Boolean>("gpuImport") ?: false
                val readerWidth = call.argument<Int>("readerWidth") ?: 0
                val readerHeight = call.argument<Int>("readerHeight") ?: 0
                val readerMaxImages = call.argument<Int>("readerMaxImages") ?: 0
                val nativeReaderMode = call.argument<Boolean>("nativeReaderMode") ?: false
                val deferredAcquire = call.argument<Boolean>("deferredAcquire") ?: false
                val holdPreviousImage = call.argument<Boolean>("holdPreviousImage") ?: false
                if (path.isNullOrEmpty() || maxFrames < 1) {
                    result.error("INVALID_ARGUMENT", "path and maxFrames are required", null)
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val report = P5CodecProbe.run(
                            path, maxFrames, surfaceMode, cpuRead, gpuImport,
                            readerWidth, readerHeight, readerMaxImages,
                            nativeReaderMode, deferredAcquire, holdPreviousImage
                        )
                        runOnUiThread { result.success(report) }
                    } catch (error: Exception) {
                        runOnUiThread {
                            result.error("PROBE_FAILED", error.toString(), null)
                        }
                    }
                }.start()
            }
    }
}
