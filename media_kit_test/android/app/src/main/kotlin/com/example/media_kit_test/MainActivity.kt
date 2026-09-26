package com.example.media_kit_test

import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
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

    private fun pixelHash(bitmap: Bitmap): String {
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        var hash = 2166136261L
        for (pixel in pixels) hash = ((hash xor pixel.toLong()) * 16777619L) and 0xffffffffL
        return hash.toString(16)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "media_kit_test/p5_runtime_gate")
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
                                readSystemProperty("debug.media_kit.p5_raw_yuv")
                        )
                        runOnUiThread { result.success(values) }
                    } catch (error: Exception) {
                        runOnUiThread {
                            result.error("P5_PROPERTIES_UNAVAILABLE", error.toString(), null)
                        }
                    }
                }.start()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "media_kit_test/flutter_surface_probe")
            .setMethodCallHandler { call, result ->
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "media_kit_test/p5_codec_probe")
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
