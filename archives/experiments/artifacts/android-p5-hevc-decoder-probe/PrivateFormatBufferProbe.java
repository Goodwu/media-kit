import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import java.nio.ByteBuffer;

/** Probe whether Huawei private color formats expose a no-Surface ByteBuffer. */
public final class PrivateFormatBufferProbe {
    public static void main(String[] args) throws Exception {
        int requested = Integer.decode(args[1]);
        MediaExtractor extractor = new MediaExtractor();
        MediaCodec codec = null;
        try {
            extractor.setDataSource(args[0]);
            MediaFormat format = extractor.getTrackFormat(0);
            extractor.selectTrack(0);
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, requested);
            System.out.println("request=" + requested + " input=" + format);
            codec = MediaCodec.createByCodecName("OMX.hisi.video.decoder.hevc");
            codec.configure(format, null, null, 0);
            codec.start();
            System.out.println("configured=" + codec.getOutputFormat());
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            int frames = 0;
            boolean eos = false;
            long deadline = android.os.SystemClock.elapsedRealtime() + 30000;
            while (frames < 12 && android.os.SystemClock.elapsedRealtime() < deadline) {
                if (!eos) {
                    int input = codec.dequeueInputBuffer(10000);
                    if (input >= 0) {
                        ByteBuffer buffer = codec.getInputBuffer(input);
                        buffer.clear();
                        int size = extractor.readSampleData(buffer, 0);
                        if (size < 0) {
                            codec.queueInputBuffer(input, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            eos = true;
                        } else {
                            codec.queueInputBuffer(input, 0, size, extractor.getSampleTime(), 0);
                            extractor.advance();
                        }
                    }
                }
                int index = codec.dequeueOutputBuffer(info, 10000);
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    System.out.println("changed=" + codec.getOutputFormat());
                } else if (index >= 0) {
                    if (frames == 0) {
                        ByteBuffer buffer = codec.getOutputBuffer(index);
                        System.out.println("firstPTS=" + info.presentationTimeUs + " size=" + info.size
                                + " offset=" + info.offset + " capacity="
                                + (buffer == null ? "null" : buffer.capacity()));
                    }
                    frames++;
                    codec.releaseOutputBuffer(index, false);
                    if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break;
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
