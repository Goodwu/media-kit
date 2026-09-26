/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.util.Log;

import java.lang.reflect.Method;
import java.util.HashSet;
import java.util.Locale;
import java.util.Objects;

/**
 * Manages global object references through JNI.
 * This class provides functionality to create and delete global references to Java objects
 * for use in native code.
 */
public class GlobalObjectRefManager {
    private static final String TAG = "GlobalObjectRefManager";
    private static final Method newGlobalObjectRefMethod;
    private static final Method deleteGlobalObjectRefMethod;
    // Track live allocations, not historical pointer values. JNI may reuse a
    // deleted global-reference address; a history set would then suppress the
    // legitimate delete for the newer allocation. Owners remain responsible
    // for exactly-once release of each allocation generation.
    private static final HashSet<Long> activeGlobalObjectRefs = new HashSet<>();

    static {
        try {
            // com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper is part of package:media_kit_libs_android_video & package:media_kit_libs_android_audio packages.
            // Use reflection to invoke methods of com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper.
            Class<?> mediaKitAndroidHelperClass = Class.forName("com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper");
            newGlobalObjectRefMethod = mediaKitAndroidHelperClass.getDeclaredMethod("newGlobalObjectRef", Object.class);
            deleteGlobalObjectRefMethod = mediaKitAndroidHelperClass.getDeclaredMethod("deleteGlobalObjectRef", long.class);
            newGlobalObjectRefMethod.setAccessible(true);
            deleteGlobalObjectRefMethod.setAccessible(true);
        } catch (Throwable e) {
            Log.i("media_kit", "package:media_kit_libs_android_video missing. Make sure you have added it to pubspec.yaml.");
            throw new RuntimeException("Failed to initialize com.alexmercerind.media_kit_video.GlobalObjectRefManager.", e);
        }
    }

    /**
     * Creates a new global reference to the given object.
     *
     * @param object The object to create a global reference for.
     * @return The global reference ID, or 0 if creation failed.
     */
    public static synchronized long newGlobalObjectRef(Object object) {
        Log.i(TAG, String.format(Locale.ENGLISH, "newGlobalRef: object = %s", object));
        try {
            final long reference = (long) Objects.requireNonNull(newGlobalObjectRefMethod.invoke(null, object));
            if (reference != 0) {
                activeGlobalObjectRefs.add(reference);
            }
            return reference;
        } catch (Throwable e) {
            Log.e(TAG, "newGlobalRef", e);
            return 0;
        }
    }

    /**
     * Deletes a live global reference by its ID.
     * Owners provide generation-aware exactly-once release; this live set
     * rejects duplicate deletes without retaining reusable pointer values.
     *
     * @param ref The global reference ID to delete.
     */
    public static synchronized boolean deleteGlobalObjectRef(long ref) {
        if (!activeGlobalObjectRefs.contains(ref)) {
            Log.i(TAG, String.format(Locale.ENGLISH, "deleteGlobalObjectRef: ref = %d NOT ACTIVE", ref));
            return false;
        }
        Log.i(TAG, String.format(Locale.ENGLISH, "deleteGlobalObjectRef: ref = %d", ref));
        try {
            deleteGlobalObjectRefMethod.invoke(null, ref);
            activeGlobalObjectRefs.remove(ref);
            return true;
        } catch (Throwable e) {
            Log.e(TAG, "deleteGlobalObjectRef", e);
            return false;
        }
    }
}
