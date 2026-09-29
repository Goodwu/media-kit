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
    }

    public static void unregister(long ctx) {
        synchronized (handles) {
            handles.remove(ctx);
        }
    }

    /**
     * Clears the wakeup callback of every registered handle. Called from
     * plugin engine-detach, before any Dart-side teardown could have run.
     */
    public static void onEngineDetach() {
        synchronized (handles) {
            for (final Long ctx : new ArrayList<>(handles)) {
                try {
                    nativeClearWakeupCallback(ctx);
                } catch (Throwable e) {
                    Log.e(TAG, "onEngineDetach", e);
                }
            }
        }
    }

    private static native void nativeClearWakeupCallback(long ctx);

    static {
        System.loadLibrary("media_kit_video_hdr_bridge");
    }
}
