# Windows CI mpv fixture A/B

Baseline main: 25f3520e653bc6e56e71b8f30d4d71578909c191.
Run 60 (37034064978) is complete: Windows access violation; Web 60 passed / 1 failed / 27 skipped and Linux 80 passed / 1 failed / 15 skipped, both player-set-shuffle-consecutive (Stream closed); macOS package tests passed.

Diagnostic branch runs unchanged code with the 2023-08-11 fixture and the latest release in media-kit/libmpv-win32-video-build, 2023-09-24. Latest here is still a 2023 build, not evidence of modern mpv coverage. Both run the full suite with dart test -j 1 --reporter expanded. Failure logs and resolved lockfile are retained. No main CI gates or tests are removed or relaxed.

Status: prepared; A/B outcome pending. Do not infer a fix before observing both results.
