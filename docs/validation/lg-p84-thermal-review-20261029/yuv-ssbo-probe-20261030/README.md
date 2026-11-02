# Fragment SSBO + YUV output capability probe (not executed)

Only NDK27.2/API24 source compilation and arm64 PIE ELF verification were performed. No device operation or playback build was performed by this worker. Independent review is required before running.

Frozen binary: `build/lg-yuv-ssbo-20261029T190845Z-22315/lg_yuv_ssbo_probe`

SHA256: `b4ad1d0a3dae9ad07a1b7c2b09c417c755d39481f2d68f3d65d55c43495e40f1`.

The standalone probe owns its EGL contexts. CLI: `lg_yuv_ssbo_probe /new/result.txt`; result is O_EXCL0600, starts with a flushed running marker, and a 30 second alarm bounds execution. Host runner should additionally apply a bounded timeout and verify process exit.

Distinct gates:

1. RGB pbuffer context actual GLES>=3.1, fragment SSBO blocks/bindings and maximum block size.
2. Real fragment SSBO execution over16x16 pixels: atomic per-pixel invocation count, deterministic exact-bit payload and per-position sentinel; buffer barrier + fence + zero-timeout polling + map after signaled; every count must equal1, no errors/unmap failure. This is RGB execution only.
3. Compile/link actual `layout(yuv)`+SSBO program in the RGB context. Success is compilation only, not YUV execution.
4. Attempt config49/native visual0x7fa30c04 and ImageReader consumer. Context creation matches the production GLES client-version2 request/fallback. Query limits and compile again in that context, draw same YUV program and validate SSBO as above. No swap or NV12 byte readback is used; even a full pass only proves that the tested YUV draw and fragment SSBO can execute together, not surface quantization or panel output.

`rgb_ssbo_executed`, `yuv_ssbo_compiled`, and `yuv_ssbo_executed` are separate booleans. Exit0 requires all gates and cleanup; unsupported ImageReader still produces exit2 and `yuv_ssbo_executed=0`, even if the first three gates passed. Existing ImageReader evidence (`../yuv-fusion-probe-20261030/device-v3/`) predicts config49 window creation may return EGL_BAD_MATCH, so no YUV execution is assumed.

## If standalone ImageReader window remains unsupported

A different process cannot borrow the player's owned `ANativeWindow`/EGL context. Do not replace the producer with a pbuffer or pretend an RGB framebuffer is a YUV target.

The minimal next probe belongs inside the test application's already-current, already-validated production YUV context. It should be default off and run only once per surface generation on an explicitly paused quality-test frame. It must query the fragment SSBO limits there, compile the exact YUV+SSBO shader, use the existing legal drawable, and validate independent buffer coverage/payload before claiming execution support. Test programs and bindings need state save/restore (current program, VAO, framebuffer, viewport/scissor, blend/depth/stencil/cull/dither, color mask, SSBO generic and indexed binding); do not destroy or rebind the application's EGL context/surface. Preserve context error ownership; explicit probe errors must go through the existing error-epoch contract. Only after successful drawing/cleanup should the normal current frame be redrawn and swapped once. Failure disables the probe and keeps ordinary rendering.

The test executes a synthetic shader. It does not validate real-video shader equivalence, raw YUV/NV12 bytes, panel colour/brightness, performance, power or heat. SSBO insertion may change compiler optimization and GPU scheduling; runs are not valid performance A/B.
