package com.alexmercerind.media_kit_android_dataspace_vendor;

import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.alexmercerind.media_kit_video.platformview.PlatformVideoView;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding;

/**
 * Registers the vendor dataspace extension with the core library when the
 * engine attaches.
 *
 * <p>Registration is gated by a read-only check: on any device that does
 * not exactly match the validated firmware, this plugin neither registers
 * an extension nor loads the native library.
 */
public class MediaKitAndroidDataspaceVendorPlugin implements FlutterPlugin {
    private static final String TAG = "MediaKitDataspaceVendor";

    @Nullable
    private PlatformVideoView.SurfaceDataSpaceExt registered;
    private boolean slotTakenOver;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        if (registered != null) {
            return; // Already attached; idempotent.
        }
        // Read-only gates first: no registration and no native library load
        // on any other device. Devices are mutually exclusive.
        LyaPqDataSpaceExt lya = new LyaPqDataSpaceExt();
        if (lya.isApplicable()) {
            PlatformVideoView.setSurfaceDataSpaceExt(lya);
            registered = lya;
            return;
        }
        LgPqDataSpaceExt lg = new LgPqDataSpaceExt();
        if (lg.isApplicable()) {
            PlatformVideoView.setSurfaceDataSpaceExt(lg);
            registered = lg;
            return;
        }
        Log.i(TAG, "device not applicable; extension not registered");
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (registered == null) {
            return;
        }
        if (registered instanceof LgPqDataSpaceExt) {
            ((LgPqDataSpaceExt) registered).clearVisual278Experiments();
        }
        registered = null;
        // The core exposes a single static slot without an ownership query.
        // Clear it only while this plugin is still the registrant; an app
        // that replaced the slot with its own wrapper (e.g. diagnostics
        // chaining) announces the hand-off via takeOverSlot() and then owns
        // unregistration itself.
        if (!slotTakenOver) {
            PlatformVideoView.setSurfaceDataSpaceExt(null);
        }
        slotTakenOver = false;
    }

    /**
     * The extension this plugin registered with the core library, or
     * {@code null} when the device gate failed (nothing was registered).
     */
    @Nullable
    public LyaPqDataSpaceExt registeredExtension() {
        return registered instanceof LyaPqDataSpaceExt ? (LyaPqDataSpaceExt) registered : null;
    }

    /**
     * The extension this plugin registered (LYA or LG), or {@code null}
     * when the device gate failed for both.
     */
    @Nullable
    public PlatformVideoView.SurfaceDataSpaceExt registeredAny() {
        return registered;
    }

    /**
     * Called by an app that replaces this plugin's slot registration with
     * its own wrapper: the plugin then leaves the slot alone on engine
     * detach instead of clearing someone else's registration.
     */
    public void takeOverSlot() {
        slotTakenOver = true;
    }
}
