/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.content.Context;
import android.hardware.display.DisplayManager;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;
import android.os.Build;
import android.util.Log;
import android.util.Range;
import android.view.Display;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.alexmercerind.media_kit_video.platformview.PlatformVideoView;

/**
 * HdrCapabilities
 *
 * Pre-playback device capability snapshot for HDR output planning, served to
 * Dart through the {@code HdrCapabilities.Get} channel method and re-sent on
 * {@code HdrCapabilities.Changed}.
 *
 * Reads public system APIs only: {@link Display.HdrCapabilities} for the
 * default display and {@link MediaCodecList}/{@link android.media.CodecCapabilities}
 * for the decoder census. It never calls eglInitialize/eglTerminate (which
 * would interfere with other EGL users in the process) and never touches any
 * private vendor ABI — a registered SurfaceDataSpaceExt is only described
 * through its read-only {@code id()}/{@code isApplicable()} accessors.
 */
public final class HdrCapabilities {
    private static final String TAG = "HdrCapabilities";

    private static final String MIMETYPE_DOLBY_VISION = "video/dolby-vision";
    private static final int WIDTH_4K = 3840;
    private static final int HEIGHT_4K = 2160;

    private HdrCapabilities() {}

    /**
     * Builds the capability snapshot.
     *
     * {@code displayHdrTypes} is null when the default display reports no HDR
     * capability at all (SDR panel, headless display); the key is always
     * present with an explicit value. Dolby Vision decoders are reported
     * as-is — an empty list simply means the device offers none.
     *
     * {@code p5Pipeline} answers whether the loaded mpv fork carries the P5
     * dovi rescale pipeline. The source is the disposable mpv instance probe
     * run once through the bridge at engine attach (plan B, 2026-10-02) —
     * not option introspection. {@code probeOnce} is idempotent, so this
     * fallback also covers an attach path that skipped the probe; the
     * three-state verdict is consumed conservatively (-1 → false).
     * {@code nativeDvBridgeApi} is the independent static bridge schema
     * version (1 supported, otherwise 0), read from the same cached probe.
     * Neither field establishes visible HDR or native DV playback acceptance.
     */
    @NonNull
    public static Map<String, Object> get(@NonNull Context context) {
        final Map<String, Object> snapshot = new HashMap<>();
        snapshot.put("sdkInt", Build.VERSION.SDK_INT);
        snapshot.put("displayHdrTypes", displayHdrTypes(context));
        snapshot.put("hevcDecoders", decoders(MediaFormat.MIMETYPE_VIDEO_HEVC));
        snapshot.put("dolbyVisionDecoders", decoders(MIMETYPE_DOLBY_VISION));
        snapshot.put("p5Pipeline", MpvPipelineProbe.probeOnce() == 1);
        snapshot.put("nativeDvBridgeApi", MpvPipelineProbe.getNativeDvBridgeApi());
        snapshot.put("dataSpaceBridgeLoaded", PlatformVideoView.isDataSpaceBridgeLoaded());
        snapshot.put("dataSpaceExt", PlatformVideoView.getSurfaceDataSpaceExtInfo());
        return snapshot;
    }

    @Nullable
    private static List<Integer> displayHdrTypes(@Nullable Context context) {
        if (context == null) {
            return null;
        }
        final DisplayManager displayManager = (DisplayManager)
                context.getSystemService(Context.DISPLAY_SERVICE);
        if (displayManager == null) {
            return null;
        }
        final Display display = displayManager.getDisplay(Display.DEFAULT_DISPLAY);
        if (display == null) {
            return null;
        }
        final Display.HdrCapabilities hdrCapabilities = display.getHdrCapabilities();
        if (hdrCapabilities == null) {
            return null;
        }
        final int[] types = hdrCapabilities.getSupportedHdrTypes();
        if (types == null) {
            return null;
        }
        final List<Integer> reported = new ArrayList<>(types.length);
        for (final int type : types) {
            reported.add(type);
        }
        return reported;
    }

    @NonNull
    private static List<Map<String, Object>> decoders(@NonNull String mimeType) {
        final List<Map<String, Object>> result = new ArrayList<>();
        final MediaCodecInfo[] infos;
        try {
            infos = new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos();
        } catch (Throwable error) {
            Log.w(TAG, "MediaCodecList unavailable: " + error);
            return result;
        }
        for (final MediaCodecInfo info : infos) {
            if (info.isEncoder() || !supports(info, mimeType)) {
                continue;
            }
            result.add(decoderInfo(info, mimeType));
        }
        return result;
    }

