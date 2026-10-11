package com.alexmercerind.media_kit_video;

import java.util.Map;
import java.util.Locale;

/** Source constraints in bitstream units. Never a player, surface or URI. */
final class VideoSourceSpec {
    final String key;
    final String codec;
    String mime;
    final Integer width, height, bitrate;
    final Double frameRate;
    Integer profile, level, bitDepth;
    Boolean highTier;
    Integer dvProfile, dvLevel;
    boolean mapped = true;

    VideoSourceSpec(Map<?, ?> input) {
        key = text(input.get("key"), 1024);
        codec = text(input.get("codec"), 128).toLowerCase(Locale.ROOT);
        if (!codec.matches("[a-z0-9._-]+")) throw new IllegalArgumentException("Invalid codec");
        width = integer(input.get("width"), 1);
        height = integer(input.get("height"), 1);
        bitrate = integer(input.get("bitrate"), 1);
        frameRate = rate(input.get("frameRate"));
        profile = integer(input.get("profile"), 0);
        level = integer(input.get("level"), 0);
        bitDepth = integer(input.get("bitDepth"), 1);
        if (bitDepth != null && bitDepth > 32) throw new IllegalArgumentException("Invalid bit depth");
        Object tier = input.get("highTier");
        if (tier != null && !(tier instanceof Boolean)) throw new IllegalArgumentException("Invalid tier");
        highTier = (Boolean) tier;
        parseCodec();
    }

    private static String text(Object raw, int limit) {
        if (!(raw instanceof String) || ((String) raw).isEmpty() || ((String) raw).length() > limit)
            throw new IllegalArgumentException("Invalid source string");
        return (String) raw;
    }

    static Integer integer(Object raw, int min) {
        if (raw == null) return null;
        if (!(raw instanceof Integer) && !(raw instanceof Long)) throw new IllegalArgumentException("Expected integer");
        long value = ((Number) raw).longValue();
        if (value < min || value > Integer.MAX_VALUE) throw new IllegalArgumentException("Integer outside range");
        return (int) value;
    }

    private static Double rate(Object raw) {
        if (raw == null) return null;
        if (!(raw instanceof Number)) throw new IllegalArgumentException("Expected frame rate");
        double value = ((Number) raw).doubleValue();
        if (!Double.isFinite(value) || value <= 0) throw new IllegalArgumentException("Invalid frame rate");
        return value;
    }

    private Integer agree(Integer given, Integer parsed) {
        if (given != null && parsed != null && !given.equals(parsed))
            throw new IllegalArgumentException("Conflicting codec and source profile/level/depth");
        return given != null ? given : parsed;
    }

    private void parseCodec() {
        String[] p = codec.split("\\.", -1);
        try {
            switch (p[0]) {
                case "avc1": case "avc3": case "h264": case "avc":
                    mime = "video/avc";
                    if (p.length > 1) {
                        if (!p[1].matches("[0-9a-f]{6}")) { mapped = false; break; }
                        profile = agree(profile, Integer.parseInt(p[1].substring(0, 2), 16));
                        int flags = Integer.parseInt(p[1].substring(2, 4), 16);
                        int parsedLevel = Integer.parseInt(p[1].substring(4, 6), 16);
                        // AVC level 1b sorts between 1 and 1.1, not numerically.
                        if (parsedLevel == 11 && (flags & 16) != 0 &&
                                (profile == 66 || profile == 77 || profile == 88)) parsedLevel = 9;
                        level = agree(level, parsedLevel);
                    }
                    break;
                case "hvc1": case "hev1": case "hevc": case "h265":
                    mime = "video/hevc";
                    if (p.length > 1) {
                        // Nonzero profile spaces have different semantics.
                        if (!p[1].matches("[0-9]+") || p.length < 4 || !p[3].matches("[lh][0-9]+")) {
                            mapped = false; break;
                        }
                        profile = agree(profile, Integer.valueOf(p[1]));
                        level = agree(level, Integer.valueOf(p[3].substring(1)));
                        boolean parsedTier = p[3].charAt(0) == 'h';
                        if (highTier != null && highTier != parsedTier) throw new IllegalArgumentException("Conflicting tier");
                        highTier = parsedTier;
                    }
                    break;
                case "av01": case "av1":
                    mime = "video/av01";
                    if (p.length > 1) {
                        if (p.length < 4 || !p[2].matches("[0-9]{2}[mh]")) { mapped = false; break; }
                        profile = agree(profile, Integer.valueOf(p[1]));
                        level = agree(level, Integer.valueOf(p[2].substring(0, 2)));
                        bitDepth = agree(bitDepth, Integer.valueOf(p[3]));
                        boolean parsedTier = p[2].charAt(2) == 'h';
                        if (highTier != null && highTier != parsedTier) throw new IllegalArgumentException("Conflicting tier");
                        highTier = parsedTier;
                        // Optional chroma/color fields are not mapped by this adapter.
                        if (p.length > 4) mapped = false;
                    }
                    break;
                case "vp09": case "vp9":
                    mime = "video/x-vnd.on2.vp9";
                    if (p.length > 1) {
                        if (p.length < 4) { mapped = false; break; }
                        profile = agree(profile, Integer.valueOf(p[1]));
                        level = agree(level, Integer.valueOf(p[2]));
                        bitDepth = agree(bitDepth, Integer.valueOf(p[3]));
                        if (p.length > 4) mapped = false;
                    }
                    break;
                case "dvh1": case "dvhe":
                    mime = "video/hevc";
                    if (p.length != 3) { mapped = false; break; }
                    dvProfile = Integer.valueOf(p[1]); dvLevel = Integer.valueOf(p[2]);
                    if (dvProfile != 5 && dvProfile != 8) { mapped = false; break; }
                    if (profile != null || level != null) throw new IllegalArgumentException("DV codec string requires DV fields, not HEVC overrides");
                    // P5/P8 elementary-stream decoding is HEVC Main10; this
                    // alone says NOTHING about RPU processing or valid colors.
                    profile = 2;
                    bitDepth = agree(bitDepth, 10);
                    break;
                default: mapped = false;
            }
        } catch (NumberFormatException e) {
            mapped = false;
        }
    }

    boolean complete() {
        return mapped && mime != null && profile != null && (level != null || dvLevel != null) &&
                width != null && height != null && frameRate != null;
    }
}
