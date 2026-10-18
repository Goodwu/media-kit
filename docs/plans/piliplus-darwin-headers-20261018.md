# Continue R3: Darwin header input closure

Continue only `compat/piliplus-zero-change-20261018`. The source snapshot `2d11e86f` was verified file-by-file against its Git manifest (1419 SDK files, 1640 original-app files). The app snapshot is `6a5171f98f6d493f3c07bc7fc5f0952d4bc5a5b4`. Upstream `0597c8318ccf50f0824249ceeab310632efb84ab` is merged normally as `d96ab35533d5094474862516e4c2ce49aa1d9012`; its two design documents do not authorize weakening the existing readiness gate or changing the app's capability-event path.

## Verified prior result

Original-app run 39130269367 on `61bc3a7c` ended with Android, Linux and Windows T1 success. The iOS and macOS evidence archives have `analysis=passed`, `applicationCompile=passed`, and successful compiler logs, but the SDK integrity guard rejected six previously unrecorded inputs: the common mpv header archive, its cache symlink and four copied public headers. Therefore the aggregate remained FAILED; compiler success was not a full T1 pass. SDK regression run 39130269426 succeeded. This supersedes the older checkpoint's five-failure description.

## This patch

`darwin_header_inputs.py` reads the existing common Darwin Makefile version/checksum and verifies the exact cached archive plus `mpv-<version>/libmpv/*.h` projection. Header contents, executable mode, output directory types and cache alias targets must match. Added or missing files, symlink substitutions, duplicate entries, traversal and ambiguous declarations fail. The result is merged into the existing per-path native-input records; no directory exemption is added. Darwin input CI now executes both existing recipes, rather than testing frameworks alone.

Local Python tool suite: 114 tests passed, including 21 new header tests. This is not Flutter compilation or native-source freshness. The next required result is the fresh five-platform matrix on this integrated code. The existing download declarations are unchanged; verifying their bytes does NOT satisfy P4's latest-source native-build requirement.

## Remaining after T1

P2 media/EDL and operation sequencing, P3 ordinary-open automatic routing and stable output ownership, P4 current native-source builds, and P5 feature/PiP/screenshot/device/HDR acceptance remain open. Do not replay the completed P1 migrations. Do not label successful build or a historical native archive as verified HDR playback.
