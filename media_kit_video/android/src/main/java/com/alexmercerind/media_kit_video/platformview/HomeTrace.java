/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video.platformview;

import android.util.Log;

/**
 * Default-off HOME-return bridge timeline diagnostics ({@code MKS-HOME-TRACE}).
 *
 * <p>The P0 forensic round ran this instrumentation unconditionally on every
 * surface callback, factory create and authorization entry; it is now
 * retained behind a process-lifetime switch read exactly once at class load:
 * {@code adb shell setprop debug.mks.home_trace 1} (before the app process
 * starts) enables it. When disabled, every call site is a single
 * constant-foldable branch — zero logging and zero string building on the
 * hot path. Logs only; no control-flow change. realtime_ms is comparable
 * with the Dart DateTime.now().millisecondsSinceEpoch and the native
 * CLOCK_REALTIME column; mono_ms is SystemClock.uptimeMillis(). Trace lines
 * never carry the raw owner token, only its presence.</p>
 */
final class HomeTrace {

    /** Static-cached switch: read once at class load, then folded at call sites. */
    static final boolean ENABLED = readEnabled();

    private HomeTrace() {}

    static void emit(String msg) {
        Log.i("MKS-HOME-TRACE", "rt=" + System.currentTimeMillis()
                + " mono=" + android.os.SystemClock.uptimeMillis()
                + " tid=" + android.os.Process.myTid()
                + " thr=" + Thread.currentThread().getName()
                + " java " + msg);
    }

    private static boolean readEnabled() {
        try {
            // android.os.SystemProperties is a hidden API: reflection keeps
            // this compilable against the public SDK surface (and lets the
            // JVM host harness default to off when the class is absent).
            final Class<?> systemProperties = Class.forName("android.os.SystemProperties");
            final Object value = systemProperties.getMethod("get", String.class)
                    .invoke(null, "debug.mks.home_trace");
            return "1".equals(value);
        } catch (Throwable ignored) {
            return false;
        }
    }
}
