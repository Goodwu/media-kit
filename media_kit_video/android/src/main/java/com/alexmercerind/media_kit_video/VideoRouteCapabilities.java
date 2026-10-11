package com.alexmercerind.media_kit_video;

import android.content.Context;
import android.hardware.display.DisplayManager;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;
import android.os.Build;
import android.view.Display;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Read-only source/target capabilities; never creates MediaCodec or output. */
final class VideoRouteCapabilities {
    private VideoRouteCapabilities() {}

    static Map<String, Object> get(Context context, Display applicationDisplay, Map<?, ?> request) {
        if (request == null || !Integer.valueOf(1).equals(request.get("schema")) ||
                !(request.get("sources") instanceof List)) throw new IllegalArgumentException("Invalid query schema");
        List<?> rawSources = (List<?>) request.get("sources");
        if (rawSources.size() > 128) throw new IllegalArgumentException("Too many source specifications");
        List<VideoSourceSpec> specs = new ArrayList<>();
        for (Object raw : rawSources) {
            if (!(raw instanceof Map)) throw new IllegalArgumentException("Invalid source specification");
            specs.add(new VideoSourceSpec((Map<?, ?>) raw));
        }
        Display targetDisplay = resolveDisplay(context, applicationDisplay, request.get("target"));
        Map<String, Object> display = describeDisplay(targetDisplay,
                request.get("target") == null ? "notRequested" : "unresolved");
        Map<String, Object> result = new HashMap<>();
        result.put("schema", 1); result.put("platform", "android");
        result.put("display", display);
        // Reuse the existing read-only runtime probe and HDR value model.
        result.put("hdr", HdrCapabilities.get(context, targetDisplay));
        MediaCodecInfo[] infos = new MediaCodecInfo[0];
        boolean censusComplete = true;
        try {
            if (!specs.isEmpty()) infos = new MediaCodecList(MediaCodecList.REGULAR_CODECS).getCodecInfos();
        } catch (RuntimeException | LinkageError e) { censusComplete = false; }
        List<Map<String, Object>> matches = new ArrayList<>();
        for (VideoSourceSpec spec : specs) {
            List<Map<String, Object>> decoders = new ArrayList<>();
            boolean complete = censusComplete && spec.mime != null;
            for (MediaCodecInfo info : infos) {
                try {
                    if (info.isEncoder()) continue;
                    if (contains(info.getSupportedTypes(), spec.mime)) {
                        decoders.add(probe(info, spec, false));
                    }
                    if (spec.dvProfile != null && contains(info.getSupportedTypes(), "video/dolby-vision")) {
                        decoders.add(probe(info, spec, true));
                    }
                } catch (RuntimeException | LinkageError e) { complete = false; }
            }
            Map<String, Object> match = new HashMap<>();
            match.put("key", spec.key); match.put("censusComplete", complete);
            match.put("reason", complete ? "systemDeclarations" : "capabilitiesUnavailable");
            match.put("decoders", decoders); matches.add(match);
        }
        result.put("sources", matches);
        // A mode switch during collection must not turn an old target into
        // a fresh complete snapshot. Decode results remain target-independent.
        if (targetDisplay != null && !display.equals(describeDisplay(targetDisplay, "unresolved"))) {
            result.put("display", describeDisplay(null, "changedDuringQuery"));
        }
        return result;
    }

    private static boolean contains(String[] values, String target) {
        if (target == null) return false;
        for (String value : values) if (target.equalsIgnoreCase(value)) return true;
        return false;
    }

    private static Display resolveDisplay(Context context, Display appDisplay, Object raw) {
        if (raw == null) return null;
        if (!(raw instanceof Map)) throw new IllegalArgumentException("Invalid output target");
        Map<?, ?> target = (Map<?, ?>) raw;
        Object kind = target.get("kind");
        if ("applicationView".equals(kind)) return appDisplay;
        if ("flutterView".equals(kind)) {
            // The first adapter is implicit-view only. The plugin resolves
            // the unique native FlutterView bound to THIS messenger, never
            // by treating a Flutter ID as an OS ID.
            return Boolean.TRUE.equals(target.get("live")) && Boolean.TRUE.equals(target.get("implicit"))
                    ? appDisplay : null;
        }
        if (!"defaultDisplay".equals(kind) && !"nativeDisplay".equals(kind))
            throw new IllegalArgumentException("Unknown target kind");
        if ("nativeDisplay".equals(kind) && !"android".equals(target.get("platform"))) return null;
        Integer id = "defaultDisplay".equals(kind) ? Display.DEFAULT_DISPLAY :
                VideoSourceSpec.integer(target.get("displayId"), 0);
        if (id == null) throw new IllegalArgumentException("Missing display ID");
        DisplayManager manager = (DisplayManager) context.getSystemService(Context.DISPLAY_SERVICE);
        return manager == null ? null : manager.getDisplay(id);
    }

