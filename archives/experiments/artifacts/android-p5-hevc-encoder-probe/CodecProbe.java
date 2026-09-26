import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import java.util.Arrays;
public final class CodecProbe {
  public static void main(String[] args) {
    for (MediaCodecInfo info : new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
      if (!info.isEncoder()) continue;
      for (String type : info.getSupportedTypes()) {
        if (!"video/hevc".equalsIgnoreCase(type)) continue;
        System.out.println("codec=" + info.getName() + " type=" + type + " hardware=" + info.isHardwareAccelerated());
        try {
          MediaCodecInfo.CodecCapabilities caps = info.getCapabilitiesForType(type);
          for (MediaCodecInfo.CodecProfileLevel pl : caps.profileLevels)
            System.out.println("profile=" + pl.profile + " level=" + pl.level);
          for (int color : caps.colorFormats)
            System.out.println("colorFormat=0x" + Integer.toHexString(color));
          MediaCodecInfo.VideoCapabilities video = caps.getVideoCapabilities();
          if (video != null) {
            for (int[] sample : new int[][]{{3840,2160,50},{3840,2160,30},{1920,1080,60},{1920,1080,50},{1440,810,50},{1440,812,50},{1440,812,24}}) {
              System.out.println("sizeRate=" + sample[0] + "x" + sample[1] + "@" + sample[2] + " supported=" + video.areSizeAndRateSupported(sample[0],sample[1],sample[2]));
            }
          }
        } catch (Exception error) {
          System.out.println("error=" + error);
        }
      }
    }
  }
}
