# P2a: original per-media options and opaque EDL

Continue only compat/piliplus-zero-change-20261018. Baseline 0024a369 completed all five original-app T1 jobs AND the aggregate in run 39143954233. This does not certify the new P2 source below. Native freshness and ordinary-open automatic HDR routing are still open.

## Verified functional gap

Original PiliPlus 6a5171f supplies cache, cache-secs, demuxer-hysteresis-secs, demuxer-max-bytes, demuxer-max-back-bytes and lavfi-complex through Media.extras. Its resolved original media_kit (My-Responsitories/media-kit 73771ec, real.dart _add) passes these as loadfile per-entry options. The compatibility playback core before this patch uses loadlist / loadfile without options; it ignores extras. The app wraps the whole normalization graph in double quotes for the old key/value parser.

## Implementation scope

Freeze the finite known option set before queuing open/add. Keep all unrelated extras as application data and never admit decoder/output/script ownership through this map. Convert the old whole-value quoting once, then serialize each value using mpv's UTF-8 byte-length suboption escaping, preventing commas or equals from escaping into a second option. Reject malformed declared values without modifying the existing playback. The native loadfile per-entry mechanism applies/restores the option scope; no global Dart rollback values are introduced. Support client API versions both before and after the insertion-index argument. EDL stays one opaque URI, and is loaded directly rather than reconstructed or split into a text playlist.

Source publication is guarded by the exact previous core blob 56c8e827373e7ff27e9c2b981bfe3a0f13f5e7b2. The resulting reviewed core blob must be 0fe15c816436f9c8462751434c223ef26272cc0b. The publisher only touches SDK source and records the integration; it is not an application build-time patch. Tests and T1 run on the committed result, not the staging request.

## Required tests

Pure contracts cover buffer options, normalization quoting, UTF-8 and delimiter escaping, option map immutability, same-URI entries, unknown metadata, both API argument layouts and NUL/malformed inputs. Real Linux libmpv tests must show ordinary open/add per-entry application AND restoration, plus successful loading of an opaque Unicode EDL. System libmpv in this test validates API/option semantics only, not latest fork-native source provenance. Re-run the full media_kit_video suite and all five original-app builds after integration.

This is not all of P2: HTTP headers/source identity, full operation cancellation/rebuild sequencing, separate audio/video EDL playback and feature/device acceptance remain separate. Do not broaden HDR gates, rewrite hwdec preferences, or declare automatic routing implemented.