    private static Map<String, Object> describeDisplay(Display display, String unresolved) {
        Map<String, Object> result = new HashMap<>();
        result.put("platform", "android");
        if (display == null || !display.isValid()) { result.put("status", unresolved); return result; }
        try {
            int modeId = Build.VERSION.SDK_INT >= 23 ? display.getMode().getModeId() : 0;
            int[] types = Build.VERSION.SDK_INT >= 34 ? display.getMode().getSupportedHdrTypes() :
                    (Build.VERSION.SDK_INT >= 24 ? display.getHdrCapabilities().getSupportedHdrTypes() : null);
            List<Integer> hdr = null;
            if (types != null) {
                hdr = new ArrayList<>(); for (int type : types) hdr.add(type);
            }
            result.put("status", "resolved"); result.put("displayId", display.getDisplayId());
            result.put("modeId", modeId); result.put("hdrTypes", hdr);
            result.put("revision", display.getDisplayId() + ":" + modeId + ":" + display.getRefreshRate() + ":" + hdr);
        } catch (RuntimeException | LinkageError e) { result.clear(); result.put("status", "queryUnavailable"); }
        return result;
    }

    private static Map<String, Object> probe(MediaCodecInfo info, VideoSourceSpec spec, boolean nativeDv) {
        Map<String, Object> result = new HashMap<>();
        String mime = nativeDv ? "video/dolby-vision" : spec.mime;
        result.put("name", info.getName()); result.put("mime", mime);
        result.put("path", nativeDv ? "nativeDv" : "codec");
        result.put("kind", decoderKind(info));
        String verdict;
        try { verdict = evaluate(info.getCapabilitiesForType(mime), spec, mime, nativeDv); }
        catch (RuntimeException | LinkageError e) { verdict = "unknown:queryFailed"; }
        int split = verdict.indexOf(':');
        result.put("support", verdict.substring(0, split)); result.put("reason", verdict.substring(split + 1));
        return result;
    }

    private static String decoderKind(MediaCodecInfo info) {
        if (Build.VERSION.SDK_INT >= 29) {
            if (info.isSoftwareOnly()) return "software";
            if (info.isHardwareAccelerated()) return "hardware";
        }
        String name = info.getName();
        if (name.startsWith("OMX.google.") || name.startsWith("c2.android.") ||
                name.startsWith("OMX.ffmpeg.") || name.equals("OMX.qcom.video.decoder.hevcswvdec")) return "software";
        return "unknown"; // Pre-29 vendor naming is not authoritative hardware evidence.
    }

    private static String evaluate(MediaCodecInfo.CodecCapabilities caps, VideoSourceSpec s, String mime, boolean nativeDv) {
        if (caps == null) return "unknown:missingCodecCapabilities";
        if (caps.isFeatureRequired(MediaCodecInfo.CodecCapabilities.FEATURE_SecurePlayback) ||
                caps.isFeatureRequired(MediaCodecInfo.CodecCapabilities.FEATURE_TunneledPlayback))
            return "unsupported:requiresUnrequestedCodecFeature";
        MediaCodecInfo.VideoCapabilities video = caps.getVideoCapabilities();
        if (video == null) return "unknown:missingVideoCapabilities";
        if (s.width != null && s.height != null) {
            // Explicit joint query, also on API21 where isFormatSupported
            // ignores/rejects frame-rate keys. Never combine independent maxima.
            boolean fits = s.frameRate == null ? video.isSizeSupported(s.width, s.height) :
                    video.areSizeAndRateSupported(s.width, s.height, s.frameRate);
            if (!fits) return "unsupported:sizeAndRate";
        }
        if (s.bitrate != null && !video.getBitrateRange().contains(s.bitrate)) return "unsupported:bitrate";
        int profile = androidProfile(s, nativeDv);
        if (profile < 0 || !s.mapped) return "unknown:unmappedCodecProfile";
        if (caps.profileLevels == null || caps.profileLevels.length == 0) return "unknown:missingProfileLevels";
        boolean foundProfile = false, foundLevel = false, unknownLevel = false;
        int requestedLevel = nativeDv ? (s.dvLevel == null ? -1 : s.dvLevel) : (s.level == null ? -1 : s.level);
        for (MediaCodecInfo.CodecProfileLevel entry : caps.profileLevels) {
            if (!compatibleProfile(mime, profile, entry.profile)) continue;
            foundProfile = true;
            int accepted = levelSupports(mime, entry.level, requestedLevel, Boolean.TRUE.equals(s.highTier));
            foundLevel |= accepted > 0; unknownLevel |= accepted < 0;
        }
        if (!foundProfile) return "unsupported:profile";
        if (!foundLevel && !unknownLevel) return "unsupported:levelOrTier";
        if (!depthMatches(s, nativeDv)) return "unknown:unmappedBitDepth";
        if (!s.complete() || !foundLevel) return "unknown:incompleteSpecification";
        MediaFormat format = new MediaFormat(); format.setString(MediaFormat.KEY_MIME, mime);
        if (s.width != null) format.setInteger(MediaFormat.KEY_WIDTH, s.width);
        if (s.height != null) format.setInteger(MediaFormat.KEY_HEIGHT, s.height);
        // Profile and bitrate were checked explicitly; on old SDKs the
        // framework ignores these. LEVEL is decoder-ignored on several SDKs.
        format.setInteger(MediaFormat.KEY_PROFILE, profile);
        if (!caps.isFormatSupported(format)) return "unsupported:format";
        return "supported:declaredSupportOnly";
    }

