# P2b: freeze request headers and playback intervals on native entries

Date: 2026-10-19 (Asia/Singapore). Continue only `compat/piliplus-zero-change-20261018`.

## Confirmed starting point

HEAD `81b6d94028fd6ba55f05e47af9c536c8499fc700` contains current routing `0597c8318ccf50f0824249ceeab310632efb84ab` (compare behind_by=0). T1 run 39145299165 completed/success; all Android, iOS, macOS, Windows, Linux build and output-upload steps and aggregate were success. SDK regression 39145299152 and macOS view contracts 39145299187 were success. These certify exactly that earlier source, not this change. Native-source freshness, automatic routing and device/HDR gates remain open.

## Source-confirmed defect and integrated change

The old on_load reconstituted `Media(uri)` from a global URI cache. Equal-URI entries could therefore use the later entry's headers, and later application defaults could affect queued opens. start/end also came from mutable current[index]. on_unload globally reset these settings instead of relying on per-entry restoration.

Core source is committed at `486d1080f18abb54629da197f09c374b115a16c7`, blob `4f4348f40df74a8fc5622783ce6993974998b4b9`. open/add synchronously freeze validated default/per-media headers and start/end with the existing extras. Native loadfile entries own application and restoration. Original Media references retain resource lifetime and public playlist behavior. Public hooks, event pump and HDR review are unchanged. Invalid maps fail before modifying playback. No header values enter our production diagnostics. Empty resolved headers preserve configured native baseline. Extras cannot introduce arbitrary native ownership/options.

## First real regression and encoding correction

SDK run 39185952681 at f4221f84 ran the complete suite: 1011 pass, 3 skip, 1 failure. Full artifact 12158575451 was downloaded and read (ZIP SHA256 b38767c8620a7fe3c2f4c8169e4b1a5cc1194f8fbe388b83bc75cdea839ff1e8). The failing same-URI HTTP test timed out; other tests did not fail. The initial repeated http-header-fields-append design is invalid: mpv v0.37.0 options/m_option.c parse_keyvalue_list (lines 1690-1694, blob 1b1ac0acd60ff38450e2da1875cccf1fe933cc10) deletes an existing key before appending its new value. Only the last field survives. This is a production encoding defect, not justification to skip/loosen the test.

Corrected encoding uses ONE http-header-fields key. Validated fields are assembled internally with CRLF separators into a single string-list member; commas are escaped for the inner mpv list parser, the whole string is UTF-8 length-quoted for the outer key/value parser. User values still cannot contain CR/LF/NUL. A trailing backslash is followed by CRLF/end rather than a comma delimiter, so it stays literal. mpv/FFmpeg receives the complete header block and native per-file restoration remains automatic. No duplicate map keys or global fallback. Add a unique-key/multiple-backslash pure contract; retain all real-wire assertions.

A diagnostic-only guarded request at bc6dc5e2 was rejected because its preimage hash was transcribed incorrectly; no source change occurred. The new request binds the actually re-read native test blob 59c6bd5acb9c1717ee7f0b0835f164e97572e4b5. It only labels timeouts with synthetic fixture observations and changes no assertions or time budgets.

## Required acceptance

Ten pure contracts cover immutable defaults/overrides, equal URI, UTF-8/commas/backslashes, injection-looking values, bad input, both API layouts and interval semantics. Four real native tests use a loopback HTTP server for equal-URI playlists/replay, queued add, malformed-input preservation, start/end restoration, and authenticated video+audio EDL with both tracks. Native dependency is Linux system libmpv for API semantics only, not latest fork-native provenance. Run complete video regression and five-platform T1 on the actual integrated correction; keep prior failure in history. Source publication/green compilation is not automatic routing or device acceptance.

## Still open

P2 full operation cancellation/rebuild sequencing; P3 ordinary-open automatic routing/no-hint facts/stable output ownership; P4 latest-source native build closure; P5 feature/PiP/screenshot/device/HDR checks. Existing sdrEmbed defaults, copy intent, capability tri-state and accepted GL tradeoffs are unchanged. Original PiliPlus source is not patched.
