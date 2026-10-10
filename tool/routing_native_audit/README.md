# Native decoder selection regression (MK-ROUTING-20261011)

This is a host-C regression harness with JNI fixtures, not an Android test or a full FFmpeg build. It compiles the selection function and native-DV lookup branch extracted from the FFmpeg sources supplied for each run. No historical source fragment, pinned checkout, library, or binary is bundled here.

## Run against the latest working sources

After reconciling the task's canonical branches and updating the actual FFmpeg checkout (preserving intentional dirty changes):

```sh
python3 -m unittest discover -s tool/routing_native_audit -p test_extract.py -v
python3 tool/routing_native_audit/run.py \
  --ffmpeg-root /path/to/current/FFmpeg \
  --output /path/to/new/audit-output \
  --sanitize
```

Python 3.9+ and a C11 compiler on a POSIX host are required. `--cc` or `CC` chooses the compiler. Sanitizers are optional when the host toolchain does not support them; the receipt records the actual command. The caller is responsible for checking that the checkout contains the latest applicable changes. Recorded SHA-256 values are provenance, not revision pins.

The harness includes generated regions through angle-bracket includes and an explicit output-directory include path, so an old `.inc` beside the harness cannot override the freshly extracted code. Source anchors must occur exactly once; changed source layout fails extraction rather than guessing. Input files are rechecked after execution. This is a small targeted extractor, not a general C parser.

## Assertions and exit status

Five controls cover P5 profile matching, P8 profile matching, encoder exclusion, software exclusion and MIME exclusion. The regression supplies a P5-only DV decoder before a P8-only DV decoder and applies the **current native caller's** profile selection to the current list selector. A P8 request must select the P8 entry.

Exit 0 means these limited checks pass. Exit 1 means a regression failed. Exit 2 means extraction, compilation, timeout or input stability failed. `receipt.json`, `compile.log`, `regression.log` and extracted regions remain in the output directory. A reproduced known defect is intentionally a failure, not an expected-failure skip or green product acceptance.

The 2026-10-11 first audit reproduced a failure because the native P8 caller supplied profile=-1 (MIME-only). See `docs/plans/media-kit-routing-native-audit-20261011.md`. That audit used current source **region captures** from the read-only workspace connector, explicitly recorded with `--input-scope captured-regions`; it did not compile the entire native repository. Future checkout runs must not inherit that stronger claim.

The fixtures do not cover JNI exceptions, real codec configure/start, Android color output, layer presentation, dimensions/levels, every vendor codec naming rule or complete resource lifecycle. These remain separate validation requirements. Do not call this alone native device or latest-source APK acceptance.
