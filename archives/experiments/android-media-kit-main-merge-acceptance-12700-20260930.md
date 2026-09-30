# media-kit 主仓合并上游 main 后的 P5 实机验收（2026-09-30）

## 背景

合并提交 `a886f556`（`fix/darwin-video-output-rebuild-barrier` = 96571a92 + 上游 main d310049）后，按登记任务门槛复跑 P5 五项实机验收。三包均注入发布基线 JAR `~/src/media-kit-build/jars/media-kit-p5-colorfix-398d0c3-arm64.jar`（当时位于 /tmp）（SHA-256 `dad30ae23cd75e85…42c2a9f7`），JDK17 + `ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar` 正式流程，`flutter build apk --release --target-platform android-arm64`。APK 内 native 库集与已验收 12680 逐项一致（libmpv 经 AGP strip，20.5MB），合并差异仅在 Dart/Java 层。设备 `3EP7N18C28016072`（LYA-AL00），每轮结束恢复原 12492、自动亮度、熄屏。

## 轮次与证据

- **12700 Glass SDR 全片**（define 集=12632 去起播偏移）：`P5_SECTION_INIT direct=1` + `P5_DOVI_RESCALE enabled k=1.002941`；片尾 `P5_TAIL_FALLBACK requested=174.858 previous=174.824`（33ms 相邻帧回退命中）且零 `Failed rendering frame`；EOS `AUTO_COMPLETED completed=true`（13:20:44，~178s）；退出闭合 `P5_IMAGE_FINAL 8376/8376 retired=0`；截图 t30/90/150/230 像素统计全部正常画面（无紫/黑/白屏）。
- **12701 Mystery PQ 全片**（=12633 集 + `MEDIA_KIT_ANDROID_GPU_PLATFORM_HDR=true`）：`gpuPlatformHdr=true`、direct=1 + RESCALE k=1.002941；片尾回退命中 PTS 98.748、零渲染错误；EOS `completed=true`（13:24:39，~99s）；退出闭合 4483/4483；截图 t30/90/140 正常画面。
- **12702 播放中直接 Engine 销毁**（=12632 集去 PERF_PROBE + `MEDIA_KIT_ANDROID_ENGINE_DESTROY_AT_SECONDS=25`）：播放 22.7s 处销毁请求即返回；进程 pid 14439 在销毁后 +0s/+10s/+25s 全部存活；`P5_IMAGE_FINAL 900/900` 由销毁路径闭合；`MpvOwnerBroker register` 正常；崩溃计数 0、mpv 线程残留 0。

## 五项门槛对照

1. **颜色数值**：native 层与全片验收的 12680-12682 逐字节同源（同 JAR、同库集），两轮 `direct=1`+`RESCALE k=1.002941` 与已验收包日志一致，截图像素统计正常——产品级证据达成。严格三方数值读回未复跑（其装置针对固定 JAR，native 未变）。
2. **片尾回退**：两片源均实际命中回退且画面正常、零渲染错误（强于 12632 的 3/3 复现证据）。
3. **EOS**：两全片轮 `completed=true`，时长与片长一致。
4. **直接 Engine 销毁**：零崩溃、进程存活、资源闭环、broker 路径工作。
5. **PQ 首帧**：PQ 输出槽代码为 HEAD 原样保留（P1 时代 12602 已测 1.1s）；本轮 PQ 通路激活、全片 EOS、t30 实际画面。精确毫秒级首帧探针不在本轮 define 集。

## 结论

合并后构建在五项门槛上均通过产品级实机验收，main 可快进至合并结果成为唯一维护线。遗留：上游亮度/音量控件特性未吸收（评估记录在案）、Linux 侧需 Linux 环境回归、严格数值读回可按需补跑。

- APK 留存：`~/src/media-kit-build/apks/merge-accept-1270{0,1,2}-*.apk`；轮次日志/截图：`~/src/media-kit-build/evidence/merge-accept-12700-02/`（/tmp 原件已删除，持久副本为权威）；轮脚本 `tool/merge-accept-round.sh`、`tool/merge-accept-destroy-round.sh`；像素判定 `tool/pixel-judge.py`（2026-09-30 自 /tmp 收编入仓）。
