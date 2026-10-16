# W1 managed output surface lifecycle (vendor side) / 2026-10-16

The production library path gains a device-neutral managed output surface
ledger in `LgPqDataSpaceExt`, separate from the experiment owner ledger:

- `registerManagedOutputSurface(surface, handle, generation, surfaceGeneration)`
  — per-surface records; no experiment token, no retired set.
- `armManagedOutputSurface(surface, handle, generation)` — the native
  YUV-diag arm keyed by the device-neutral managed owner key derived from
  (handle, generation); the native side stores only the derived key and
  never validates any Java ledger.
- `disarmManagedOutputSurface(surface)` / `unregisterManagedOutputSurface(surface)`
  — the library's end-of-attempt cleanup and the surface-destroy path.
- `enableOwnerLifetime(handle, token)` — the production entry whose
  non-conformant acceptance derives from this device's own
  `pqPresentationYuvWindow` declaration; the route lock is enforced
  library-side by the arm admission.
- The two-argument dataspace apply is authorized for registered managed
  surfaces (the values still pass `supportsDataSpace`).

The experiment owner ledger and the visual278 consent remain untouched
for the lab entry. Java sequence on the view: register → arm → initial
dataspace → surface event → Dart producer activation (the arm strictly
precedes mpv's EGL window creation).
