package com.example.media_kit_test

import android.app.Activity
import android.media.MediaCodecList
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLDisplay
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Device capability inventory for experiment manifests, served from the test
 * app (moved out of the media_kit_video plugin: the library does not ship
 * device diagnostics).
 *
 * The EGL inventory calls eglInitialize/eglTerminate on the default display,
 * which can disturb other EGL users in this process — another reason it
 * belongs in a diagnostics app and not in the library.
 */
object CapabilitiesChannel {
    private const val CHANNEL = "media_kit_test/capabilities"

    fun register(activity: Activity, flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "Get") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    result.success(androidCapabilities(activity))
                } catch (error: Exception) {
                    result.error("CAPABILITIES_UNAVAILABLE", error.toString(), null)
                }
            }
    }

    private fun androidCapabilities(activity: Activity): Map<String, Any> {
        val result = mutableMapOf<String, Any>()
        result["sdkInt"] = Build.VERSION.SDK_INT
        val hdrTypes = mutableListOf<Int>()
        val windowManager = activity.getSystemService(Activity.WINDOW_SERVICE) as? WindowManager
        @Suppress("DEPRECATION")
        val display = windowManager?.defaultDisplay
        display?.hdrCapabilities?.supportedHdrTypes?.forEach { hdrTypes.add(it) }
        result["displayHdrTypes"] = hdrTypes
        result["egl"] = eglCapabilities()

        val hevcDecoders = mutableListOf<Map<String, Any?>>()
        for (codec in MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos) {
            if (codec.isEncoder) continue
            for (type in codec.supportedTypes) {
                if (!type.equals("video/hevc", ignoreCase = true)) continue
                val decoder = mutableMapOf<String, Any?>()
                decoder["name"] = codec.name
                decoder["type"] = type
                try {
                    val caps = codec.getCapabilitiesForType(type)
                    decoder["profiles"] = caps.profileLevels.map { it.profile }
                    decoder["maxInstances"] = caps.maxSupportedInstances
                    val video = caps.videoCapabilities
                    decoder["supports3840x2160p50"] = video != null &&
                        video.areSizeAndRateSupported(3840, 2160, 50.0)
                    decoder["supports3840x1920p2997"] = video != null &&
                        video.areSizeAndRateSupported(3840, 1920, 30000.0 / 1001.0)
                } catch (error: RuntimeException) {
                    decoder["capabilityError"] = error.javaClass.simpleName
                }
                hevcDecoders.add(decoder)
            }
        }
        result["hevcDecoders"] = hevcDecoders
        return result
    }

    /** A context-free EGL inventory. It does not prove a presentation path. */
    private fun eglCapabilities(): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>()
        val display: EGLDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        if (display == EGL14.EGL_NO_DISPLAY) {
            result["error"] = "EGL_NO_DISPLAY"
            return result
        }
        val version = IntArray(2)
        if (!EGL14.eglInitialize(display, version, 0, version, 1)) {
            result["error"] = "eglInitialize failed: ${EGL14.eglGetError()}"
            return result
        }
        try {
            result["version"] = "${version[0]}.${version[1]}"
            val extensions = EGL14.eglQueryString(display, EGL14.EGL_EXTENSIONS)
            result["extensions"] = extensions
            // A high-precision EGLConfig only selects the buffer format. The
            // Android EGL surface must also advertise a BT.2020 transfer
            // extension before libmpv can request that colorspace at creation.
            result["bt2020PqWindowSurface"] =
                extensions != null &&
                    extensions.contains("EGL_EXT_gl_colorspace_bt2020_pq")
            result["bt2020HlgWindowSurface"] =
                extensions != null &&
                    extensions.contains("EGL_EXT_gl_colorspace_bt2020_hlg")
            val count = IntArray(1)
            if (!EGL14.eglGetConfigs(display, null, 0, 0, count, 0)) {
                result["configError"] = "eglGetConfigs failed: ${EGL14.eglGetError()}"
                return result
            }
            val configs = arrayOfNulls<EGLConfig>(count[0])
            if (!EGL14.eglGetConfigs(display, configs, 0, configs.size, count, 0)) {
                result["configError"] = "eglGetConfigs list failed: ${EGL14.eglGetError()}"
                return result
            }
            val highPrecision = mutableListOf<Map<String, Any>>()
            val value = IntArray(1)
            for (i in 0 until count[0]) {
                if (!EGL14.eglGetConfigAttrib(display, configs[i], EGL14.EGL_RED_SIZE, value, 0)) continue
                val red = value[0]
                if (!EGL14.eglGetConfigAttrib(display, configs[i], EGL14.EGL_GREEN_SIZE, value, 0)) continue
                val green = value[0]
                if (!EGL14.eglGetConfigAttrib(display, configs[i], EGL14.EGL_BLUE_SIZE, value, 0)) continue
                val blue = value[0]
                if (!EGL14.eglGetConfigAttrib(display, configs[i], EGL14.EGL_ALPHA_SIZE, value, 0)) continue
                val alpha = value[0]
                if (red < 10 && green < 10 && blue < 10 && alpha < 16) continue
                highPrecision.add(
                    mapOf(
                        "index" to i,
                        "red" to red,
                        "green" to green,
                        "blue" to blue,
                        "alpha" to alpha,
                    )
                )
            }
            result["highPrecisionConfigs"] = highPrecision
        } finally {
            EGL14.eglTerminate(display)
        }
        return result
    }
}
