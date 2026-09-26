package com.example.media_kit_test;

import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.Image;
import android.media.ImageReader;
import android.util.Log;
import android.graphics.ImageFormat;
import android.graphics.Rect;
import android.hardware.HardwareBuffer;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.SystemClock;
import android.view.Surface;

import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

/** Diagnostic only: inspects this device's HEVC decoder outputs. */
final class P5CodecProbe {
    private P5CodecProbe() {}
    static { System.load("/data/local/tmp/libmedia_kit_p5_probe_audit.so"); }
    private static native String inspectHardwareBuffer(HardwareBuffer buffer);
    private static native String inspectGpuImport(HardwareBuffer buffer,
            int cropLeft, int cropTop, int cropRight, int cropBottom);
    private static native Surface createNativeReader(int width, int height, int maxImages,
                                                     boolean deferredAcquire,
                                                     boolean holdPreviousImage);
    private static native int nativeReaderImageCount();
    private static native int nativeReaderAcquireErrors();
    private static native int nativeReaderNotifications();
    private static native int pollNativeReaderImage();
    private static native void closeNativeReader();

    private static int startCodeLength(ByteBuffer sample, int offset, int size) {
        if (offset + 3 > size || sample.get(offset) != 0 ||
                sample.get(offset + 1) != 0) return 0;
        if (sample.get(offset + 2) == 1) return 3;
        if (offset + 4 <= size && sample.get(offset + 2) == 0 &&
                sample.get(offset + 3) == 1) return 4;
        return 0;
    }

    private static int rpuCount(ByteBuffer sample, int size) {
        if (startCodeLength(sample, 0, size) != 0) {
            int offset = 0;
            int count = 0;
            while (offset < size) {
                int prefix = startCodeLength(sample, offset, size);
                if (prefix == 0 || offset + prefix + 2 > size) return -1;
                offset += prefix;
                if (((sample.get(offset) & 0xff) >> 1 & 0x3f) == 62) count++;
                int next = offset + 2;
                while (next < size && startCodeLength(sample, next, size) == 0) {
                    next++;
                }
                offset = next;
            }
            return count;
        }
        int offset = 0;
        int count = 0;
        while (offset + 6 <= size) {
            int nalSize = ((sample.get(offset) & 0xff) << 24)
                    | ((sample.get(offset + 1) & 0xff) << 16)
                    | ((sample.get(offset + 2) & 0xff) << 8)
                    | (sample.get(offset + 3) & 0xff);
            offset += 4;
            if (nalSize < 2 || nalSize > size - offset) return -1;
            if (((sample.get(offset) & 0xff) >> 1 & 0x3f) == 62) count++;
            offset += nalSize;
        }
        return offset == size ? count : -1;
    }

    private static MediaCodecInfo chooseCodec(String mime) {
        for (MediaCodecInfo info : new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
            if (info.isEncoder() || !info.isHardwareAccelerated()) continue;
            for (String type : info.getSupportedTypes()) {
                if (type.equalsIgnoreCase(mime)) return info;
            }
        }
        return null;
    }

