"""Compile/execute the production Java query with explicit host API fixtures.
Not an Android device or native-player test; no snippets substitute algorithms.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PKG = 'com/alexmercerind/media_kit_video'
STUBS = {
'android/os/Build.java': '''package android.os; public class Build { public static class VERSION {public static int SDK_INT=34;} }''',
'android/util/Range.java': '''package android.util; public class Range<T extends Comparable<T>> { private final T min,max; public Range(T a,T b){min=a;max=b;} public boolean contains(T x){return x.compareTo(min)>=0&&x.compareTo(max)<=0;} }''',
'android/content/Context.java': '''package android.content; public class Context { public static final String DISPLAY_SERVICE="display"; public android.hardware.display.DisplayManager manager=new android.hardware.display.DisplayManager(); public Object getSystemService(String s){return manager;} }''',
'android/hardware/display/DisplayManager.java': '''package android.hardware.display; public class DisplayManager {public java.util.Map<Integer,android.view.Display> displays=new java.util.HashMap<>(); public android.view.Display getDisplay(int id){return displays.get(id);} }''',
'android/view/Display.java': '''package android.view; public class Display {
 public static final int DEFAULT_DISPLAY=0; public int id; public boolean valid=true; public int[] types={2};
 public Display(int id){this.id=id;} public boolean isValid(){return valid;} public int getDisplayId(){return id;} public float getRefreshRate(){return 60;}
 public class Mode { public int getModeId(){return 1;} public int[] getSupportedHdrTypes(){return types;} }
 public Mode getMode(){return new Mode();} public class HdrCapabilities {public int[] getSupportedHdrTypes(){return types;}} public HdrCapabilities getHdrCapabilities(){return new HdrCapabilities();} }''',
'android/media/MediaFormat.java': '''package android.media; public class MediaFormat {
 public static final String KEY_MIME="mime",KEY_WIDTH="width",KEY_HEIGHT="height",KEY_PROFILE="profile";
 public java.util.Map<String,Object> values=new java.util.HashMap<>(); public void setString(String k,String v){values.put(k,v);} public void setInteger(String k,int v){values.put(k,v);} }''',
'android/media/MediaCodecList.java': '''package android.media; public class MediaCodecList {public static final int REGULAR_CODECS=0; public static MediaCodecInfo[] infos={}; public static boolean fail=false; public static int calls=0;
 public MediaCodecList(int kind){calls++; if(fail)throw new IllegalStateException();} public MediaCodecInfo[] getCodecInfos(){return infos;} }''',
'android/media/MediaCodecInfo.java': '''package android.media; public class MediaCodecInfo {
 public String name="vendor.hevc",mime="video/hevc"; public boolean software=false,encoder=false,hardware=true;
 public CodecCapabilities caps=new CodecCapabilities(); public String getName(){return name;} public String[] getSupportedTypes(){return new String[]{mime};}
 public boolean isEncoder(){return encoder;} public boolean isHardwareAccelerated(){return hardware;} public boolean isSoftwareOnly(){return software;}
 public CodecCapabilities getCapabilitiesForType(String s){return caps;}
 public static class CodecProfileLevel {public int profile,level; public CodecProfileLevel(int p,int l){profile=p;level=l;}}
 public static class CodecCapabilities {
  public static final String FEATURE_SecurePlayback="secure",FEATURE_TunneledPlayback="tunneled";
  public CodecProfileLevel[] profileLevels={new CodecProfileLevel(2,1<<16)};
  public VideoCapabilities video=new VideoCapabilities(); public boolean requires=false,format=true;
  public boolean isFeatureRequired(String s){return requires;} public VideoCapabilities getVideoCapabilities(){return video;}
  public boolean isFormatSupported(MediaFormat f){if(f.values.containsKey("frame-rate"))throw new AssertionError("API21 frame-rate bug");return format;}
 }
 public static class VideoCapabilities {
  public int calls=0; public double lastRate; public int lastWidth,lastHeight;
  public boolean isSizeSupported(int w,int h){return w<=3840&&h<=2160;}
  public boolean areSizeAndRateSupported(int w,int h,double r){calls++;lastRate=r;lastWidth=w;lastHeight=h;return isSizeSupported(w,h)&&r<=(w>1920?30:60);}
  public android.util.Range<Integer> getBitrateRange(){return new android.util.Range<>(1,100000000);}
 }
}''',
PKG+'/HdrCapabilities.java': '''package com.alexmercerind.media_kit_video; public class HdrCapabilities {
 public static java.util.Map<String,Object> get(android.content.Context c,android.view.Display d){java.util.Map<String,Object> m=new java.util.HashMap<>();m.put("p5Pipeline",true);return m;}
}''',
}
HARNESS = '''package com.alexmercerind.media_kit_video;
import java.util.*; import android.media.*; import android.content.*; import android.view.*;
public class QueryTest {
 static int passed=0;
 static void check(boolean b,String m){if(!b)throw new AssertionError(m);passed++;}
 static Map<String,Object> source(String codec,int w,int h,double fps){Map<String,Object>s=new HashMap<>();s.put("key",codec+w+h+fps);s.put("codec",codec);s.put("width",w);s.put("height",h);s.put("frameRate",fps);return s;}
 static Map<String,Object> query(Context c,Display d,Object target,Map<String,Object>... src){Map<String,Object>q=new HashMap<>();q.put("schema",1);q.put("target",target);q.put("sources",Arrays.asList(src));return VideoRouteCapabilities.get(c,d,q);}
 static Map match(Map q,int i){return (Map)((List)q.get("sources")).get(i);}
 static Map decoder(Map q,int i){return (Map)((List)match(q,i).get("decoders")).get(0);}
 static void support(Map q,String v){check(v.equals(decoder(q,0).get("support")),"expected "+v+" got "+q);}
 static Map<String,Object> target(String kind){Map<String,Object>t=new HashMap<>();t.put("kind",kind);return t;}
 public static void main(String[]args){
 Context c=new Context();Display main=new Display(0),external=new Display(7);main.types=new int[]{1,2};external.types=new int[]{3};c.manager.displays.put(0,main);c.manager.displays.put(7,external);
 MediaCodecInfo info=new MediaCodecInfo();MediaCodecList.infos=new MediaCodecInfo[]{info};
 Map<String,Object>s=source("hvc1.2.4.L153.B0",3840,2160,30);
 Map q=query(c,external,null,s);support(q,"supported");check("notRequested".equals(((Map)q.get("display")).get("status")),"no default display");
 check(info.caps.video.calls==1&&info.caps.video.lastWidth==3840,"joint query used");
 support(query(c,external,null,source("hvc1.2.4.L153.B0",3840,2160,60)),"unsupported");
 support(query(c,external,null,source("hvc1.2.4.L153.B0",1920,1080,60)),"supported");
 support(query(c,external,null,source("hvc1.2.4.L153.B0",3840,2160,30000.0/1001)),"supported");
 check(info.caps.video.lastRate==30000.0/1001,"fraction preserved");
 Map missing=new HashMap(s);missing.remove("frameRate");support(query(c,external,null,missing),"unknown");
 info.caps.profileLevels=new MediaCodecInfo.CodecProfileLevel[]{new MediaCodecInfo.CodecProfileLevel(1,1<<16)};support(query(c,external,null,s),"unsupported");
 info.caps.profileLevels=new MediaCodecInfo.CodecProfileLevel[0];support(query(c,external,null,s),"unknown");
 info.caps.profileLevels=new MediaCodecInfo.CodecProfileLevel[]{new MediaCodecInfo.CodecProfileLevel(2,1<<14)};support(query(c,external,null,s),"unsupported");
 info.caps.profileLevels=new MediaCodecInfo.CodecProfileLevel[]{new MediaCodecInfo.CodecProfileLevel(2,1<<16)};
 check(VideoRouteCapabilities.levelSupports("video/hevc",1<<16,153,true)==0,"main tier cannot prove high");
 check(VideoRouteCapabilities.levelSupports("video/hevc",1<<17,153,true)==1,"high tier");
 check(VideoRouteCapabilities.levelSupports("video/avc",2,10,false)==1,"AVC1b above1");
 check(VideoRouteCapabilities.levelSupports("video/avc",2,11,false)==0,"AVC1b below1.1");
 q=query(c,external,target("applicationView"),s);check(Integer.valueOf(7).equals(((Map)q.get("display")).get("displayId")),"application not default");
 q=query(c,external,target("defaultDisplay"),s);check(Integer.valueOf(0).equals(((Map)q.get("display")).get("displayId")),"explicit default");
 Map<String,Object>t=target("nativeDisplay");t.put("platform","android");t.put("displayId",99);q=query(c,external,t,s);check("unresolved".equals(((Map)q.get("display")).get("status")),"missing display no fallback");
 t.put("displayId",7);q=query(c,external,t,s);check(Integer.valueOf(7).equals(((Map)q.get("display")).get("displayId")),"explicit external");
 t.put("platform","windows");q=query(c,external,t,s);check("unresolved".equals(((Map)q.get("display")).get("status")),"namespace");
 t=target("flutterView");t.put("live",true);t.put("implicit",false);q=query(c,external,t,s);check("unresolved".equals(((Map)q.get("display")).get("status")),"nonimplicit no ID cast");
 t.put("implicit",true);q=query(c,external,t,s);check(Integer.valueOf(7).equals(((Map)q.get("display")).get("displayId")),"attached implicit");
 MediaCodecList.fail=true;q=query(c,external,null,s);check(Boolean.FALSE.equals(match(q,0).get("censusComplete")),"query failure not empty success");MediaCodecList.fail=false;
 MediaCodecList.calls=0;query(c,external,null,s,source("avc1.640028",1920,1080,30));check(MediaCodecList.calls==1,"batch scans once");
 android.os.Build.VERSION.SDK_INT=21;support(query(c,external,null,s),"supported");check("unknown".equals(decoder(query(c,external,null,s),0).get("kind")),"pre29 hardware unknown");
 android.os.Build.VERSION.SDK_INT=34;info.software=true;check("software".equals(decoder(query(c,external,null,s),0).get("kind")),"software distinct");info.software=false;
 info.caps.requires=true;support(query(c,external,null,s),"unsupported");info.caps.requires=false;
 info.name="vendor.dv";info.mime="video/dolby-vision";info.caps.profileLevels=new MediaCodecInfo.CodecProfileLevel[]{new MediaCodecInfo.CodecProfileLevel(32,256)};
 support(query(c,external,null,source("dvh1.08.06",1920,1080,30)),"unsupported");
 info.caps.profileLevels=new MediaCodecInfo.CodecProfileLevel[]{new MediaCodecInfo.CodecProfileLevel(256,256)};
 support(query(c,external,null,source("dvh1.08.06",1920,1080,30)),"supported");check("nativeDv".equals(decoder(query(c,external,null,source("dvh1.08.06",1920,1080,30)),0).get("path")),"DV role");
 Map<String,Object>conflict=new HashMap<>(s);conflict.put("profile",1);boolean threw=false;try{query(c,external,null,conflict);}catch(IllegalArgumentException e){threw=true;}check(threw,"profile conflict");
 Map<String,Object>bad=new HashMap<>(s);bad.put("frameRate",Double.NaN);threw=false;try{query(c,external,null,bad);}catch(IllegalArgumentException e){threw=true;}check(threw,"nonfinite rate");
 Map unknown=query(c,external,null,source("future.codec",1920,1080,30));check(Boolean.FALSE.equals(match(unknown,0).get("censusComplete")),"unmapped codec unknown");
 System.out.println("host_query_assertions_passed="+passed);
 }
}'''

class AndroidQueryTest(unittest.TestCase):
    def test_current_production_query_with_host_fixtures(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name, text in STUBS.items():
                p=root/name; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(text)
            production=ROOT/'media_kit_video/android/src/main/java'/PKG
            for name in ('VideoSourceSpec.java','VideoRouteCapabilities.java'):
                (root/PKG/name).write_bytes((production/name).read_bytes())
            (root/PKG/'QueryTest.java').write_text(HARNESS)
            subprocess.run(['javac','-d',str(root/'classes'),*[str(p) for p in root.rglob('*.java')]],check=True)
            subprocess.run(['java','-ea','-cp',str(root/'classes'),'com.alexmercerind.media_kit_video.QueryTest'],check=True)

if __name__=='__main__': unittest.main(verbosity=2)
