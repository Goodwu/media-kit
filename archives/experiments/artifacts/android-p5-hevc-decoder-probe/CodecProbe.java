import android.media.MediaCodecInfo;
import android.media.MediaCodecList;

public final class CodecProbe {
    public static void main(String[] args) {
        for (MediaCodecInfo info : new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos()) {
            if (info.isEncoder()) continue;
            for (String type : info.getSupportedTypes()) {
                if (!"video/hevc".equalsIgnoreCase(type)) continue;
                System.out.println("codec=" + info.getName()
                        + " hardware=" + info.isHardwareAccelerated());
                try {
                    MediaCodecInfo.CodecCapabilities caps = info.getCapabilitiesForType(type);
                    for (MediaCodecInfo.CodecProfileLevel level : caps.profileLevels)
                        System.out.println("profile=" + level.profile + " level=" + level.level);
                    for (int color : caps.colorFormats)
                        System.out.println("colorFormat=0x" + Integer.toHexString(color));
                    MediaCodecInfo.VideoCapabilities video = caps.getVideoCapabilities();
                    if (video != null) {
                        System.out.println("sizeRate=3840x2160@50 supported="
                                + video.areSizeAndRateSupported(3840, 2160, 50));
                    }
                } catch (Exception error) {
                    System.out.println("error=" + error);
                }
            }
        }
    }
}
