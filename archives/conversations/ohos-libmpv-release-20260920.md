# OHOS libmpv release 20260920

## Current State

- status: done
- scope: 将 `media_kit_libs_ohos` 的 ARM64 libmpv 二进制下载来源从 ErBWs `20260811` 切换为 Goodwu `20260920`。
- source of truth: https://github.com/Goodwu/libmpv-ohos-build/releases/tag/20260920
- verified release asset: `libmpv_aarch64.zip`，GitHub release digest 与本地下载 SHA-256 均为 `29b8bd4de54bb61c6fbb549022af5d9082d7b057a5901a1d388597ff15114191`；`unzip -t` 通过，包含 `libmpv.so`。
- changed file: `libs/ohos/media_kit_libs_ohos/ohos/src/main/cpp/CMakeLists.txt`。
- acceptance: CMake 配置文本断言通过，`git diff --check` 通过。

## History

- 2026-09-20: 用户指定 Goodwu/libmpv-ohos-build 的 `20260920` release 作为 OHOS libmpv 二进制发布来源。
