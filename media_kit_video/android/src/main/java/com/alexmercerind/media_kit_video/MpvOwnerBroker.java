/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.util.Log;

import io.flutter.plugin.common.BinaryMessenger;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;

/**
 * MpvOwnerBroker
 * --------------
 * Dart-independent owner registry for native mpv handles.
 *
 * media_kit registers every mpv client handle here at creation, tagged with
 * the BinaryMessenger (engine) that owns it. When a host destroys one
 * FlutterEngine without Dart-side disposal, that engine's detach clears the
 * wakeup callback of its own handles through JNI while the NativeCallable
 * trampoline backing them is still mapped. Handles owned by other engines in
 * the same process (add-to-app, FlutterEngineGroup, background engines) keep
 * running: without this scoping, any engine detach would terminate every
 * player in the process and leave the surviving engines' Dart side holding
 * freed mpv handles.
 */
public final class MpvOwnerBroker {
    private static final String TAG = "MpvOwnerBroker";

    // Each FlutterEngine has its own BinaryMessenger instance, so the
    // messenger identity is the engine grouping key.
    private static final HashMap<BinaryMessenger, HashSet<Long>> handlesByEngine = new HashMap<>();

    private MpvOwnerBroker() {}

    public static void register(BinaryMessenger engine, long ctx) {
        synchronized (handlesByEngine) {
            handlesByEngine.computeIfAbsent(engine, k -> new HashSet<>()).add(ctx);
        }
        Log.i(TAG, "register: ctx=0x" + Long.toHexString(ctx));
    }

    public static void unregister(long ctx) {
        synchronized (handlesByEngine) {
            // A handle lives in exactly one engine set, but scan every set:
            // unregister arrives on whatever engine the Dart dispose ran on.
            for (final HashSet<Long> handles : handlesByEngine.values()) {
                handles.remove(ctx);
            }
        }
        Log.i(TAG, "unregister: ctx=0x" + Long.toHexString(ctx));
    }

    /**
     * Engine-detach teardown for one engine. The wakeup callback of every
     * handle that engine registered is cleared synchronously (while the
     * NativeCallable trampoline backing it is still mapped, and before the
     * Dart isolate teardown), then the handles are terminated on a
     * background thread so the platform thread never blocks on mpv joining
     * its own playback threads.
     */
    public static void onEngineDetach(BinaryMessenger engine) {
        final ArrayList<Long> pending;
        synchronized (handlesByEngine) {
            final HashSet<Long> owned = handlesByEngine.remove(engine);
            pending = owned == null ? new ArrayList<>() : new ArrayList<>(owned);
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
