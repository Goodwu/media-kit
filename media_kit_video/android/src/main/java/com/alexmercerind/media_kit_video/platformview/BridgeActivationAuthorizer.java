/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video.platformview;

import java.util.HashMap;
import java.util.Map;

/**
 * Decision logic for the {@code PlatformVideoView.AuthorizeBridgeActivation}
 * channel method (A2 activation barrier): re-initializes the surfacetexture
 * bridge for a still-live view identity after the Dart bind transaction has
 * stopped the previous mpv producer (e.g. after a HOME-return teardown).
 *
 * <p>Request parsing, factory-side owner location, view-side identity checks
 * and result mapping live here as plain Java (no Android imports) so the JVM
 * host test ({@code tool/test_platform_bridge_activation.py}) compiles and
 * executes the REAL parsing, registry lookup, view validation and init call
 * instead of a parallel model (V2 C4 requirement). {@link
 * PlatformVideoViewFactory} and {@link PlatformVideoView} really work through
 * this class; they only supply their live state through the narrow {@link
 * Registry} / {@link Target} facades.</p>
 *
 * <p>Execution contract: the handler completes synchronously on the platform
 * main thread — no worker thread is started, the bridge shutdown is never
 * called from this path. {@code ok=true} covers exactly two answers: the
 * explicit init succeeded for the located owner ({@code code=ok}), or the
 * located view has no bridge owner and nothing was initialized ({@code
 * code=notApplicable} with {@code applicable=false}). {@code ok=true} never
 * indicates that a decoder window was created or that hardware decoding is
 * running. A view without a bridge owner token answers {@code
 * notApplicable} and never loads or initializes the bridge. The raw owner
 * token never appears in any returned message or log line.</p>
 */
public final class BridgeActivationAuthorizer {

    private BridgeActivationAuthorizer() {}

    /** The explicit init succeeded for the located view identity. */
    public static final String CODE_OK = "ok";
    /** The located view has no bridge owner token (non-token routes). */
    public static final String CODE_NOT_APPLICABLE = "notApplicable";
    /** The request identity no longer matches any live view/Surface state. */
    public static final String CODE_STALE_IDENTITY = "staleIdentity";
    /** Malformed or missing channel arguments. */
    public static final String CODE_INVALID_ARGUMENTS = "invalidArguments";
    /** The optional caller-provided token does not match the view owner. */
    public static final String CODE_TOKEN_MISMATCH = "tokenMismatch";
    /** The view owner tuple itself is unusable (empty token, bad generation). */
    public static final String CODE_INVALID_OWNER = "invalidOwner";
    /** Identity matched but the explicit bridge init threw. */
    public static final String CODE_INIT_FAILED = "initFailed";

    /**
     * Injectable seam for {@link MediaCodecSurfaceTextureBridge
     * #ensureInitialized(String, int)}. Production always uses the real
     * static method; the JVM host test injects a recorder so the real
     * plugin/factory/view/authorizer chain runs without the native library.
     */
    public interface BridgeInitializer {
        void ensureInitialized(String ownerToken, int generation);
    }

    /**
     * Narrow read-only registry facade implemented by
     * {@link PlatformVideoViewFactory}: the exact (handle, generation,
     * viewId) owner registry, not the handle-indexed "latest view" map.
     */
    interface Registry {
        boolean isControllerTerminated(long handle, int generation);

        Target locateSurfaceOwner(long handle, int generation, int viewId);

        boolean isLiveSurfaceGeneration(
                long handle, int generation, int viewId, int surfaceGeneration);
    }

    /**
     * Narrow read-only view facade implemented by {@link PlatformVideoView}.
     * Deliberately a package-private class rather than an interface so the
     * raw owner-token accessor never becomes public API on the view.
     */
    abstract static class Target {
        /** View-level checks + init + structured result. */
        abstract Result authorizeActivation(Request request);

        abstract boolean isDisposed();

        abstract long handle();

