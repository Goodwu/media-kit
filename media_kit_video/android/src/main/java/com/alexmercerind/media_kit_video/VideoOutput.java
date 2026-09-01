/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Surface;

import java.util.Locale;

import io.flutter.view.TextureRegistry;

public class VideoOutput implements TextureRegistry.SurfaceProducer.Callback {
    private static final String TAG = "VideoOutput";
    private static final Handler handler = new Handler(Looper.getMainLooper());

    private long id = 0;
    private long wid = 0;

    private final TextureUpdateCallback textureUpdateCallback;

    private final TextureRegistry.SurfaceProducer surfaceProducer;
    private final TextureRegistry.SurfaceTextureEntry surfaceTextureEntry;
    private final Surface surfaceTextureSurface;

    private final Object lock = new Object();

    VideoOutput(TextureRegistry textureRegistryReference,
            boolean enableSurfaceProducer,
            TextureUpdateCallback textureUpdateCallback) {
        this.textureUpdateCallback = textureUpdateCallback;

        if (enableSurfaceProducer) {
            surfaceProducer = textureRegistryReference.createSurfaceProducer();
            surfaceProducer.setCallback(this);
            surfaceTextureEntry = null;
            surfaceTextureSurface = null;
        } else {
            surfaceProducer = null;
            surfaceTextureEntry = textureRegistryReference.createSurfaceTexture();
            surfaceTextureSurface = new Surface(surfaceTextureEntry.surfaceTexture());
            id = surfaceTextureEntry.id();
            wid = GlobalObjectRefManager.newGlobalObjectRef(surfaceTextureSurface);
            textureUpdateCallback.onTextureUpdate(id, wid, 0, 0);
        }
    }

    public void dispose() {
        synchronized (lock) {
            if (surfaceProducer != null) {
                try {
                    surfaceProducer.getSurface().release();
                } catch (Throwable e) {
                    Log.e(TAG, "dispose", e);
                }
                try {
                    surfaceProducer.release();
                } catch (Throwable e) {
                    Log.e(TAG, "dispose", e);
                }
                onSurfaceCleanup();
            } else {
                textureUpdateCallback.onTextureUpdate(id, 0, 0, 0);
                if (wid != 0) {
                    GlobalObjectRefManager.deleteGlobalObjectRef(wid);
                    wid = 0;
                }
                if (surfaceTextureSurface != null) {
                    surfaceTextureSurface.release();
                }
                if (surfaceTextureEntry != null) {
                    surfaceTextureEntry.release();
                }
            }
        }
    }

    public void setSurfaceSize(int width, int height) {
        setSurfaceSize(width, height, false);
    }

    private void setSurfaceSize(int width, int height, boolean force) {
        synchronized (lock) {
            try {
                if (surfaceProducer == null) {
                    surfaceTextureEntry.surfaceTexture().setDefaultBufferSize(width, height);
                    textureUpdateCallback.onTextureUpdate(id, wid, width, height);
                    return;
                }
                if (!force && surfaceProducer.getWidth() == width && surfaceProducer.getHeight() == height) {
                    return;
                }
                surfaceProducer.setSize(width, height);
                onSurfaceAvailable();
            } catch (Throwable e) {
                Log.e(TAG, "setSurfaceSize", e);
            }
        }
    }

    @Override
    public void onSurfaceAvailable() {
        synchronized (lock) {
            if (surfaceProducer == null) {
                return;
            }
            Log.i(TAG, "onSurfaceAvailable: id=" + id + ", wid=" + wid + ", width=" + surfaceProducer.getWidth() + ", height=" + surfaceProducer.getHeight());
            id = surfaceProducer.id();
            wid = GlobalObjectRefManager.newGlobalObjectRef(surfaceProducer.getSurface());
            textureUpdateCallback.onTextureUpdate(id, wid, surfaceProducer.getWidth(), surfaceProducer.getHeight());
        }
    }

    @Override
    public void onSurfaceCleanup() {
        synchronized (lock) {
            if (surfaceProducer == null) {
                return;
            }
            Log.i(TAG, "onSurfaceCleanup: id=" + id + ", wid=" + wid + ", width=" + surfaceProducer.getWidth() + ", height=" + surfaceProducer.getHeight());
            textureUpdateCallback.onTextureUpdate(id, 0, surfaceProducer.getWidth(), surfaceProducer.getHeight());
            if (wid != 0) {
                final long widReference = wid;
                handler.postDelayed(() -> GlobalObjectRefManager.deleteGlobalObjectRef(widReference), 5000);
            }
        }
    }
}
