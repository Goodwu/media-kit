/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved. Use of this source code is governed by MIT license that can be found in LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.util.Log;

import java.util.ArrayList;
import java.util.HashSet;

/**
 * MpvOwnerBroker
 * --------------
 * Dart-independent owner registry for native mpv handles.
 *
 * media_kit registers every mpv client handle here at creation. When a host
 * destroys the FlutterEngine without Dart-side disposal, the engine-detach
 * teardown clears each handle's wakeup callback through JNI while the
 * NativeCallable trampoline backing it is still mapped. Without this, the
 * isolate teardown invalidates that trampoline and the next mpv wakeup from
 * a still-playing player calls freed executable memory.
 */
public final class MpvOwnerBroker {
    private static final String TAG = "MpvOwnerBroker";

    private static final HashSet<Long> handles = new HashSet<>();

    private MpvOwnerBroker() {}

    public static void register(long ctx) {
        synchronized (handles) {
            handles.add(ctx);
        }
        Log.i(TAG, "register: ctx=0x" + Long.toHexString(ctx));
    }

    public static void unregister(long ctx) {
        synchronized (handles) {
            handles.remove(ctx);
        }
        Log.i(TAG, "unregister: ctx=0x" + Long.toHexString(ctx));
    }

    /**
     * Engine-detach teardown. The wakeup callback of every registered handle
     * is cleared synchronously (while the NativeCallable trampoline backing
     * it is still mapped, and before the Dart isolate teardown), then the
     * handles are terminated on a background thread so the platform thread
     * never blocks on mpv joining its own playback threads.
     */
    public static void onEngineDetach() {
        final ArrayList<Long> pending;
        synchronized (handles) {
            pending = new ArrayList<>(handles);
        }
        for (final Long ctx : pending) {
            try {
                nativeClearWakeupCallback(ctx);
            } catch (Throwable e) {
                Log.e(TAG, "onEngineDetach clearWakeup", e);
            }
        }
        if (pending.isEmpty()) {
            return;
        }
        final Thread terminator = new Thread(() -> {
            for (final Long ctx : pending) {
                try {
                    nativeTerminateDestroy(ctx);
                } catch (Throwable e) {
                    Log.e(TAG, "onEngineDetach terminate", e);
                }
            }
            synchronized (handles) {
                handles.removeAll(pending);
            }
            Log.i(TAG, "onEngineDetach terminated=" + pending.size());
        }, "mpv_owner_broker");
        terminator.setDaemon(true);
        terminator.start();
    }

    private static native void nativeClearWakeupCallback(long ctx);

    private static native void nativeTerminateDestroy(long ctx);

    static {
        System.loadLibrary("media_kit_video_hdr_bridge");
    }
}
