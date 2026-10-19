# Direction B pre-initialization and failed creation review

The original video page has a separate cover/manual-play overlay above plPlayer. initPlayerIfNeeded can pre-initialize a local file while autoPlay is false. Consequently neither videoState nor autoPlay may gate mounting an existing routed binding: Android route verification needs the surface. Remove both mount gates, leave the original cover/manual-play overlay and playback intent unchanged. This is a display integration change, not enabling automatic playback.

The reviewed seven-file patch also resets a failed shared initialization Future for retry; closes an unpublished binding/raw player on initialization error; retains only failed/closing owners for a later cleanup attempt; and checks the source request again before invoking onInit after asynchronous initialization. Do not put active, currently initializing owners in the retired collection: another instance must not destroy them. Gallery failed owners survive widget disposal, and the routed video child handles an absent binding while the parent is unmounting.

Updated patch SHA256: 2109c3c44c8f93febf04636d557f863d6c05b15fa5a1287ed3f86f2a8474443b. Seven-file scope unchanged. Applied locally to a verified-source clone; exact pre/postimage and diff digest checks passed. Local clone commits are synthetic and are not the upstream app identity (actual captured upstream is 2eaeeb731462dad92246809d5b5ac716c671736b). Full T1B analysis/build and runtime feature/device gates remain required.

SDK tests at 57a5e991 passed (1024 pass, 3 skip). Runtime generation fix d42f9ed5 and its additional regression are newer and require their own test result. Do not claim the preceding green test run certifies that change.
