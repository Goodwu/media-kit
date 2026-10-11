# B3 native selection checkpoint / MK-ROUTING-20261011

Continue Goodwu/media-kit PR4 and Goodwu/PiliPlusX PR1 on routing/MK-ROUTING-20261011. Existing B2b source query and DASH integration are done and host-tested; never redo them.

A third repository is now registered for the necessary narrow native repair: **Goodwu/FFmpeg PR1**, canonical branch **routing/MK-ROUTING-20261011**, based on the existing latest native branch lg-p84-d1-vui-fix-20261010 at d4bb79394b98d6247887e169998778474f43887e. Registration commit b6163ec6. The first native repair has not previously been implemented elsewhere. Read its actual ref and handoff before resuming.

Scope: P8 decoder lookup must use the same profile256 as configure, not MIME-only; unknown/unsupported native profile fails closed; empty DV profile lists cannot authorize strict native consumption. Ordinary decoder selection remains unchanged. No new Dart/mpv name-selection protocol, pixel/color/RPU changes or local configure cleanup.

Extend the already committed tool/routing_native_audit rather than creating a competing harness. Added empty-list-before-valid, only-empty, reversed-list, native P5, ordinary HEVC and no-decoder cases. The run always extracts current source regions; stale historical source fragments are not bundled. Fixtures do not prove real JNI exceptions, codec configure/start, dynamic metadata delivery or panel HDR.

At this checkpoint, media-kit98a349 B1c fallback production fix is committed; source CI511 passed and one old second-review test still expected false acceptance of failed hardware. e4f7af3c repairs that test into a genuine valid initial reclassification followed by a second failed decoder, with no third attempt or verified event. The new test and expanded native harness require an independent current-head rerun.

Parallel Android7 fixes are integrated via media-kit8b80f452 and Appd0926b31, preserving both histories. Appc6c72369 supplies missing required ref inputs to Apple reusable workflows; Build now starts actual jobs. App85 existing analyzer infos and other legacy Build constraints remain open. All primary PRs stay draft. Full latest-source native APK and actual devices remain unaccepted.
