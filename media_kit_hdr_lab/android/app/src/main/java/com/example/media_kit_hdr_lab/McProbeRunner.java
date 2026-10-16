package com.example.media_kit_hdr_lab;

import android.media.ImageReader;
import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;
import android.util.Log;
import android.view.Surface;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.ByteBuffer;

/**
 * Minimal MediaCodec probe for the app-uid experiment (marble 4K AVC).
 * Mirrors the shell McProbe: serial bounded instances, ClientFormat =
 * mime + width + height + csd only (no color-format), same as FFmpeg.
 * mode "buffer" = ByteBuffer mode; "direct" = ImageReader surface mode.
 * Streams come from assets (stream4k.h264 / stream720.h264).
 */
public final class McProbeRunner {
    private static void log(String s) { Log.i("MCPROBE", s); }

    private McProbeRunner() {}

    /** @param mode "buffer" | "direct"; @param streamAsset e.g. "stream4k.h264" */
    public static void run(
            final android.content.res.AssetManager assets,
            final String mode,
            final String streamAsset,
            final String codecName,
            final int width,
            final int height,
            final int maxInstances) {
        new Thread(new Runnable() {
            @Override public void run() {
                try {
                    runInner(assets, mode, streamAsset, codecName,
                            width, height, maxInstances);
                } catch (Throwable t) {
                    log("FATAL " + t);
                }
            }
        }, "McProbeRunner").start();
    }

    private static void runInner(
            android.content.res.AssetManager assets,
            String mode,
            String streamAsset,
            String codecName,
            int width,
            int height,
            int maxInstances) throws Exception {
        byte[] data = readAsset(assets, streamAsset);
        boolean direct = "direct".equals(mode);
        log("mode=" + mode + " stream=" + streamAsset + " bytes=" + data.length
                + " codec=" + codecName + " " + width + "x" + height
                + " pkg=" + McProbeApp.PKG);
        MediaCodecList list = new MediaCodecList(MediaCodecList.REGULAR_CODECS);
        for (MediaCodecInfo info : list.getCodecInfos()) {
            if (!info.getName().equals(codecName)) continue;
            MediaCodecInfo.CodecCapabilities cap =
                    info.getCapabilitiesForType("video/avc");
            log("caps: maxInstances=" + cap.getMaxSupportedInstances());
        }
        int[] sc = new int[3];
        int found = 0;
        for (int i = 0; i + 3 < data.length && found < 3; i++) {
            if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 0
                    && data[i + 3] == 1) sc[found++] = i;
        }
        if (found < 3) { log("FATAL: cannot parse Annex-B"); return; }
        byte[] csd0 = slice(data, sc[0], sc[1]);
        byte[] csd1 = slice(data, sc[1], sc[2]);
        log("csd0=" + csd0.length + "B csd1=" + csd1.length + "B");

        ImageReader reader = null;
        Surface surface = null;
        if (direct) {
            reader = ImageReader.newInstance(width, height,
                    android.graphics.ImageFormat.PRIVATE, 4);
            surface = reader.getSurface();
            log("DIRECT via ImageReader surface " + width + "x" + height);
        }
        try {
            int okInstances = 0;
            for (int inst = 1; inst <= maxInstances; inst++) {
                log("--- instance " + inst + " ---");
                long t0 = android.os.SystemClock.elapsedRealtime();
                MediaCodec codec = null;
                String verdict;
                try {
                    codec = MediaCodec.createByCodecName(codecName);
                    MediaFormat f = MediaFormat.createVideoFormat(
                            MediaFormat.MIMETYPE_VIDEO_AVC, width, height);
                    f.setByteBuffer("csd-0", ByteBuffer.wrap(csd0));
                    f.setByteBuffer("csd-1", ByteBuffer.wrap(csd1));
                    codec.configure(f, surface, null, 0);
                    log("configured" + (direct ? " (surface/direct)" : " (ByteBuffer)"));
                    codec.start();
                    log("started");
                    int inputOffset = sc[2];
                    boolean inputDone = false;
                    int frames = 0;
                    long deadline = android.os.SystemClock.elapsedRealtime() + 10000;
                    MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
                    while (android.os.SystemClock.elapsedRealtime() < deadline) {
                        if (!inputDone) {
                            int inIdx = codec.dequeueInputBuffer(10000);
                            if (inIdx >= 0) {
                                ByteBuffer ib = codec.getInputBuffer(inIdx);
                                ib.clear();
                                if (inputOffset >= data.length) {
                                    codec.queueInputBuffer(inIdx, 0, 0, 0,
                                            MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                                    inputDone = true;
                                    log("input EOS queued");
                                } else {
                                    int n = Math.min(ib.remaining(),
                                            data.length - inputOffset);
                                    ib.put(data, inputOffset, n);
                                    inputOffset += n;
                                    codec.queueInputBuffer(inIdx, 0, n,
                                            frames * 33333, 0);
                                }
                            }
                        }
                        int outIdx = codec.dequeueOutputBuffer(info, 10000);
                        if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                            MediaFormat of = codec.getOutputFormat();
                            log("OUTPUT_FORMAT_CHANGED: width="
                                    + of.getInteger(MediaFormat.KEY_WIDTH)
                                    + " height="
                                    + of.getInteger(MediaFormat.KEY_HEIGHT)
                                    + " colorFormat="
                                    + of.getInteger(MediaFormat.KEY_COLOR_FORMAT));
                        } else if (outIdx >= 0) {
                            frames++;
                            if (frames <= 3) log("frame " + frames + " size=" + info.size);
                            codec.releaseOutputBuffer(outIdx, false);
                            if (frames >= 30) { log("30 frames decoded"); break; }
                        }
                    }
                    verdict = (frames >= 1) ? "SUCCESS frames=" + frames
                            : "NO_OUTPUT (inputDone=" + inputDone + ")";
                } catch (MediaCodec.CodecException e) {
                    verdict = "CODEC_EXCEPTION errorCode=0x"
                            + Integer.toHexString(e.getErrorCode())
                            + " diagnostic=" + e.getDiagnosticInfo();
                    log(verdict + " transient=" + e.isTransient());
                } catch (Throwable t) {
                    verdict = "THROWABLE " + t;
                    log(verdict);
                } finally {
                    if (codec != null) {
                        try { codec.stop(); } catch (Exception ignore) {}
                        try { codec.release(); } catch (Exception ignore) {}
                        log("released");
                    }
                }
                log("instance " + inst + " verdict=" + verdict
                        + " elapsedMs=" + (android.os.SystemClock.elapsedRealtime() - t0));
                if (verdict.startsWith("SUCCESS")) okInstances++;
                else {
                    log("=== RESULT: " + okInstances + " ok, instance " + inst
                            + " failed ===");
                    return;
                }
            }
            log("=== RESULT: all " + maxInstances + " instances succeeded in app-uid ===");
        } finally {
            if (reader != null) reader.close();
        }
    }

    private static byte[] slice(byte[] d, int from, int to) {
        byte[] r = new byte[to - from];
        System.arraycopy(d, from, r, 0, r.length);
        return r;
    }

    private static byte[] readAsset(android.content.res.AssetManager am, String name)
            throws Exception {
        InputStream in = am.open(name);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[1 << 20];
        int r;
        while ((r = in.read(buf)) > 0) out.write(buf, 0, r);
        in.close();
        return out.toByteArray();
    }

    static final class McProbeApp {
        static String PKG = "com.example.media_kit_hdr_lab";
    }
}
