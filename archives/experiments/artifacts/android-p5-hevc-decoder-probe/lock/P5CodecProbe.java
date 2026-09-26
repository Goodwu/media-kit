package com.example.media_kit_test;

import android.graphics.ImageFormat;
import android.hardware.HardwareBuffer;
import android.media.Image;
import android.media.ImageReader;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.os.SystemClock;
import java.nio.ByteBuffer;

/** Standalone, read-only inspection of the decoder's private Surface buffer. */
public final class P5CodecProbe {
    static { System.load("/data/local/tmp/libmedia_kit_p5_lock_probe.so"); }
    private static native String inspectHardwareBuffer(HardwareBuffer buffer);

    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("input.mp4");
        MediaExtractor extractor = new MediaExtractor();
        MediaCodec codec = null;
        ImageReader reader = null;
        boolean started = false;
        try {
            extractor.setDataSource(args[0]);
            int track = -1;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat f = extractor.getTrackFormat(i);
                if (f.getString(MediaFormat.KEY_MIME).startsWith("video/")) { track = i; break; }
            }
            if (track < 0) throw new IllegalStateException("no video track");
            extractor.selectTrack(track);
            MediaFormat format = extractor.getTrackFormat(track);
            System.out.println("input=" + format);
            int width = format.getInteger(MediaFormat.KEY_WIDTH);
            int height = format.getInteger(MediaFormat.KEY_HEIGHT);
            format.setString(MediaFormat.KEY_MIME, "video/hevc");
            long usage = HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE
                    | HardwareBuffer.USAGE_CPU_READ_RARELY;
            reader = ImageReader.newInstance(width, height, ImageFormat.PRIVATE, 2, usage);
            codec = MediaCodec.createByCodecName("OMX.hisi.video.decoder.hevc");
            codec.configure(format, reader.getSurface(), null, 0);
            codec.start();
            started = true;
            System.out.println("configured=" + codec.getOutputFormat());
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            boolean inputEos = false;
            int frames = 0;
            long deadline = SystemClock.elapsedRealtime() + 120000;
            while (frames < 550 && SystemClock.elapsedRealtime() < deadline) {
                if (!inputEos) {
                    int in = codec.dequeueInputBuffer(10000);
                    if (in >= 0) {
                        ByteBuffer bytes = codec.getInputBuffer(in);
                        bytes.clear();
                        int size = extractor.readSampleData(bytes, 0);
                        if (size < 0) {
                            codec.queueInputBuffer(in, 0, 0, 0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputEos = true;
                        } else {
                            codec.queueInputBuffer(in, 0, size, extractor.getSampleTime(), 0);
                            extractor.advance();
                        }
                    }
                }
                int out = codec.dequeueOutputBuffer(info, 10000);
                if (out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    System.out.println("changed=" + codec.getOutputFormat());
                } else if (out >= 0) {
                    long ptsUs = info.presentationTimeUs;
                    codec.releaseOutputBuffer(out, true);
                    frames++;
                    Image image = null;
                    long imageDeadline = SystemClock.elapsedRealtime() + 1000;
                    while (image == null && SystemClock.elapsedRealtime() < imageDeadline) {
                        image = reader.acquireNextImage();
                        if (image == null) SystemClock.sleep(2);
                    }
                    if (image == null) throw new IllegalStateException("no Image PTS=" + ptsUs);
                    try {
                        if (frames == 1 || ptsUs == 10000000L) {
                            HardwareBuffer buffer = image.getHardwareBuffer();
                            System.out.println("frame=" + frames + " PTS=" + ptsUs
                                    + " imageNs=" + image.getTimestamp()
                                    + " format=" + image.getFormat()
                                    + " bufferFormat=" + (buffer == null ? -1 : buffer.getFormat())
                                    + " crop=" + image.getCropRect());
                            System.out.println("native=" + inspectHardwareBuffer(buffer));
                        }
                    } finally { image.close(); }
                    if (ptsUs == 10000000L ||
                            (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break;
                }
            }
            System.out.println("frames=" + frames);
        } finally {
            if (codec != null) {
                if (started) try { codec.stop(); } catch (Exception ignored) { }
                codec.release();
            }
            if (reader != null) reader.close();
            extractor.release();
        }
    }
}
