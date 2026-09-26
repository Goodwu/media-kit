/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video.platformview;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.common.MethodChannel;

import android.util.Log;
import java.util.Objects;
import java.util.HashMap;
import java.util.concurrent.ConcurrentHashMap;

/**
 * A factory class responsible for creating platform video views that can be embedded in a Flutter
 * app.
 */
public class PlatformVideoViewFactory extends PlatformViewFactory {
    private static final String TAG = "PlatformVideoViewFactory";
    private final MethodChannel channel;
    private final ConcurrentHashMap<Long, PlatformVideoView> views = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<SurfaceOwner, PlatformVideoView> surfaceOwners = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<SurfaceOwner, Integer> liveSurfaceGenerations =
            new ConcurrentHashMap<>();
    private final java.util.Set<ControllerOwner> terminatedControllers =
            java.util.Collections.newSetFromMap(new ConcurrentHashMap<ControllerOwner, Boolean>());
    // An engine detach is not proof that libmpv stopped using a Surface. Keep
    // factories with unresolved owners reachable so a new engine cannot
    // overwrite their identity and GC cannot hide an unsafe native leak.
    private static final java.util.Set<PlatformVideoViewFactory> detachedFactories =
            java.util.Collections.newSetFromMap(
                    new ConcurrentHashMap<PlatformVideoViewFactory, Boolean>());

    private static final class ControllerOwner {
        final long handle;
        final int generation;

        ControllerOwner(long handle, int generation) {
            this.handle = handle;
            this.generation = generation;
        }

        @Override
        public boolean equals(Object other) {
            if (this == other) return true;
            if (!(other instanceof ControllerOwner)) return false;
            final ControllerOwner owner = (ControllerOwner) other;
            return handle == owner.handle && generation == owner.generation;
        }

        @Override
        public int hashCode() {
            return Objects.hash(handle, generation);
        }
    }

    private static final class SurfaceOwner {
        final long handle;
        final int generation;
        final int viewId;

        SurfaceOwner(long handle, int generation, int viewId) {
            this.handle = handle;
            this.generation = generation;
            this.viewId = viewId;
        }

        @Override
        public boolean equals(Object other) {
            if (this == other) return true;
            if (!(other instanceof SurfaceOwner)) return false;
            final SurfaceOwner owner = (SurfaceOwner) other;
            return handle == owner.handle && generation == owner.generation && viewId == owner.viewId;
        }

        @Override
        public int hashCode() {
            return Objects.hash(handle, generation, viewId);
        }
    }

    public boolean setColorSpace(long handle, String transfer) {
        // Every live view for a controller has the same output transfer. A
        // previously selected view may disappear before Dart rebinds a
        // survivor, so apply the policy to all live Surfaces.
        boolean found = false;
        boolean applied = true;
        for (java.util.Map.Entry<SurfaceOwner, Integer> entry : liveSurfaceGenerations.entrySet()) {
            if (entry.getKey().handle != handle) continue;
            final PlatformVideoView view = surfaceOwners.get(entry.getKey());
            if (view == null) continue;
            found = true;
            applied &= view.setColorSpace(transfer);
        }
        return found && applied;
    }

    public String releaseSurface(
            long handle,
            int generation,
            int viewId,
            int surfaceGeneration,
            long wid) {
        final SurfaceOwner owner = new SurfaceOwner(handle, generation, viewId);
        final PlatformVideoView view = surfaceOwners.get(owner);
        if (view == null) return "ownerMissing";
        return view.releaseSurface(surfaceGeneration, wid);
    }

    public boolean releaseSurfaceOwner(
            long handle,
            int generation,
            int viewId,
            int surfaceGeneration,
            long wid) {
        final SurfaceOwner owner = new SurfaceOwner(handle, generation, viewId);
        final PlatformVideoView view = surfaceOwners.get(owner);
        if (view == null) return true;
        if (!view.acknowledgeSurfaceRelease(surfaceGeneration, wid)) return false;
        // Do not remove the owner here. The ACK response itself may be lost;
        // keeping the per-generation tombstone makes the complete exchange
        // idempotent. markPlayerTerminated is the registry GC barrier.
        return true;
    }

    public boolean markPlayerTerminated(long handle, int generation) {
        final ControllerOwner controller = new ControllerOwner(handle, generation);
        terminatedControllers.add(controller);
        boolean released = true;
        for (java.util.Map.Entry<SurfaceOwner, PlatformVideoView> entry : surfaceOwners.entrySet()) {
            final SurfaceOwner owner = entry.getKey();
            if (owner.handle != handle || owner.generation != generation) continue;
            final PlatformVideoView view = entry.getValue();
            if (view.releaseAllSurfacesAfterProducerTermination()) {
                surfaceOwners.remove(owner, view);
                liveSurfaceGenerations.remove(owner);
                views.remove(handle, view);
            } else {
                released = false;
            }
        }
        if (surfaceOwners.isEmpty()) detachedFactories.remove(this);
        return released;
    }