        abstract int ownerGeneration();

        abstract int viewId();

        abstract int activeSurfaceGeneration();

        abstract long currentWid();

        /** Live JNI reference for a Surface generation, or null. */
        abstract Long surfaceReference(int surfaceGeneration);

        abstract boolean hasValidHolderSurface();

        /** Raw owner token; null when this view has no bridge owner. */
        abstract String ownerToken();

        abstract void initializeOwnerBridge();
    }

    /**
     * Strictly parsed channel request. {@code handle} and {@code wid} use the
     * decimal-string encoding of the existing release channel; the int fields
     * reject floating-point values and out-of-range widths instead of
     * truncating. {@code ownerToken} is optional.
     */
    public static final class Request {
        public final long handle;
        public final int generation;
        public final int viewId;
        public final int surfaceGeneration;
        public final long wid;
        /** Optional caller-provided token; null when absent. */
        public final String ownerToken;

        private Request(long handle, int generation, int viewId,
                int surfaceGeneration, long wid, String ownerToken) {
            this.handle = handle;
            this.generation = generation;
            this.viewId = viewId;
            this.surfaceGeneration = surfaceGeneration;
            this.wid = wid;
            this.ownerToken = ownerToken;
        }

        /**
         * Parses the channel argument map. Any missing field, illegal type
         * (floating point, wrong class) or overflowing value fails closed
         * with {@link IllegalArgumentException} whose message is returned to
         * Dart as {@code invalidArguments}.
         */
        public static Request parse(Object arguments) {
            if (!(arguments instanceof Map)) {
                throw new IllegalArgumentException("arguments must be a map");
            }
            final Map<?, ?> args = (Map<?, ?>) arguments;
            return new Request(
                    parseDecimalLong(args.get("handle"), "handle"),
                    parseStrictInt(args.get("generation"), "generation"),
                    parseStrictInt(args.get("viewId"), "viewId"),
                    parseStrictInt(args.get("surfaceGeneration"), "surfaceGeneration"),
                    parseDecimalLong(args.get("wid"), "wid"),
                    parseOptionalString(args.get("ownerToken")));
        }

        private static long parseDecimalLong(Object value, String field) {
            if (!(value instanceof String)) {
                throw new IllegalArgumentException(field + " must be a decimal string");
            }
            try {
                // Long.parseLong rejects "", "1.5", trailing junk and values
                // outside the 64-bit range (overflow) — no truncation.
                return Long.parseLong((String) value);
            } catch (NumberFormatException error) {
                throw new IllegalArgumentException(
                        field + " is not a valid decimal long");
            }
        }

        private static int parseStrictInt(Object value, String field) {
            if (value instanceof Integer) {
                return (Integer) value;
            }
            if (value instanceof Long) {
                final long widened = (Long) value;
                // Refuse instead of truncating (e.g. 0x100000005 -> 5).
                if (widened < Integer.MIN_VALUE || widened > Integer.MAX_VALUE) {
                    throw new IllegalArgumentException(field + " overflows int range");
                }
                return (int) widened;
            }
            // Double/Float (floating point), BigInteger and anything else are
            // outside the int contract.
            throw new IllegalArgumentException(field + " must be an int");
        }

        private static String parseOptionalString(Object value) {
            if (value == null || value instanceof String) {
                return (String) value;
            }
            throw new IllegalArgumentException("ownerToken must be a string when present");
        }
    }

    /**
     * Structured authorization result; {@link #toMap()} is the exact channel
     * payload. {@code applicable} is true exactly when the located view is a
     * bridge-owner route ({@code notApplicable} and {@code invalidArguments}
     * report false). {@code ok} is true for {@code code=ok} (init succeeded)
     * and for {@code code=notApplicable} (non-owner view: nothing failed and
     * nothing was initialized — but also nothing authorized); every other
     * code reports {@code ok=false}.
     */
    public static final class Result {
        public final boolean applicable;
        public final boolean ok;
        public final String code;
        /** Located view's lgOwnerGeneration; null when no view was located. */
        public final Integer ownerGeneration;
        /** Located view's activeSurfaceGeneration; null when no view was located. */
        public final Integer surfaceGeneration;
        /** Failure description; never contains the raw owner token. */
        public final String message;

