# P1 source integration — static API/build correction checkpoint

Continue ONLY compat/piliplus-zero-change-20261018; never replay materializers.
Initial P1: f2495b983d48fb3ac8cf5a00040d4967c16625ff.
Compile-r2: a165f55c81cd5f9ef6c6d5297c2803bb8fd6663b.
Static Flutter/pure-Dart entry integration: 288b9f24803025c462f081a5be4c3c0cb9065ea4.
Exact macOS generator integration: b5e7602da9b9c87be7496c8d2ec96de5f62b4711.
The 11 existing locally available static-facade source files matched the published blobs. No application sources were patched. Local final tool suite: 77 passed.

Prior T1 run39126075750 at f0de192 compiled Android/iOS/Linux; Windows compiler also exited 0 but the console printer failed, and macOS failed due to flattened framework links. Analysis failed on the conditional screenshot type on every platform. iOS/macOS automatic project migrations were rejected, not silently admitted. These are historical intermediate results, NOT acceptance of current code.

This commit starts all five original-app builds on the published fixes and adds analyzer verification for restricted-import screenshot/header APIs before the complete video test suite. Non-Flutter callers explicitly use media_kit_dart.dart; the Flutter entry remains unchanged for original PiliPlus. The SDK system-libmpv lifetime test does not certify source-fresh fork binaries. Native closure, runtime/feature/automatic routing and HDR remain separate open gates.
