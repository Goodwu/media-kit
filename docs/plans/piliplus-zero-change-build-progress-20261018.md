# Original PiliPlus implementation / build checkpoint

2026-10-18. Continue ONLY `compat/piliplus-zero-change-20261018` from `1ad43167831bdeb0494134dd781d82b71b41548c`; routing remains `0a212785a87df88a0a583cd5f1f526630d5c4e81`. Read the R3 main plan and its existing handoff first.

## This slice

Adds P0b isolated staging and five-platform original-app T1 compilation. The app revision is resolved once from current main per workflow and shared by every platform. All media-kit packages use this run's source checkout; the app's tracked source/pubspec is never patched. The upstream PowerShell recipe is reviewed rather than blindly executed: its Flutter/material/cupertino patches are applied to private copies and hashes are logged. Two upstream iOS patches that modify PiliPlus itself are intentionally not applied, and this difference is explicitly recorded, not called feature parity.

Override-only missing packages remain recorded in the declaration plan. Only a successful real pub resolution plus package-config inspection proving absence can discharge them. Missing required packages stop immediately. Original files are verified against Git blob/type/mode, even with assume-unchanged, and new source files cannot hide behind gitignore or an assets/build name. Exact generated lock/plugin paths are recorded separately.

Local: 14 new Python guard tests passed. Remote T1 compilation not yet observed at publication. No claim of application compile, native-source freshness, runtime compatibility, automatic routing or device/HDR success. Existing P0a executable is unchanged (blob `2ba0a9d9b25cd48171915c692fe92e13fa15f3fb`).

The next work is to read actual pub/analyzer/build results, fix concrete SDK compatibility errors and run again. Do not suppress errors or replace the original app with a fixture to make T1 green. P1-P5 remain open. Full dependency asset and native artifact closure verification remains separate from the original/SDK source guards in this slice.
