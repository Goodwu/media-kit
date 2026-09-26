import android.graphics.ImageFormat;
import android.media.Image;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import java.nio.ByteBuffer;
import java.io.FileOutputStream;

/** Diagnostic: inspect actual HEVC ByteBuffer output on this Android device. */
public final class BufferProbe {
    public static void main(String[] args) throws Exception {
        if (args.length < 2 || args.length > 3)
            throw new IllegalArgumentException("path, requestFlexible, optional output path required");
        boolean captureTarget = args.length == 3;
        MediaExtractor extractor = new MediaExtractor();
        MediaCodec codec = null;
        try {
            extractor.setDataSource(args[0]);
            int track = -1;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat candidate = extractor.getTrackFormat(i);
                String mime = candidate.getString(MediaFormat.KEY_MIME);
                if (mime != null && mime.startsWith("video/")) { track = i; break; }
            }
            if (track < 0) throw new IllegalStateException("no video track");
            extractor.selectTrack(track);
            MediaFormat format = extractor.getTrackFormat(track);
            System.out.println("input=" + format);
            format.setString(MediaFormat.KEY_MIME, "video/hevc");
            if (Boolean.parseBoolean(args[1]))
                format.setInteger(MediaFormat.KEY_COLOR_FORMAT, 0x7f420888);
            codec = MediaCodec.createByCodecName("OMX.hisi.video.decoder.hevc");
            codec.configure(format, null, null, 0);
            codec.start();
            System.out.println("configured=" + codec.getOutputFormat());
            MediaCodec.BufferInfo output = new MediaCodec.BufferInfo();
            boolean inputEos = false;
            int frames = 0;
            long deadline = android.os.SystemClock.elapsedRealtime()
                    + (captureTarget ? 120000 : 30000);
            while (frames < (captureTarget ? 550 : 12)
                    && android.os.SystemClock.elapsedRealtime() < deadline) {
                if (!inputEos) {
                    int input = codec.dequeueInputBuffer(10000);
                    if (input >= 0) {
                        ByteBuffer bytes = codec.getInputBuffer(input);
                        bytes.clear();
                        int size = extractor.readSampleData(bytes, 0);
                        if (size < 0) {
                            codec.queueInputBuffer(input, 0, 0, 0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputEos = true;
                        } else {
                            codec.queueInputBuffer(input, 0, size,
                                    extractor.getSampleTime(), 0);
                            extractor.advance();
                        }
                    }
                }
                int index = codec.dequeueOutputBuffer(output, 10000);
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    System.out.println("changed=" + codec.getOutputFormat());
                } else if (index >= 0) {
                    if (frames == 0) {
                        System.out.println("firstPTS=" + output.presentationTimeUs
                                + " size=" + output.size);
                        Image image = codec.getOutputImage(index);
                        if (image == null) {
                            System.out.println("firstImage=null");
                        } else {
                            System.out.println("firstImageFormat=" + image.getFormat()
                                    + " YUV420_888=" + ImageFormat.YUV_420_888
                                    + " planes=" + image.getPlanes().length);
                            for (int i = 0; i < image.getPlanes().length; i++) {
                                Image.Plane plane = image.getPlanes()[i];
                                System.out.println("plane=" + i + " rowStride="
                                        + plane.getRowStride() + " pixelStride="
                                        + plane.getPixelStride() + " capacity="
                                        + plane.getBuffer().capacity());
                            }
                            image.close();
                        }
                    }
                    if (captureTarget && output.presentationTimeUs == 10_000_000L) {
                        Image image = codec.getOutputImage(index);
                        if (image == null || image.getFormat() != ImageFormat.YUV_420_888)
                            throw new IllegalStateException("target image unavailable or not 8-bit YUV420");
                        try (FileOutputStream file = new FileOutputStream(args[2])) {
                            Image.Plane[] planes = image.getPlanes();
                            for (int c = 0; c < 3; c++) {
                                int width = image.getWidth() >> (c == 0 ? 0 : 1);
                                int height = image.getHeight() >> (c == 0 ? 0 : 1);
                                Image.Plane plane = planes[c];
                                ByteBuffer bytes = plane.getBuffer();
                                byte[] row = new byte[width];
                                for (int y = 0; y < height; y++) {
                                    for (int x = 0; x < width; x++)
                                        row[x] = bytes.get(y * plane.getRowStride()
                                                + x * plane.getPixelStride());
                                    file.write(row);
                                }
                            }
                        } finally {
                            image.close();
                        }
                        System.out.println("capturedPTS=" + output.presentationTimeUs
                                + " ordinal=" + frames + " path=" + args[2]);
                    }
                    frames++;
                    codec.releaseOutputBuffer(index, false);
                    if (captureTarget && output.presentationTimeUs == 10_000_000L) break;
                    if ((output.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break;
                }
            }
            System.out.println("frames=" + frames + " finalOutput=" + codec.getOutputFormat());
        } finally {
            if (codec != null) {
                try { codec.stop(); } catch (Exception ignored) { }
                codec.release();
            }
            extractor.release();
        }
    }
}
