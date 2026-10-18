# P1 source integration

The guarded materializer published real SDK edits as commit
`f2495b983d48fb3ac8cf5a00040d4967c16625ff` (parent `ecb586250dcf87ebe3bdc965a772a36a07b81575`).
Actions run `39094929543`, job `117579285761`, completed successfully.
This is source integration, not compilation or runtime acceptance. The materializer
must not be replayed once `docs/plans/piliplus-p1-materialized.json` is present.

This commit triggers original-app T1 builds on the integrated code and installs
libmpv for the Linux raw-event lifetime regression. That system library test is
an ABI/lifetime test, NOT a certification of the fork's native source freshness.
Application sources remain untouched; build outputs, SDK tests and native/device
acceptance are separate result categories.
