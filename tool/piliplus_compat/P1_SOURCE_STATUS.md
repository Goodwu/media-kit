# P1 source integration — R4 acceptance run

Continue ONLY compat/piliplus-zero-change-20261018; never replay materializers.
Initial P1: f2495b983d48fb3ac8cf5a00040d4967c16625ff.
Compile-r2: a165f55c81cd5f9ef6c6d5297c2803bb8fd6663b.
Static Flutter/pure-Dart entry: 288b9f24803025c462f081a5be4c3c0cb9065ea4.
Exact macOS generator: b5e7602da9b9c87be7496c8d2ec96de5f62b4711.
Darwin input/scheme verifier integrated: 6c55323d8b7a6bca31c1f4547d533ad6176051bc; builder blob 80d251ad91319056c091bd4630e3f82c5a67ddcb matches the locally tested code. Local tool suite: 93 passed.

At f7dceaa93edfa8d5a4e5cf2fde1661cbecf6c795, T1 run39128691646 had all five analyzers and compilers exit0. Android/Linux/Windows passed full guards and uploaded debug outputs. iOS/macOS failed the new-input guard on downloaded Frameworks; exact original/generated scheme/workspace changes were also reviewed before admitting them. This commit runs the complete five-platform workflow on the integrated R4 verifier, not on an unmaterialized request.

SDK run39128691721: pure Dart byte contract and restricted-import Flutter analyzer passed; complete video suite 979passed,3macOS-onlyskips. Separate actual macOS run39129486851 executed all25 viewport/legacy-view/player/restricted-import cases successfully, including those three previously skipped tests. Runtime/library sources are unchanged by R4; no native freshness or device playback is inferred.

Original PiliPlus Dart/native logic and source pubspec remain untouched. Generated lockfiles and precisely reviewed platform build configurations are separately recorded, never called byte-identical. Non-Flutter clients use media_kit_dart.dart; original PiliPlus keeps its Flutter import. P2-P5 media sequencing, automatic routing, stable output lifecycle, latest-source native closure and feature/PiP/HDR acceptance remain open.
