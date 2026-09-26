import android.graphics.ImageFormat;
import android.media.Image;
import android.media.ImageReader;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.os.SystemClock;
import android.hardware.HardwareBuffer;
import java.io.FileOutputStream;
import java.nio.ByteBuffer;

/** Diagnose whether the same HEVC decoder exposes CPU-readable Surface YUV. */
public final class SurfaceYuvProbe {
    public static void main(String[] args) throws Exception {
        if (args.length != 2) throw new IllegalArgumentException("input.mp4 output.yuv");
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
            reader = ImageReader.newInstance(width, height, ImageFormat.YUV_420_888, 2);
            codec = MediaCodec.createByCodecName("OMX.hisi.video.decoder.hevc");
            codec.configure(format, reader.getSurface(), null, 0);
            codec.start();
            started = true;
            System.out.println("configured=" + codec.getOutputFormat());
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            boolean inputEos = false;
            int frames = 0, images = 0;
            long deadline = SystemClock.elapsedRealtime() + 120000;
            while (frames < 550 && SystemClock.elapsedRealtime() < deadline) {
                if (!inputEos) {
                    int in = codec.dequeueInputBuffer(10000);
                    if (in >= 0) {
                        ByteBuffer bytes = codec.getInputBuffer(in);
                        bytes.clear();
                        int size = extractor.readSampleData(bytes, 0);
                        if (size < 0) {
                            codec.queueInputBuffer(in, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
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
                    if (image == null) throw new IllegalStateException("no Image for PTS=" + ptsUs);
                    try {
                        images++;
                        HardwareBuffer hardwareBuffer = image.getHardwareBuffer();
                        int hardwareFormat = hardwareBuffer == null ? -1 : hardwareBuffer.getFormat();
                        if (frames == 1 || ptsUs == 10000000L) {
                            System.out.println("frame=" + frames + " PTS=" + ptsUs
                                    + " imageNs=" + image.getTimestamp() + " format=" + image.getFormat()
                                    + " hardwareFormat=" + hardwareFormat + " crop=" + image.getCropRect());
                        }
                        if (ptsUs == 10000000L) {
                            if (hardwareFormat != HardwareBuffer.YCBCR_420_888)
                                throw new IllegalStateException("native buffer format " + hardwareFormat
                                        + " is not CPU-readable YCBCR_420_888");
                            if (image.getFormat() != ImageFormat.YUV_420_888 || image.getPlanes().length != 3)
                                throw new IllegalStateException("not three-plane YUV_420_888");
                            try (FileOutputStream file = new FileOutputStream(args[1])) {
                                Image.Plane[] planes = image.getPlanes();
                                for (int c = 0; c < 3; c++) {
                                    int pw = width >> (c == 0 ? 0 : 1);
                                    int ph = height >> (c == 0 ? 0 : 1);
                                    Image.Plane p = planes[c];
                                    ByteBuffer b = p.getBuffer();
                                    System.out.println("plane=" + c + " row=" + p.getRowStride()
                                            + " pixel=" + p.getPixelStride() + " capacity=" + b.capacity());
                                    byte[] row = new byte[pw];
                                    for (int y = 0; y < ph; y++) {
                                        for (int x = 0; x < pw; x++)
                                            row[x] = b.get(y * p.getRowStride() + x * p.getPixelStride());
                                        file.write(row);
                                    }
                                }
                            }
                            System.out.println("captured PTS=" + ptsUs + " ordinal=" + frames);
                            break;
                        }
                    } finally { image.close(); }
                    if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break;
                }
            }
            System.out.println("frames=" + frames + " images=" + images);
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