    private static boolean supports(@NonNull MediaCodecInfo info, @NonNull String mimeType) {
        try {
            return info.getCapabilitiesForType(mimeType) != null;
        } catch (IllegalArgumentException error) {
            return false;
        }
    }

    @NonNull
    private static Map<String, Object> decoderInfo(
            @NonNull MediaCodecInfo info, @NonNull String mimeType) {
        final Map<String, Object> map = new HashMap<>();
        map.put("name", info.getName());
        map.put("mimeType", mimeType);
        map.put("hardwareAcceleration", isHardwareAccelerated(info));

        final MediaCodecInfo.CodecCapabilities capabilities;
        try {
            capabilities = info.getCapabilitiesForType(mimeType);
        } catch (IllegalArgumentException error) {
            return map;
        }
        if (capabilities == null) {
            return map;
        }
        map.put("profiles", profiles(capabilities));
        if (MediaFormat.MIMETYPE_VIDEO_HEVC.equals(mimeType)) {
            map.put("main10", supportsMain10(capabilities));
        }
        putVideoTier(map, capabilities.getVideoCapabilities());
        return map;
    }

    private static boolean isHardwareAccelerated(@NonNull MediaCodecInfo info) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return info.isHardwareAccelerated();
        }
        // API < 29 has no authoritative flag: treat the known software codec
        // naming schemes (Codec2 default and Google OMX) as software and
        // everything else as hardware. This is a best-effort fallback.
        final String name = info.getName();
        return !name.startsWith("c2.android") && !name.startsWith("OMX.google");
    }

    private static boolean supportsMain10(@NonNull MediaCodecInfo.CodecCapabilities capabilities) {
        final MediaCodecInfo.CodecProfileLevel[] levels = capabilities.profileLevels;
        if (levels == null) {
            return false;
        }
        for (final MediaCodecInfo.CodecProfileLevel level : levels) {
            if (level == null) {
                continue;
            }
            switch (level.profile) {
                case MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10:
                case MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10:
                case MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10Plus:
                    return true;
                default:
                    break;
            }
        }
        return false;
    }

    @NonNull
    private static List<Integer> profiles(@NonNull MediaCodecInfo.CodecCapabilities capabilities) {
        final List<Integer> result = new ArrayList<>();
        final MediaCodecInfo.CodecProfileLevel[] levels = capabilities.profileLevels;
        if (levels == null) {
            return result;
        }
        for (final MediaCodecInfo.CodecProfileLevel level : levels) {
            if (level != null && !result.contains(level.profile)) {
                result.add(level.profile);
            }
        }
        return result;
    }

    /**
     * Reports the {@link android.media.VideoCapabilities} size/rate ranges and
     * the 4K tier (whether 3840x2160 is a supported size and the highest
     * frame rate supported at it). Unsupported sizes yield
     * {@code supports4K=false} with a null {@code max4KFps}.
     */
    private static void putVideoTier(
            @NonNull Map<String, Object> map,
            @Nullable MediaCodecInfo.VideoCapabilities video) {
        if (video == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            map.put("widthRange", null);
            map.put("heightRange", null);
            map.put("frameRateRange", null);
            map.put("supports4K", false);
            map.put("max4KFps", null);
            return;
        }
        try {
            map.put("widthRange", rangeToList(video.getSupportedWidths()));
            map.put("heightRange", rangeToList(video.getSupportedHeights()));
            map.put("frameRateRange", rangeToList(video.getSupportedFrameRates()));
        } catch (Throwable error) {
            Log.w(TAG, "video capability ranges unavailable: " + error);
            map.put("widthRange", null);
            map.put("heightRange", null);
            map.put("frameRateRange", null);
        }
        try {
            final Range<Double> at4K = video.getSupportedFrameRatesFor(WIDTH_4K, HEIGHT_4K);
            final double max4KFps = at4K.getUpper();
            map.put("supports4K", max4KFps > 0);
            map.put("max4KFps", max4KFps);
        } catch (Throwable error) {
            // IllegalArgumentException: 4K is not a supported size at all.
            map.put("supports4K", false);
            map.put("max4KFps", null);
        }
    }

    @NonNull
    private static List<Integer> rangeToList(@NonNull Range<Integer> range) {
        final List<Integer> list = new ArrayList<>(2);
        list.add(range.getLower());
        list.add(range.getUpper());
        return list;
    }
}
