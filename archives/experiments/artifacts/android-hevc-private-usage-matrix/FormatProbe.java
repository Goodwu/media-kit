import android.graphics.ImageFormat;
import android.hardware.HardwareBuffer;
import android.media.Image;
import android.media.ImageReader;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.os.SystemClock;
import java.nio.ByteBuffer;

public final class FormatProbe {
  public static void main(String[] args) throws Exception {
    MediaExtractor ex = new MediaExtractor();
    ex.setDataSource(args[0]);
    ex.selectTrack(0);
    MediaFormat fmt = ex.getTrackFormat(0);
    System.out.println("input=" + fmt); System.out.println("requestedUsage=" + args[1]);
    ImageReader reader = ImageReader.newInstance(fmt.getInteger(MediaFormat.KEY_WIDTH),
        fmt.getInteger(MediaFormat.KEY_HEIGHT), ImageFormat.PRIVATE, 2,
        Long.parseLong(args[1]));
    MediaCodec codec = MediaCodec.createByCodecName("OMX.hisi.video.decoder.hevc");
    boolean started = false;
    try {
      codec.configure(fmt, reader.getSurface(), null, 0);
      codec.start(); started = true;
      MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
      int count = 0;
      long deadline = SystemClock.elapsedRealtime() + 30000;
      while (count < 8 && SystemClock.elapsedRealtime() < deadline) {
        int in = codec.dequeueInputBuffer(10000);
        if (in >= 0) {
          ByteBuffer bytes = codec.getInputBuffer(in); bytes.clear();
          int size = ex.readSampleData(bytes, 0);
          if (size < 0) break;
          codec.queueInputBuffer(in, 0, size, ex.getSampleTime(), 0);
          ex.advance();
        }
        int out = codec.dequeueOutputBuffer(info, 10000);
        if (out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED)
          System.out.println("output=" + codec.getOutputFormat());
        if (out >= 0) {
          codec.releaseOutputBuffer(out, true); count++;
          Image image = null;
          long imageDeadline = SystemClock.elapsedRealtime() + 1000;
          while (image == null && SystemClock.elapsedRealtime() < imageDeadline) {
            image = reader.acquireNextImage();
            if (image == null) SystemClock.sleep(2);
          }
          if (image == null) throw new IllegalStateException("no image at output=" + count);
          try {
            HardwareBuffer hb = image.getHardwareBuffer();
            System.out.println("frame=" + count + " pts=" + info.presentationTimeUs
                + " imageNs=" + image.getTimestamp() + " imageFormat=" + image.getFormat()
                + " hbFormat=" + hb.getFormat() + " usage=" + hb.getUsage()
                + " stride=" + hb.getWidth() + "x" + hb.getHeight());
          } finally { image.close(); }
        }
      }
      System.out.println("frames=" + count);
    } finally {
      if (started) codec.stop(); codec.release(); reader.close(); ex.release();
    }
  }
}
