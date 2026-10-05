package com.example.androidhdrprobe;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaPlayer;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.Environment;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.view.Display;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public final class ProbeActivity extends Activity implements SurfaceHolder.Callback {
    private static final int REQUEST_STORAGE = 41;
    private TextView status;
    private SurfaceView surfaceView;
    private Uri mediaUri;
    private MediaPlayer player;
    private File report;
    private boolean prepared;
    private boolean surfaceReady;
    private boolean startPending;
    private int seekSeconds;
    private String backend = "player";
    private String colorMode = "passthrough";
    private String explicitCodecName;
    private String renderMode = "timed";
    private boolean foreground = true;
    private CodecSession codecSession;
    private final Handler positionHandler = new Handler(Looper.getMainLooper());
    private final Runnable positionTicker = new Runnable() {
        @Override public void run() {
            if (player != null && prepared) {
                log("player.positionMs=" + safePosition(player) + " playing=" + safeIsPlaying(player));
                positionHandler.postDelayed(this, 1000);
            }
        }
    };

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        buildUi();
        report = new File(getExternalFilesDir(null), "report.txt");
        log("=== LG HDR / MediaCodec probe ===");
        log("time=" + new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).format(new Date()));
        log("device=" + Build.MANUFACTURER + " " + Build.MODEL + " product=" + Build.PRODUCT + " sdk=" + Build.VERSION.SDK_INT);
        log("report=" + report.getAbsolutePath());
        queryDisplay();
        queryCodecs();
        tryLoadLibrary(getIntent());
        consumeIntent(getIntent());
        updateStatus("能力报告已写入\n" + report.getAbsolutePath() + "\n选择 HDR 视频 Intent 或在启动参数中传 file:///sdcard/Download/... ");
    }

    private void buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.BLACK);
        surfaceView = new SurfaceView(this);
        surfaceView.setKeepScreenOn(true);
        root.addView(surfaceView, new LinearLayout.LayoutParams(-1, 0, 1));
        surfaceView.getHolder().addCallback(this);
        ScrollView scroll = new ScrollView(this);
        status = new TextView(this);
        status.setTextColor(Color.WHITE);
        status.setTextSize(14);
        status.setPadding(12, 8, 12, 8);
        scroll.addView(status);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        Button play = new Button(this);
        play.setText("播放 / 继续");
        play.setOnClickListener(new View.OnClickListener() { @Override public void onClick(View v) { startPlayback(); } });
        root.addView(play, new LinearLayout.LayoutParams(-1, -2));
        setContentView(root);
    }

    private void queryDisplay() {
        try {
            Display d = getWindowManager().getDefaultDisplay();
            log("display=" + d.getName() + " size=" + d.getWidth() + "x" + d.getHeight());
            if (Build.VERSION.SDK_INT >= 24) {
                Display.HdrCapabilities h = d.getHdrCapabilities();
                if (h == null) { log("display.hdrCapabilities=null"); return; }
                int[] types = h.getSupportedHdrTypes();
                StringBuilder names = new StringBuilder();
                for (int t : types) {
                    if (names.length() > 0) names.append(',');
                    names.append(hdrName(t)).append('(').append(t).append(')');
                }
                log("display.hdr.types=" + names);
                log("display.hdr.maxLuminance=" + h.getDesiredMaxLuminance());
                log("display.hdr.maxAverageLuminance=" + h.getDesiredMaxAverageLuminance());
                log("display.hdr.minLuminance=" + h.getDesiredMinLuminance());
            }
        } catch (Throwable t) { log("display.query.error=" + t); }
    }

    private static String hdrName(int t) {
        switch (t) {
            case 1: return "DOLBY_VISION";
            case 2: return "HDR10";
            case 3: return "HLG";
            case 4: return "HDR10_PLUS";
            default: return "UNKNOWN";
        }
    }

    private void queryCodecs() {
        try {
            MediaCodecInfo[] codecs = new MediaCodecList(MediaCodecList.ALL_CODECS).getCodecInfos();
            int count = 0;
            for (MediaCodecInfo codec : codecs) {
                if (codec.isEncoder()) continue;
                for (String mime : codec.getSupportedTypes()) {
                    String m = mime.toLowerCase(Locale.US);
                    if (!(m.contains("avc") || m.contains("hevc") || m.contains("dolby") || m.contains("vp9"))) continue;
                    count++;
                    log("codec=" + codec.getName() + " mime=" + mime);
                    try {
                        MediaCodecInfo.CodecCapabilities caps = codec.getCapabilitiesForType(mime);
                        for (MediaCodecInfo.CodecProfileLevel pl : caps.profileLevels) {
                            log("  profileLevel profile=0x" + Integer.toHexString(pl.profile) + " level=0x" + Integer.toHexString(pl.level) + " tier=" + hevcTier(m, pl.level));
                        }
                        MediaCodecInfo.VideoCapabilities vc = caps.getVideoCapabilities();
                        if (vc != null) {
                            log("  videoSizeRange=" + vc.getSupportedWidths() + "x" + vc.getSupportedHeights());
                            probeRate(vc, 1920, 1080, 30);
                            probeRate(vc, 1920, 1080, 60);
                            probeRate(vc, 3840, 2160, 30);
                            probeRate(vc, 3840, 2160, 60);
                            log("  performancePoints=unavailable(API24)");
                        }
                    } catch (Throwable t) { log("  codec.capabilities.error=" + t); }
                }
            }
            log("codec.matchingDecoderMimeCount=" + count);
        } catch (Throwable t) { log("codec.query.error=" + t); }
    }

    private void probeRate(MediaCodecInfo.VideoCapabilities vc, int w, int h, double fps) {
        try { log("  supports=" + w + "x" + h + "@" + fps + ":" + vc.areSizeAndRateSupported(w, h, fps)); }
        catch (Throwable t) { log("  supports=" + w + "x" + h + "@" + fps + ":error:" + t.getClass().getSimpleName()); }
    }

    private static String hevcTier(String mime, int level) {
        if (!mime.toLowerCase(Locale.US).contains("hevc")) return "n/a";
        if (level == MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel1 || level == MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel2 ||
            level == MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel21 || level == MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel3 ||
            level == MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel31 || level == MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel4 ||
            level == MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel41 || level == MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel5 ||
            level == MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel51 || level == MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel52 ||
            level == MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel6 || level == MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel61 ||
            level == MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel62) return "main";
        if (level == MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel1 || level == MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel2 ||
            level == MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel21 || level == MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel3 ||
            level == MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel31 || level == MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel4 ||
            level == MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel41 || level == MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel5 ||
            level == MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel51 || level == MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel52 ||
            level == MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel6 || level == MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel61 ||
            level == MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel62) return "high";
        return "unknown";
    }

    @Override protected void onNewIntent(android.content.Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        tryLoadLibrary(intent);
        consumeIntent(intent);
    }

    private void tryLoadLibrary(android.content.Intent intent) {
        if (intent == null) return;
        String path = intent.getStringExtra("loadLibraryPath");
        if (path == null || path.length() == 0) return;
        log("library.load.request path=" + path);
        final String libraryPath = path;
        Thread loader = new Thread(new Runnable() {
            @Override public void run() {
                try {
                    System.load(libraryPath);
                    log("library.load.success path=" + libraryPath);
                } catch (Throwable t) {
                    log("library.load.failure path=" + libraryPath + " error=" + t.getClass().getName() + ":" + t.getMessage());
                }
            }
        }, "probe-library-loader");
        loader.start();
    }

    private void consumeIntent(android.content.Intent intent) {
        if (intent == null) return;
        Uri uri = intent.getData();
        String path = intent.getStringExtra("path");
        if (uri == null && path != null) uri = Uri.fromFile(new File(path));
        if (uri == null) return;
        if (player != null) releasePlayer("new intent");
        stopCodec("new intent");
        backend = intent.getStringExtra("backend");
        if (backend == null) backend = "player";
        colorMode = intent.getStringExtra("color_mode");
        if (colorMode == null) colorMode = "passthrough";
        renderMode = intent.getStringExtra("render_mode");
        if (renderMode == null) renderMode = "timed";
        explicitCodecName = intent.getStringExtra("codec_name");
        if (explicitCodecName != null && explicitCodecName.length() == 0) explicitCodecName = null;
        if (!(backend.equals("player") || backend.equals("codec")) ||
            !(colorMode.equals("passthrough") || colorMode.equals("pq") || colorMode.equals("sdr")) ||
            !(renderMode.equals("timed") || renderMode.equals("boolean"))) {
            mediaUri = null;
            startPending = false;
            log("play.intent.invalid backend=" + backend + " colorMode=" + colorMode + " renderMode=" + renderMode);
            updateStatus("参数错误：backend=player|codec，color_mode=passthrough|pq|sdr，render_mode=timed|boolean");
            return;
        }
        mediaUri = uri;
        seekSeconds = intent.getIntExtra("seek_seconds", intent.getIntExtra("seek", 0));
        log("play.intent action=" + intent.getAction() + " uri=" + mediaUri + " seekSeconds=" + seekSeconds + " backend=" + backend + " colorMode=" + colorMode + " explicitCodecName=" + explicitCodecName + " renderMode=" + renderMode);
        startPending = true;
        if (Build.VERSION.SDK_INT >= 23 && checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.READ_EXTERNAL_STORAGE}, REQUEST_STORAGE);
            updateStatus("等待存储读取授权：\n" + uri);
            return;
        }
        prepareSelectedBackend();
    }

    @Override public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_STORAGE) {
            log("permission.readExternal=" + (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED));
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) prepareSelectedBackend();
            else updateStatus("读取存储权限被拒绝；报告已生成，可用 adb shell pm grant 授权后重启播放。");
        }
    }

    private void prepareSelectedBackend() {
        if ("codec".equals(backend)) prepareCodec();
        else preparePlayer();
    }

    private void preparePlayer() {
        if (!surfaceReady || mediaUri == null || player != null) return;
        try {
            player = new MediaPlayer();
            player.setOnPreparedListener(new MediaPlayer.OnPreparedListener() {
                @Override public void onPrepared(MediaPlayer mp) {
                    prepared = true;
                    log("player.prepared durationMs=" + mp.getDuration() + " video=" + mp.getVideoWidth() + "x" + mp.getVideoHeight());
                    if (seekSeconds > 0) {
                        int target = seekSeconds * 1000;
                        mp.seekTo(target);
                        log("player.seek requestedMs=" + target);
                    }
                    updateStatus("prepared " + mp.getVideoWidth() + "x" + mp.getVideoHeight() + " duration=" + mp.getDuration() + "ms\n" + mediaUri);
                    if (startPending) startPlayback();
                }
            });
            player.setOnVideoSizeChangedListener(new MediaPlayer.OnVideoSizeChangedListener() { @Override public void onVideoSizeChanged(MediaPlayer mp, int w, int h) { log("player.videoSize=" + w + "x" + h); } });
            player.setOnInfoListener(new MediaPlayer.OnInfoListener() { @Override public boolean onInfo(MediaPlayer mp, int what, int extra) { log("player.info what=" + what + " extra=" + extra + " positionMs=" + safePosition(mp)); return false; } });
            player.setOnErrorListener(new MediaPlayer.OnErrorListener() { @Override public boolean onError(MediaPlayer mp, int what, int extra) { log("player.error what=" + what + " extra=" + extra + " positionMs=" + safePosition(mp)); updateStatus("播放错误 what=" + what + " extra=" + extra); return true; } });
            player.setOnCompletionListener(new MediaPlayer.OnCompletionListener() { @Override public void onCompletion(MediaPlayer mp) { log("player.completed positionMs=" + safePosition(mp)); updateStatus("播放结束 position=" + safePosition(mp) + "ms"); } });
            player.setDisplay(surfaceView.getHolder());
            player.setDataSource(this, mediaUri);
            log("player.prepareAsync uri=" + mediaUri);
            player.prepareAsync();
            updateStatus("正在准备\n" + mediaUri);
        } catch (Throwable t) {
            log("player.setup.error=" + t);
            updateStatus("播放器初始化失败：" + t);
            releasePlayer("setup error");
        }
    }

    private void startPlayback() {
        if ("codec".equals(backend)) {
            startPending = true;
            prepareCodec();
            return;
        }
        if (player == null) { preparePlayer(); return; }
        if (!prepared) { startPending = true; updateStatus("等待 MediaPlayer prepared"); return; }
        try { player.start(); startPending = false; log("player.started positionMs=" + safePosition(player)); positionHandler.removeCallbacks(positionTicker); positionHandler.post(positionTicker); updateStatus("playing position=" + safePosition(player) + "ms"); }
        catch (Throwable t) { log("player.start.error=" + t); updateStatus("启动播放失败：" + t); }
    }

    @Override public void surfaceCreated(SurfaceHolder holder) {
        surfaceReady = true;
        log("surface.created format=" + holder.getSurfaceFrame());
        if (player != null) player.setDisplay(holder);
        else prepareSelectedBackend();
    }
    @Override public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) { log("surface.changed format=" + format + " size=" + width + "x" + height); }
    @Override public void surfaceDestroyed(SurfaceHolder holder) { surfaceReady = false; stopCodec("surface destroyed"); log("surface.destroyed positionMs=" + safePosition(player)); }

    @Override protected void onResume() { super.onResume(); foreground = true; }
    @Override protected void onPause() { super.onPause(); foreground = false; if ("codec".equals(backend)) startPending = false; stopCodec("activity pause"); positionHandler.removeCallbacks(positionTicker); if (player != null && safeIsPlaying(player)) { player.pause(); log("player.paused positionMs=" + safePosition(player)); } }
    @Override protected void onDestroy() { startPending = false; stopCodec("activity destroy"); releasePlayer("activity destroy"); super.onDestroy(); }

    private void prepareCodec() {
        if (!foreground || !startPending || !surfaceReady || mediaUri == null || codecSession != null) return;
        Surface surface = surfaceView.getHolder().getSurface();
        if (!surface.isValid()) { log("codec.surface.invalid"); return; }
        CodecSession session = new CodecSession(mediaUri, surface, colorMode, explicitCodecName, renderMode, Math.max(0, seekSeconds) * 1000000L);
        codecSession = session;
        startPending = false;
        session.start();
    }

    private void stopCodec(String reason) {
        if (codecSession != null) codecSession.requestStop(reason);
    }

    // The decoder thread owns codec/extractor. The stop lock serializes surface submission
    // with teardown requests; an old session cannot submit after requestStop returns.
    private final class CodecSession extends Thread {
        final Uri uri;
        final Surface surface;
        final String mode;
        final String requestedCodecName;
        final String renderMode;
        final long seekUs;
        volatile boolean stopped;
        String stopReason = "completed";
        long inputCount;
        long outputCount;
        long renderCount;
        long lastPtsUs = -1;
        long firstPtsUs = -1;
        long firstReleaseNs;
        long lastProgressMs;
        long backwardsPts;
        long lateFrames;
        long maxLatenessUs;

        CodecSession(Uri uri, Surface surface, String mode, String requestedCodecName, String renderMode, long seekUs) {
            super("probe-codec-surface");
            this.uri = uri;
            this.surface = surface;
            this.mode = mode;
            this.requestedCodecName = requestedCodecName;
            this.renderMode = renderMode;
            this.seekUs = seekUs;
        }

        synchronized void requestStop(String reason) {
            if (!stopped) {
                stopped = true;
                stopReason = reason;
                interrupt();
            }
        }

        @Override public void run() {
            MediaExtractor extractor = null;
            MediaCodec codec = null;
            boolean codecStarted = false;
            boolean outputEos = false;
            try {
                log("codec.session.start uri=" + uri + " colorMode=" + mode + " seekUs=" + seekUs + " renderMode=" + renderMode);
                extractor = new MediaExtractor();
                extractor.setDataSource(ProbeActivity.this, uri, null);
                MediaFormat format = null;
                int track = -1;
                for (int i = 0; i < extractor.getTrackCount(); i++) {
                    MediaFormat candidate = extractor.getTrackFormat(i);
                    logFormat("codec.input.track[" + i + "]", candidate);
                    String mime = candidate.getString(MediaFormat.KEY_MIME);
                    if (track < 0 && mime != null && mime.startsWith("video/")) {
                        track = i;
                        format = candidate;
                    }
                }
                if (track < 0) throw new IOException("No video track");
                extractor.selectTrack(track);
                if (seekUs > 0) extractor.seekTo(seekUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC);
                log("codec.input.selectedTrack=" + track + " firstSampleUs=" + extractor.getSampleTime());
                // Preserve every extractor key, including real hdr-static-info; no invented metadata.
                if ("pq".equals(mode) || "sdr".equals(mode)) {
                    format.setInteger(MediaFormat.KEY_COLOR_STANDARD, "pq".equals(mode) ? 6 : 1);
                    format.setInteger(MediaFormat.KEY_COLOR_TRANSFER, "pq".equals(mode) ? 6 : 3);
                    format.setInteger(MediaFormat.KEY_COLOR_RANGE, 2);
                }
                logFormat("codec.configure.format", format);
                if ("sdr".equals(mode)) log("codec.control=SDR_ASPECT_OVERRIDE_ONLY; bitstream unchanged (PQ stays PQ), not HDR output or tone mapping; hdr-static-info retained if present, HAL may still treat as HDR");
                String codecName;
                if (requestedCodecName != null) {
                    codecName = requestedCodecName;
                    log("codec.selection=explicit name=" + codecName +
                        "; bypass findDecoderForFormat declaration/profile/level matching; extracted format unchanged except requested color_mode aspects; no fallback");
                } else {
                    codecName = new MediaCodecList(MediaCodecList.ALL_CODECS).findDecoderForFormat(format);
                    log("codec.selection=finder result=" + codecName);
                    if (codecName == null) throw new IOException("No decoder for configured format; configure not attempted");
                }
                codec = MediaCodec.createByCodecName(codecName);
                log("codec.name=" + codec.getName());
                synchronized (this) {
                    if (stopped) return;
                    if (!surface.isValid()) { requestStop("surface invalid before configure"); return; }
                    codec.configure(format, surface, null, 0);
                    codec.start();
                    codecStarted = true;
                }
                updateCodecStatus("codec playing " + codecName + " " + mode);
                boolean inputEos = false;
                MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
                long lastInputPtsUs = 0;
                lastProgressMs = SystemClock.elapsedRealtime();
                while (!stopped && !outputEos) {
                    if (!inputEos) {
                        int index = codec.dequeueInputBuffer(10000);
                        if (index >= 0) {
                            ByteBuffer buffer = codec.getInputBuffer(index);
                            if (buffer == null) throw new IOException("Null input buffer");
                            buffer.clear();
                            int size = extractor.readSampleData(buffer, 0);
                            if (size < 0) {
                                codec.queueInputBuffer(index, 0, 0, lastInputPtsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                                inputEos = true;
                                log("codec.input.eos count=" + inputCount + " lastPtsUs=" + lastInputPtsUs);
                            } else {
                                int sampleFlags = extractor.getSampleFlags();
                                if ((sampleFlags & MediaExtractor.SAMPLE_FLAG_ENCRYPTED) != 0)
                                    throw new IOException("Encrypted samples not supported by this probe");
                                // API24 has no partial-frame queue contract; fail closed rather than reinterpret it.
                                if ((sampleFlags & 4) != 0) throw new IOException("Partial samples not supported on API24");
                                lastInputPtsUs = extractor.getSampleTime();
                                int flags = (sampleFlags & MediaExtractor.SAMPLE_FLAG_SYNC) != 0 ? MediaCodec.BUFFER_FLAG_KEY_FRAME : 0;
                                codec.queueInputBuffer(index, 0, size, lastInputPtsUs, flags);
                                inputCount++;
                                extractor.advance();
                            }
                        }
                    }
                    int index = codec.dequeueOutputBuffer(info, 10000);
                    if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        logFormat("codec.output.format", codec.getOutputFormat());
                    } else if (index >= 0) {
                        outputCount++;
                        boolean eos = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
                        boolean config = (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0;
                        // Surface output size can be zero for real frames. Empty EOS has no frame to render.
                        boolean render = !config && (!eos || info.size > 0) && info.presentationTimeUs >= seekUs;
                        if (render) {
                            long ptsUs = info.presentationTimeUs;
                            if (firstPtsUs < 0) { firstPtsUs = ptsUs; firstReleaseNs = System.nanoTime(); }
                            long releaseNs = firstReleaseNs + (ptsUs - firstPtsUs) * 1000L;
                            waitForPresentation(releaseNs);
                            synchronized (this) {
                                if (stopped) break;
                                if (!surface.isValid()) { requestStop("surface invalid before submission"); break; }
                                long lateUs = Math.max(0, (System.nanoTime() - releaseNs) / 1000L);
                                if (lateUs > 50000) lateFrames++;
                                maxLatenessUs = Math.max(maxLatenessUs, lateUs);
                                if ("boolean".equals(renderMode))
                                    codec.releaseOutputBuffer(index, true);
                                else
                                    codec.releaseOutputBuffer(index, releaseNs);
                                renderCount++;
                            }
                            if (lastPtsUs >= 0 && ptsUs < lastPtsUs) backwardsPts++;
                            if (renderCount <= 3) log("codec.frame count=" + renderCount + " ptsUs=" + ptsUs + " flags=" + info.flags + " size=" + info.size + " renderMode=" + renderMode);
                            lastPtsUs = ptsUs;
                        } else {
                            synchronized (this) {
                                if (stopped) break;
                                codec.releaseOutputBuffer(index, false);
                            }
                        }
                        outputEos = eos;
                        if (eos) log("codec.output.eos ptsUs=" + info.presentationTimeUs);
                    }
                    long nowMs = SystemClock.elapsedRealtime();
                    if (nowMs - lastProgressMs >= 1000) {
                        log("codec.progress input=" + inputCount + " output=" + outputCount + " scheduled=" + renderCount +
                            " lastPtsUs=" + lastPtsUs + " backwardsPts=" + backwardsPts + " lateOver50ms=" + lateFrames + " maxLateUs=" + maxLatenessUs + " renderMode=" + renderMode);
                        updateCodecStatus("codec " + mode + " scheduled=" + renderCount + " pts=" + lastPtsUs / 1000 + "ms");
                        lastProgressMs = nowMs;
                    }
                }
            } catch (InterruptedException e) {
                if (!stopped) { synchronized (this) { stopReason = "interrupted"; } log("codec.error=" + e); updateCodecStatus("codec interrupted"); }
            } catch (Throwable t) {
                synchronized (this) { if (!stopped) stopReason = "error"; }
                log("codec.error=" + t.getClass().getName() + ":" + t.getMessage() + " stopped=" + stopped);
                if (t instanceof MediaCodec.CodecException) {
                    MediaCodec.CodecException e = (MediaCodec.CodecException) t;
                    log("codec.error.diagnostic=" + e.getDiagnosticInfo() + " recoverable=" + e.isRecoverable() + " transient=" + e.isTransient());
                }
                updateCodecStatus("codec failed: " + t);
            } finally {
                if (codec != null) {
                    if (codecStarted) try { codec.stop(); log("codec.stop.success"); } catch (Throwable t) { log("codec.stop.error=" + t); }
                    try { codec.release(); log("codec.release.success"); } catch (Throwable t) { log("codec.release.error=" + t); }
                }
                if (extractor != null) try { extractor.release(); log("extractor.release.success"); } catch (Throwable t) { log("extractor.release.error=" + t); }
                log("codec.session.end reason=" + stopReason + " eos=" + outputEos + " input=" + inputCount +
                    " output=" + outputCount + " scheduled=" + renderCount + " lastPtsUs=" + lastPtsUs + " backwardsPts=" + backwardsPts + " lateOver50ms=" + lateFrames + " maxLateUs=" + maxLatenessUs + " renderMode=" + renderMode);
                final boolean reachedEos = outputEos;
                positionHandler.post(new Runnable() {
                    @Override public void run() {
                        if (codecSession != CodecSession.this) return;
                        codecSession = null;
                        if (reachedEos) updateStatus("codec EOS scheduled=" + renderCount + " pts=" + lastPtsUs / 1000 + "ms");
                        if (foreground) prepareSelectedBackend();
                    }
                });
            }
        }

        private void waitForPresentation(long timeNs) throws InterruptedException {
            while (!stopped) {
                long remainingNs = timeNs - System.nanoTime();
                if (remainingNs <= 0) return;
                // Short interruptible waits avoid queueing seconds ahead into a dying Surface.
                Thread.sleep(Math.max(1, Math.min(10, remainingNs / 1000000L)));
            }
        }

        private void updateCodecStatus(final String value) {
            positionHandler.post(new Runnable() {
                @Override public void run() { if (codecSession == CodecSession.this && !stopped) status.setText(value); }
            });
        }
    }

    private void logFormat(String prefix, MediaFormat format) {
        log(prefix + "=" + format.toString());
        for (String key : new String[]{"csd-0", "csd-1", "csd-2", "hdr-static-info"}) {
            if (!format.containsKey(key)) continue;
            try {
                ByteBuffer bytes = format.getByteBuffer(key).duplicate();
                StringBuilder hex = new StringBuilder();
                while (bytes.hasRemaining()) hex.append(String.format(Locale.US, "%02x", bytes.get() & 255));
                log(prefix + "." + key + " hex=" + hex);
            } catch (Throwable t) { log(prefix + "." + key + ".error=" + t); }
        }
    }

    private void releasePlayer(String reason) {
        if (player != null) {
            log("player.release reason=" + reason + " positionMs=" + safePosition(player));
            try { player.reset(); player.release(); } catch (Throwable t) { log("player.release.error=" + t); }
            player = null;
        }
        prepared = false;
    }
    private static int safePosition(MediaPlayer mp) { try { return mp == null ? -1 : mp.getCurrentPosition(); } catch (Throwable t) { return -1; } }
    private static boolean safeIsPlaying(MediaPlayer mp) { try { return mp != null && mp.isPlaying(); } catch (Throwable t) { return false; } }

    private synchronized void log(String message) {
        String line = new SimpleDateFormat("HH:mm:ss.SSS", Locale.US).format(new Date()) + " " + message;
        android.util.Log.i("AndroidHdrProbe", line);
        if (report == null) return;
        try (BufferedWriter w = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(report, true), "UTF-8"))) {
            w.write(line); w.newLine();
        } catch (IOException e) { android.util.Log.e("AndroidHdrProbe", "report write failed", e); }
    }
    private void updateStatus(final String value) { if (status != null) status.post(new Runnable() { @Override public void run() { status.setText(value); } }); }
}