        private Result(boolean applicable, boolean ok, String code,
                Integer ownerGeneration, Integer surfaceGeneration,
                String message) {
            this.applicable = applicable;
            this.ok = ok;
            this.code = code;
            this.ownerGeneration = ownerGeneration;
            this.surfaceGeneration = surfaceGeneration;
            this.message = message;
        }

        public static Result ok(int ownerGeneration, int surfaceGeneration) {
            return new Result(true, true, CODE_OK,
                    ownerGeneration, surfaceGeneration, null);
        }

        public static Result notApplicable(int ownerGeneration, int surfaceGeneration) {
            return new Result(false, true, CODE_NOT_APPLICABLE,
                    ownerGeneration, surfaceGeneration, null);
        }

        public static Result staleIdentity(String message,
                Integer ownerGeneration, Integer surfaceGeneration) {
            return new Result(true, false, CODE_STALE_IDENTITY,
                    ownerGeneration, surfaceGeneration, message);
        }

        public static Result invalidArguments(String message) {
            return new Result(false, false, CODE_INVALID_ARGUMENTS,
                    null, null, message);
        }

        public static Result tokenMismatch(int ownerGeneration, int surfaceGeneration) {
            return new Result(true, false, CODE_TOKEN_MISMATCH,
                    ownerGeneration, surfaceGeneration, "owner token mismatch");
        }

        public static Result invalidOwner(String message,
                int ownerGeneration, int surfaceGeneration) {
            return new Result(true, false, CODE_INVALID_OWNER,
                    ownerGeneration, surfaceGeneration, message);
        }

        public static Result initFailed(String message,
                int ownerGeneration, int surfaceGeneration) {
            return new Result(true, false, CODE_INIT_FAILED,
                    ownerGeneration, surfaceGeneration, message);
        }

        public Map<String, Object> toMap() {
            final Map<String, Object> map = new HashMap<>();
            map.put("applicable", applicable);
            map.put("ok", ok);
            map.put("code", code);
            map.put("ownerGeneration", ownerGeneration);
            map.put("surfaceGeneration", surfaceGeneration);
            map.put("message", message);
            return map;
        }
    }

    /**
     * Factory-side flow: parse-validated request in, structured result out.
     * Never throws. Order: terminated controller → exact owner location →
     * live Surface generation → view-level checks and init.
     */
    static Result authorize(Registry registry, Request request) {
        if (registry.isControllerTerminated(request.handle, request.generation)) {
            return Result.staleIdentity("controller generation terminated", null, null);
        }
        final Target view =
                registry.locateSurfaceOwner(request.handle, request.generation, request.viewId);
        if (view == null) {
            return Result.staleIdentity("surface owner missing", null, null);
        }
        if (!registry.isLiveSurfaceGeneration(
                request.handle, request.generation, request.viewId, request.surfaceGeneration)) {
            return Result.staleIdentity("surface generation not live",
                    view.ownerGeneration(), view.activeSurfaceGeneration());
        }
        return view.authorizeActivation(request);
    }