    public void onEngineDetached() {
        // This is fail-closed leak isolation, not lifecycle completion. With
        // no producer-termination proof it is unsafe to release a JNI Surface.
        if (!surfaceOwners.isEmpty()) detachedFactories.add(this);
        for (java.util.Map.Entry<SurfaceOwner, PlatformVideoView> entry : surfaceOwners.entrySet()) {
            final SurfaceOwner owner = entry.getKey();
            if (!terminatedControllers.contains(new ControllerOwner(owner.handle, owner.generation))) {
                Log.e(TAG, "Retaining Surface owner without producer-termination proof: handle="
                        + owner.handle + ", generation=" + owner.generation + ", viewId=" + owner.viewId);
            }
        }
    }

    private void remove(long handle, PlatformVideoView view) {
        views.remove(handle, view);
        // View disposal is not a producer-termination proof. Keep the owner
        // and its ACK tombstones until markPlayerTerminated completes.
        if (surfaceOwners.isEmpty()) detachedFactories.remove(this);
    }

    /**
     * Constructs a new PlatformVideoViewFactory.
     *
     * @param channel The MethodChannel used to communicate with Flutter side.
     */
    public PlatformVideoViewFactory(@NonNull MethodChannel channel) {
        super(StandardMessageCodec.INSTANCE);
        this.channel = channel;
    }

    /**
     * Creates a new instance of platform view.
     *
     * @param context The context in which the view is running.
     * @param id The unique identifier for the view.
     * @param args The arguments for creating the view.
     * @return A new instance of PlatformVideoView.
     */
    @NonNull
    @Override
    public PlatformView create(@NonNull Context context, int id, @Nullable Object args) {
        @SuppressWarnings("unchecked")
        final java.util.Map<String, Object> params = (java.util.Map<String, Object>) Objects.requireNonNull(args);
        final long handle = ((Number) Objects.requireNonNull(params.get("handle"))).longValue();
        final int generation = ((Number) Objects.requireNonNull(params.get("generation"))).intValue();
        final int width = ((Number) Objects.requireNonNull(params.get("width"))).intValue();
        final int height = ((Number) Objects.requireNonNull(params.get("height"))).intValue();
        final String initialDataSpace = (String) params.get("dataspace");
        final String initialPixelFormat = (String) params.get("pixelFormat");

        Log.i(TAG, "Creating PlatformVideoView for handle: " + handle);
        final PlatformVideoView view = new PlatformVideoView(context, handle, width, height, initialDataSpace,
            initialPixelFormat,
            (event) -> {});
        final SurfaceOwner owner = new SurfaceOwner(handle, generation, id);
        surfaceOwners.put(owner, view);
        view.setOnSurfaceEvent((surfaceEvent) -> {
            if (terminatedControllers.contains(new ControllerOwner(handle, generation))) {
                if (view.releaseAllSurfacesAfterProducerTermination()) {
                    surfaceOwners.remove(owner, view);
                    liveSurfaceGenerations.remove(owner);
                    views.remove(handle, view);
                } else {
                    Log.e(TAG, "Terminal Surface release failed: handle=" + handle
                            + ", generation=" + generation + ", viewId=" + id);
                }
                return;
            }
            final HashMap<String, Object> event = new HashMap<>();
            event.put("handle", handle);
            event.put("wid", surfaceEvent.wid);
            event.put("generation", generation);
            event.put("viewId", id);
            event.put("surfaceGeneration", surfaceEvent.generation);
            // Fullscreen transitions may construct more than one PlatformView
            // before either receives a Surface. Publish the view that actually
            // acquired a Surface; Dart resolves competing owners by view and
            // Surface generation, and explicitly stops the prior producer.
            if (surfaceEvent.destroyed) {
                liveSurfaceGenerations.remove(owner, surfaceEvent.generation);
            } else {
                liveSurfaceGenerations.put(owner, surfaceEvent.generation);
                views.put(handle, view);
            }
            final boolean cleanup = surfaceEvent.destroyed;
            channel.invokeMethod(
                cleanup ? "PlatformVideoView.SurfaceDestroyed" : "PlatformVideoView.SurfaceAvailable",
                event);
        });
        view.setOnDispose(() -> remove(handle, view));
        return view;
    }
}