    static Map<String, Object> run(String path, int maxFrames, boolean surfaceMode,
                                   boolean cpuRead, boolean gpuImport,
                                   int readerWidth, int readerHeight,
                                   int readerMaxImages, boolean nativeReaderMode,
                                   boolean deferredAcquire,
                                   boolean holdPreviousImage) throws Exception {
        Map<String, Object> result = new HashMap<>();
        MediaExtractor extractor = new MediaExtractor();
        extractor.setDataSource(path);
        int track = -1;
        List<String> tracks = new ArrayList<>();
        for (int i = 0; i < extractor.getTrackCount(); i++) {
            MediaFormat candidate = extractor.getTrackFormat(i);
            tracks.add(candidate.toString());
            String mime = candidate.getString(MediaFormat.KEY_MIME);
            if (mime != null && mime.startsWith("video/")) { track = i; break; }
        }
        result.put("tracks", tracks);
        if (track < 0) {
            extractor.release();
            throw new IllegalStateException("No video track: " + tracks);
        }
        extractor.selectTrack(track);
        MediaFormat inputFormat = extractor.getTrackFormat(track);
        String sourceMime = inputFormat.getString(MediaFormat.KEY_MIME);
        String decodeMime = "video/dolby-vision".equals(sourceMime) ? "video/hevc" : sourceMime;
        result.put("inputFormat", inputFormat.toString());
        result.put("sourceMime", sourceMime);
        MediaCodecInfo codecInfo = chooseCodec(decodeMime);
        if (codecInfo == null) {
            extractor.release();
            throw new IllegalStateException("No hardware decoder for " + decodeMime);
        }
        result.put("codec", codecInfo.getName());
        result.put("decodeMime", decodeMime);
        result.put("surfaceMode", surfaceMode);
        result.put("cpuRead", cpuRead);
        result.put("gpuImport", gpuImport);
        result.put("readerSize", readerWidth + "x" + readerHeight);
        result.put("readerMaxImages", readerMaxImages);
        result.put("nativeReaderMode", nativeReaderMode);
        result.put("deferredAcquire", deferredAcquire);
        result.put("holdPreviousImage", holdPreviousImage);
        List<String> advertisedColors = new ArrayList<>();
        for (int color : codecInfo.getCapabilitiesForType(decodeMime).colorFormats) {
            advertisedColors.add("0x" + Integer.toHexString(color));
        }
        result.put("advertisedColorFormats", advertisedColors);
        inputFormat.setString(MediaFormat.KEY_MIME, decodeMime);
        MediaCodec codec = MediaCodec.createByCodecName(codecInfo.getName());
        List<Map<String, Object>> firstFrames = new ArrayList<>();
        // -1 marks a duplicate PTS; an Image timestamp then has no unique output.
        Map<Long, Integer> outputIndexByPtsUs = new HashMap<>();
        Map<Long, Integer> rpuByPts = new HashMap<>();
        int rpuInputSamples = 0;
        int rpuParseInvalidInputs = 0;
        int rpuMatchedOutputs = 0;
        int rpuMissingOutputs = 0;
        int rpuUnmatchedOutputs = 0;
        List<Map<String, Object>> surfaceImages = new ArrayList<>();
        AtomicInteger imageIndex = new AtomicInteger();
        HandlerThread imageThread = null;
        ImageReader imageReader = null;
        Surface nativeSurface = null;
        int frames = 0;
        long firstOutputNs = 0;
        long lastOutputNs = 0;
        boolean inputEos = false;
        boolean started = false;
        MediaCodec.BufferInfo output = new MediaCodec.BufferInfo();
        try {
            if (surfaceMode) {
                int width = readerWidth > 0 ? readerWidth :
                        inputFormat.getInteger(MediaFormat.KEY_WIDTH);
                int height = readerHeight > 0 ? readerHeight :
                        inputFormat.getInteger(MediaFormat.KEY_HEIGHT);
                if (nativeReaderMode) {
                    nativeSurface = createNativeReader(width, height,
                            readerMaxImages > 0 ? readerMaxImages : 3,
                            deferredAcquire, holdPreviousImage);
                } else {
                    imageThread = new HandlerThread("p5-probe-images");
                    imageThread.start();
                    imageReader = ImageReader.newInstance(
                        width,
                        height,
                        ImageFormat.PRIVATE, readerMaxImages > 0 ? readerMaxImages : 3,
                        HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE |
                                (cpuRead ? HardwareBuffer.USAGE_CPU_READ_RARELY : 0));
                    imageReader.setOnImageAvailableListener(reader -> {
                    Image image = reader.acquireNextImage();
                    if (image == null) return;
                    try {
                        int index = imageIndex.getAndIncrement();
                        synchronized (surfaceImages) {
                            if ((!cpuRead && !gpuImport && index < 8) ||
                                    ((cpuRead || gpuImport) &&
                                            (index == 0 || image.getTimestamp() == 10000000000L))) {
                                Map<String, Object> sample = new HashMap<>();
                                sample.put("index", index);
                                sample.put("imageFormat", image.getFormat());
                                sample.put("timestampNs", image.getTimestamp());
                                sample.put("width", image.getWidth());
                                sample.put("height", image.getHeight());
                                Rect crop = image.getCropRect();
                                sample.put("cropRect", crop.flattenToString());
                                HardwareBuffer hardwareBuffer = image.getHardwareBuffer();
                                if (hardwareBuffer != null) {
                                    sample.put("hardwareBufferFormat", hardwareBuffer.getFormat());
                                    sample.put("hardwareBufferUsage", hardwareBuffer.getUsage());
                                    sample.put("hardwareBufferWidth", hardwareBuffer.getWidth());
                                    sample.put("hardwareBufferHeight", hardwareBuffer.getHeight());
                                    if (cpuRead) {
                                        sample.put("cpuInspect", inspectHardwareBuffer(hardwareBuffer));
                                    }
                                    if (gpuImport) {
                                        sample.put("gpuImport", inspectGpuImport(hardwareBuffer,
                                                crop.left, crop.top, crop.right, crop.bottom));
                                    }
                                }
                                surfaceImages.add(sample);
                            }
                        }
                    } finally {
                        image.close();
                    }
                    }, new Handler(imageThread.getLooper()));
                }
            }
            codec.configure(inputFormat, nativeSurface != null ? nativeSurface :
                    imageReader == null ? null : imageReader.getSurface(), null, 0);
            codec.start();
            started = true;
            long deadline = SystemClock.elapsedRealtimeNanos() +
                    (maxFrames > 250 ? 1_800_000_000_000L : 45_000_000_000L);
            boolean stalled = false;
            while (frames < maxFrames && SystemClock.elapsedRealtimeNanos() < deadline) {
                if (maxFrames > 250 && lastOutputNs != 0 &&
                        SystemClock.elapsedRealtimeNanos() - lastOutputNs > 15_000_000_000L) {
                    stalled = true;
                    break;
                }
                if (nativeReaderMode && deferredAcquire) {
                    pollNativeReaderImage();
                }
                if (!inputEos) {
                    int inputIndex = codec.dequeueInputBuffer(10000);
                    if (inputIndex >= 0) {
                        ByteBuffer buffer = codec.getInputBuffer(inputIndex);
                        if (buffer == null) throw new IllegalStateException("No input buffer");
                        buffer.clear();
                        int size = extractor.readSampleData(buffer, 0);
                        if (size < 0) {
                            codec.queueInputBuffer(inputIndex, 0, 0, 0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputEos = true;
                        } else {
                            long ptsUs = extractor.getSampleTime();
                            int rpus = rpuCount(buffer, size);
                            if (rpus < 0) {
                                rpuParseInvalidInputs++;
                            } else {
                                rpuByPts.put(ptsUs, rpus);
                                if (rpus > 0) rpuInputSamples++;
                            }
                            codec.queueInputBuffer(inputIndex, 0, size,
                                    ptsUs, 0);
                            extractor.advance();
                        }
                    }
                }
                int outputIndex = codec.dequeueOutputBuffer(output, 10000);
                if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    MediaFormat outputFormat = codec.getOutputFormat();
                    result.put("outputFormat", outputFormat.toString());
                    for (String key : new String[] {"color-format", "bit-depth", "stride",
                            "slice-height", "crop-left", "crop-right", "crop-top", "crop-bottom",
                            "color-standard", "color-transfer", "color-range"}) {
                        if (outputFormat.containsKey(key)) {
                            try { result.put("output." + key, outputFormat.getInteger(key)); }
                            catch (Exception ignored) { }
                        }
                    }
                } else if (outputIndex >= 0) {
                    Integer previousIndex = outputIndexByPtsUs.putIfAbsent(
                            output.presentationTimeUs, frames);
                    if (previousIndex != null) {
                        outputIndexByPtsUs.put(output.presentationTimeUs, -1);
                    }
                    long now = SystemClock.elapsedRealtimeNanos();
                    if (firstOutputNs == 0) firstOutputNs = now;
                    lastOutputNs = now;
                    if (firstFrames.size() < 8) {
                        Map<String, Object> frame = new HashMap<>();
                        frame.put("ptsUs", output.presentationTimeUs);
                        frame.put("size", output.size);
                        frame.put("rpuNalCount", rpuByPts.get(output.presentationTimeUs));
                        if (!surfaceMode) {
                            ByteBuffer buffer = codec.getOutputBuffer(outputIndex);
                            frame.put("bufferRemaining", buffer == null ? -1 : buffer.remaining());
                        }
                        firstFrames.add(frame);
                    }
                    Integer rpus = rpuByPts.remove(output.presentationTimeUs);
                    if (rpus == null) rpuUnmatchedOutputs++;
                    else if (rpus > 0) rpuMatchedOutputs++;
                    else rpuMissingOutputs++;
                    frames++;
                    if (maxFrames > 250 && frames % 1000 == 0) {
                        Log.i("MEDIA_KIT_CODEC_LONG", "frames=" + frames +
                                " ptsUs=" + output.presentationTimeUs +
                                " readerImages=" +
                                (nativeReaderMode ? nativeReaderImageCount() : imageIndex.get()));
                    }
                    codec.releaseOutputBuffer(outputIndex, surfaceMode);
                    if (nativeReaderMode && deferredAcquire) {
                        pollNativeReaderImage();
                    }
                    if ((output.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break;
                }
            }
            double seconds = (lastOutputNs - firstOutputNs) / 1_000_000_000.0;
            result.put("firstFrames", firstFrames);
            if (surfaceMode) {
                if (nativeReaderMode) {
                    Thread.sleep(200);
                    if (deferredAcquire) pollNativeReaderImage();
                    result.put("nativeReaderImages", nativeReaderImageCount());
                    result.put("nativeReaderAcquireErrors", nativeReaderAcquireErrors());
                    result.put("nativeReaderNotifications", nativeReaderNotifications());
                } else {
                long imageDeadline = SystemClock.elapsedRealtimeNanos() + 2_000_000_000L;
                int expectedImages = cpuRead || gpuImport
                        ? Math.min(3, (frames + 99) / 100) : Math.min(8, frames);
                while (SystemClock.elapsedRealtimeNanos() < imageDeadline) {
                    synchronized (surfaceImages) {
                        if (surfaceImages.size() >= expectedImages) break;
                    }
                    Thread.sleep(10);
                }
                synchronized (surfaceImages) {
                    int exactImagePtsMatches = 0;
                    for (Map<String, Object> sample : surfaceImages) {
                        long timestampNs = (Long) sample.get("timestampNs");
                        long ptsUs = timestampNs / 1000;
                        Integer outputOrdinal = timestampNs % 1000 == 0 ?
                                outputIndexByPtsUs.get(ptsUs) : null;
                        boolean exactMatch = outputOrdinal != null && outputOrdinal >= 0;
                        sample.put("timestampAsPtsUs", ptsUs);
                        sample.put("timestampMatchesOutputPts", exactMatch);
                        sample.put("matchedOutputOrdinal", exactMatch ? outputOrdinal : null);
                        sample.put("duplicateOutputPts", outputOrdinal != null &&
                                outputOrdinal < 0);
                        if (exactMatch) exactImagePtsMatches++;
                    }
                    result.put("exactImagePtsMatches", exactImagePtsMatches);
                    result.put("surfaceImages", new ArrayList<>(surfaceImages));
                }
                }
            }
            result.put("frames", frames);
            result.put("stalled", stalled);
            result.put("inputEos", inputEos);
            result.put("rpuInputSamples", rpuInputSamples);
            result.put("rpuParseInvalidInputs", rpuParseInvalidInputs);
            result.put("rpuMatchedOutputs", rpuMatchedOutputs);
            result.put("rpuMissingOutputs", rpuMissingOutputs);
            result.put("rpuUnmatchedOutputs", rpuUnmatchedOutputs);
            result.put("rpuQueuedInputs", rpuByPts.size());
            result.put("elapsedOutputSeconds", seconds);
            result.put("outputFps", seconds > 0 ? (frames - 1) / seconds : 0.0);
            result.put("reachedFrameTarget", frames >= maxFrames);
            return result;
        } finally {
            try { if (started) codec.stop(); } finally {
                codec.release();
                if (imageReader != null) {
                    imageReader.setOnImageAvailableListener(null, null);
                }
                if (imageThread != null) {
                    imageThread.quitSafely();
                    try { imageThread.join(5000); }
                    catch (InterruptedException e) { Thread.currentThread().interrupt(); }
                }
                if (imageReader != null) {
                    if (imageThread == null || !imageThread.isAlive()) {
                        imageReader.close();
                    } else {
                        Log.w("MEDIA_KIT_CODEC_PROBE", "Reader callback did not exit; skip close");
                    }
                }
                if (nativeSurface != null) nativeSurface.release();
                if (nativeReaderMode) closeNativeReader();
                extractor.release();
            }
        }
    }
}
