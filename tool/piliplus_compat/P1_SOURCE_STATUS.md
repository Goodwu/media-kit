# P1 source integration — current checkpoint

Continue ONLY `compat/piliplus-zero-change-20261018`. Do not replay the P1 materializer.

Initial P1 sources: f2495b983d48fb3ac8cf5a00040d4967c16625ff.
First correction: 66df199c1165abc872af2161dadbd99f166b21d7.
Compile-r2 source integration: a165f55c81cd5f9ef6c6d5297c2803bb8fd6663b.
All seven changed existing source files in compile-r2 have locally verified matching remote Git blob hashes (see docs/plans/piliplus-p1-compile-r2.json).

Compile-r2 replaces the screenshot extension with a true inherited member selected for Flutter/pure Dart; adds the audio headers replacement contract and exact generated Gradle wrapper provenance. Local tool tests: 60 passed. The current commit starts T1 and the full video regression on the already integrated SDK code, not on the pre-publication request commit. A separate pure Dart test checks that no Flutter import is required.

The previous T1 run 39096187146 failed at ac964799; it is not evidence for compile-r2. No application/native/device success is claimed before the new runs complete. The Linux system-libmpv test is only an ABI/lifetime test, not fork-native freshness. Application source remains untouched. Ordinary-open routing, stable output ownership, full native closure, feature and HDR acceptance remain open.
