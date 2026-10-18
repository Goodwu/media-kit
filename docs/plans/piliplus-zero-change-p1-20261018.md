# R3 execution update: P1 typed player compatibility

Continue only `compat/piliplus-zero-change-20261018`, based on `867c48afc84db408bb3d131345f4c7a6a3b5796b`. Routing remains `0a212785a87df88a0a583cd5f1f526630d5c4e81`. Do not recreate the branch, weaken HDR review, or patch original PiliPlus.

The previous T1 run 39054877275 reached real pub resolution and original-app analysis/build. The old override-only native event loop is proven absent from that resolved graph. Linux compilation still failed on actual Player/API/FFI differences, not on an accepted compiler-error baseline. Existing SimpleVideo/subtitle/staging work must be retained. The older root handoff describes only P0a and is not a complete record of the later P0b/typed-view commits.

This slice keeps NativePlayer as the existing implementation rather than inserting a broad new wrapper hierarchy. The safe operations get unambiguous internal names: getPropertyAsync, screenshotBytes, PlayerInitializer and mpvBindings. A code-only migration updates SDK call sites without rewriting option names, literals or comments. UI-only synchronous getProperty covers the actually consumed finite property set; it never authorizes a route. Width/height expose legacy zero while videoWidth/videoHeight preserve nullable native evidence. A paired size stream does not own an independent playback state.

The legacy screenshot API creates a real caller-owned ui.Image from a safe PNG snapshot; pure Dart retains a byte extension. Android's old attachment argument is an alias preserving every nested option and rejecting contradictions. setMediaHeader records synchronous defaults for the next on_load; per-media headers win.

Encoding handles have a separate static byte-pointer facade. Playback continues using the existing asynchronous event pump. Raw encoding event delivery uses nonblocking same-isolate polling and deep-owned payloads; dispose cancels polling synchronously, destroy does not race a client waiter, and a callback may destroy its native handle without invalidating its event copy. Unknown payloads fail rather than exposing borrowed memory. Native integration and event-copy tests are added; no successful native test is claimed before it runs.

The one-shot materializer is guarded by the exact input blobs, touches SDK paths only, and publishes actual source before the next T1 matrix. If source publication is rejected, stop and use the connector; do not treat a build-time patch as completed source integration. No forced update is permitted. Its marker prevents repeating the migration.

Still pending: ordinary open automatic routing, stable output ownership under automatic rebuilds, EDL/media-option parity, full source-fresh native build closure, feature/device/HDR acceptance. Compile success alone does not close these gates. Existing sdrEmbed default, preferCopy, capability tri-state and reviewed GL tradeoffs are unchanged.
