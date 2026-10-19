# P2b: freeze request headers and playback intervals on native entries

Date: 2026-10-19 (Asia/Singapore). Continue only `compat/piliplus-zero-change-20261018`.

## Confirmed starting point

HEAD `81b6d94028fd6ba55f05e47af9c536c8499fc700` contains current routing `0597c8318ccf50f0824249ceeab310632efb84ab` (compare behind_by=0). T1 run 39145299165 is completed/success; its Android, iOS, macOS, Windows, Linux build and output-upload steps and aggregate are all success. SDK regression 39145299152 and macOS view contracts 39145299187 also completed/success. These are the old code's results, not certification of this new change. Native-source freshness, automatic routing and device/HDR gates remain open.

## Source-confirmed defect

The existing on_load reconstitutes `Media(uri)` and reads its headers from the global URI cache. Two entries sharing a URL can therefore use the later entry's headers; later application default updates can also affect an already queued open. Start/end similarly come from mutable current[index]. on_unload globally resets headers/start/end instead of leaving per-entry restoration to mpv. This is a request-identity prerequisite for automatic routing, not a new HDR path.

## Change

Capture merged and validated default/per-media headers plus start/end synchronously in ordinary open/add, alongside the already frozen extras. Preserve original Media references for resource lifetime and public current/playlist behavior. Native loadfile entries own the captured fields and restoration. Remove only the late header/interval lookup and unconditional reset blocks; keep public hooks, the current asynchronous event pump, and HDR/decoder review unchanged. Per-file header actions use clear then one append per field, with UTF-8 byte-length key/value escaping; unlike a comma-joined string list, append retains literal commas/backslashes. Unknown extras still cannot become HTTP, time, decoder, VO or script settings. Empty resolved headers add no native override, retaining any configured native baseline. Invalid maps fail before changing playback; no header values are included in our diagnostics.

The exact core preimage is blob `0fe15c816436f9c8462751434c223ef26272cc0b`. The existing guarded publisher commits the source changes; it is not an application build-time patch. Read the resulting receipt and blob before triggering the acceptance run. Do not replay P1 or P2a migrations.

## Required tests

Pure tests: default precedence and snapshot immutability, equal-URI distinct requests, UTF-8/commas/trailing backslashes, injection-looking values, malformed input, both client API layouts, zero/negative/start/end semantics, unchanged extras allowlist. Real native tests: loopback HTTP captures for two same-URI playlist entries and replay, queued add vs later defaults, malformed input preserving current playback, same-URI interval application/restoration, and video+audio EDL with authenticated fields on both requests and both tracks loaded. Native tests use system libmpv for API semantics only, not fork-native source provenance. Re-run the complete video suite and original five-platform build on the integrated source. A green compile does not close automatic-route/device gates.

## Still open

P2 full operation cancellation/rebuild sequencing; P3 automatic ordinary-open routing and no-hint encoded facts, stable output ownership; P4 current-source native closure; P5 feature/PiP/HDR/device verification. Existing sdrEmbed defaults, copy intent, capability tri-state and accepted GL tradeoffs are unchanged. Original PiliPlus is not patched.