    private static boolean depthMatches(VideoSourceSpec s, boolean nativeDv) {
        if (s.bitDepth == null) return true; // Profile/level still checked; no depth was requested.
        if (nativeDv) return s.bitDepth == 10;
        if ("video/hevc".equals(s.mime)) return s.profile == 1 ? s.bitDepth == 8 : s.profile == 2 && (s.bitDepth == 8 || s.bitDepth == 10);
        if ("video/av01".equals(s.mime)) return s.bitDepth == 8 || s.bitDepth == 10;
        if ("video/x-vnd.on2.vp9".equals(s.mime)) return s.profile < 2 ? s.bitDepth == 8 : s.bitDepth == 10 || s.bitDepth == 12;
        if ("video/avc".equals(s.mime)) return s.profile == 110 ? s.bitDepth <= 10 : s.profile <= 100 && s.bitDepth == 8;
        return false;
    }

    private static int androidProfile(VideoSourceSpec s, boolean nativeDv) {
        if (nativeDv) return s.dvProfile == null ? -1 : s.dvProfile == 5 ? 32 : s.dvProfile == 8 ? 256 : -1;
        if (s.profile == null) return -1;
        switch (s.mime) {
            case "video/avc":
                switch (s.profile) { case 66: return 1; case 77: return 2; case 88: return 4;
                    case 100: return 8; case 110: return 16; case 122: return 32; case 244: return 64; default: return -1; }
            case "video/hevc": return s.profile == 1 ? 1 : s.profile == 2 ? 2 : s.profile == 3 ? 4 : -1;
            case "video/x-vnd.on2.vp9": return s.profile <= 3 ? 1 << s.profile : -1;
            case "video/av01": return s.profile == 0 && s.bitDepth != null ? (s.bitDepth == 8 ? 1 : s.bitDepth == 10 ? 2 : -1) : -1;
            default: return -1;
        }
    }

    private static boolean compatibleProfile(String mime, int wanted, int offered) {
        if (wanted == offered) return true;
        // HDR profile variants include the same underlying bit depth/profile.
        if ("video/hevc".equals(mime) && wanted == 2) return offered == 4096 || offered == 8192;
        if ("video/av01".equals(mime) && wanted == 2) return offered == 4096 || offered == 8192;
        if ("video/x-vnd.on2.vp9".equals(mime)) {
            if (wanted == 4) return offered == 4096 || offered == 16384;
            if (wanted == 8) return offered == 8192 || offered == 32768;
        }
        return false;
    }

    /** Compare semantic levels/tier, NOT Android integers across codecs. */
    static int levelSupports(String mime, int offered, int requested, boolean highTier) {
        if (requested < 0) return 1; // Only constraints actually supplied are checked.
        if (offered <= 0 || Integer.bitCount(offered) != 1) return -1;
        int bit = Integer.numberOfTrailingZeros(offered);
        int[] values;
        switch (mime) {
            case "video/hevc":
                values = new int[] {30,60,63,90,93,120,123,150,153,156,180,183,186};
                if (bit / 2 >= values.length) return -1;
                if (!has(values, requested)) return -1;
                return (values[bit / 2] >= requested && (!highTier || bit % 2 == 1)) ? 1 : 0;
            case "video/avc":
                values = new int[] {10,9,11,12,13,20,21,22,30,31,32,40,41,42,50,51,52,60,61,62};
                int requestedRank = index(values, requested);
                return bit >= values.length || requestedRank < 0 ? -1 : bit >= requestedRank ? 1 : 0;
            case "video/x-vnd.on2.vp9":
                values = new int[] {10,11,20,21,30,31,40,41,50,51,52,60,61,62};
                return bit >= values.length || !has(values, requested) ? -1 : values[bit] >= requested ? 1 : 0;
            case "video/av01":
                // MediaCodec does not expose separate AV1 tier capability.
                return highTier || bit > 23 || requested > 23 ? -1 : bit >= requested ? 1 : 0;
            case "video/dolby-vision":
                return bit > 12 || requested < 1 || requested > 13 ? -1 : bit + 1 >= requested ? 1 : 0;
            default: return -1;
        }
    }
    private static int index(int[] values, int wanted) { for (int i=0; i<values.length; i++) if(values[i]==wanted) return i; return -1; }
    private static boolean has(int[] values, int wanted) { return index(values,wanted)>=0; }
}