    /**
     * View-level body: owner applicability/validity, full identity match,
     * optional explicit token match, then the real init. Identity mismatches
     * are stale requests (silently abandoned on the Dart side), never
     * degradable init failures.
     */
    static Result checkTarget(Target view, Request request) {
        final int viewOwnerGeneration = view.ownerGeneration();
        final int viewSurfaceGeneration = view.activeSurfaceGeneration();
        // Owner applicability first, BEFORE every identity check: a view
        // without a bridge owner can never be authorized regardless of the
        // request or surface state — including a wid=0 request, a disposed
        // view, or any other stale identity — and the answer must not depend
        // on transient surface churn. notApplicable must not load or
        // initialize the bridge. (Pinned by the host no-token-wid-zero case.)
        final String ownerToken = view.ownerToken();
        if (ownerToken == null) {
            return Result.notApplicable(viewOwnerGeneration, viewSurfaceGeneration);
        }
        if (ownerToken.isEmpty()) {
            return Result.invalidOwner(
                    "owner token is empty", viewOwnerGeneration, viewSurfaceGeneration);
        }
        if (viewOwnerGeneration <= 0) {
            return Result.invalidOwner(
                    "owner generation is not positive", viewOwnerGeneration, viewSurfaceGeneration);
        }
        // Full identity match (controller generation vs per-view surface
        // generation are separate counting domains and checked separately).
        if (view.isDisposed()) {
            return Result.staleIdentity("view disposed",
                    viewOwnerGeneration, viewSurfaceGeneration);
        }
        if (view.handle() != request.handle) {
            return Result.staleIdentity("handle mismatch",
                    viewOwnerGeneration, viewSurfaceGeneration);
        }
        if (viewOwnerGeneration != request.generation) {
            return Result.staleIdentity("controller generation mismatch",
                    viewOwnerGeneration, viewSurfaceGeneration);
        }
        if (view.viewId() != request.viewId) {
            return Result.staleIdentity("viewId mismatch",
                    viewOwnerGeneration, viewSurfaceGeneration);
        }
        if (viewSurfaceGeneration != request.surfaceGeneration) {
            return Result.staleIdentity("active surface generation mismatch",
                    viewOwnerGeneration, viewSurfaceGeneration);
        }
        // A wid=0 request never authorizes (helper-level hard rule); the
        // current wid must be the requested live wid.
        if (request.wid == 0) {
            return Result.staleIdentity("wid=0 is not an activation request",
                    viewOwnerGeneration, viewSurfaceGeneration);
        }
        if (view.currentWid() != request.wid) {
            return Result.staleIdentity("wid mismatch",
                    viewOwnerGeneration, viewSurfaceGeneration);
        }
        // Keyed by surfaceGeneration, not by the controller generation.
        final Long reference = view.surfaceReference(request.surfaceGeneration);
        if (reference == null || reference.longValue() != view.currentWid()) {
            return Result.staleIdentity("surface reference mismatch",
                    viewOwnerGeneration, viewSurfaceGeneration);
        }
        if (!view.hasValidHolderSurface()) {
            return Result.staleIdentity("holder surface invalid",
                    viewOwnerGeneration, viewSurfaceGeneration);
        }
        // Optional explicit caller token must match the view owner exactly.
        if (request.ownerToken != null && !request.ownerToken.equals(ownerToken)) {
            return Result.tokenMismatch(viewOwnerGeneration, viewSurfaceGeneration);
        }
        try {
            view.initializeOwnerBridge();
        } catch (Throwable error) {
            return Result.initFailed(
                    describeThrowable(error, ownerToken),
                    viewOwnerGeneration, viewSurfaceGeneration);
        }
        return Result.ok(viewOwnerGeneration, viewSurfaceGeneration);
    }

    /**
     * Redacted, human-readable description of a bridge-init failure for any
     * log line or channel result. Belt-and-braces redaction: the bridge
     * never embeds the raw token in its exceptions, but the token must not
     * leak even through an unexpected message. Shared with the cold-start
     * owner setter, whose catch must keep its record-not-throw contract
     * without emitting the token.
     */
    static String describeThrowable(Throwable error, String ownerToken) {
        String description = error.getClass().getSimpleName();
        if (error.getMessage() != null) {
            description += ": " + error.getMessage();
        }
        if (ownerToken != null && !ownerToken.isEmpty() && description.contains(ownerToken)) {
            description = description.replace(ownerToken, "<redacted>");
        }
        return description;
    }
}
