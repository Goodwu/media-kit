# 双设备最新代码回归轮（2026-10-10）

## Current State（2026-10-10 晚收口）

- **回归结论：通过**。当前 main（a072e964）+ 最新 native 源码（mpv `c11426b67a` 含当日 5 未推送提交、FFmpeg `d4bb79394b` + 既定 dirty configure）重建 JAR（槽 5f8fc04c，链接字节级可复现），LYA-AL00 与 marble（23049RAD8C）六轮全绿：路由全 verified、render_failures=0、fatal=0、EOS/dispose 闭合（除已知问题②）。完整报告：experiments 库 `regression-two-device-latest-20261010.md`（4c65217）；证据本机 `~/src/media-kit-build/evidence/regression-two-device-20261010/`。
- **核心兑现**：dvP5×nativeDV（d2fdbc65）与 dvP84×nativeDV（a0d8c4a3）在 marble 以默认策略（无 GATE_OPEN）首次真机直达 nativeDolbyVision（P5 全片丢帧 1 次，直通流畅再证）；用户屏幕目视通过。
- **用户裁决入账——测试版构建默认行为**：测试版必须从最新源码构建；钉定发布 JAR 只属发布链。落地：`tool/build-android-test.sh`（ninja 同步 → build-mks-r1 `MKS_SKIP_APK=1` JAR-only → gradle 内建 `ORG_GRADLE_PROJECT_mediaKitLocalArm64Jar` 正式本地 JAR 通道）为默认测试构建入口；`tool/README.md`、`AGENTS.local.md` 同步；发布链（钉定下载+SHA 核验）不动。
- **构建链新事实**：12:01 genbump2 JAR 不含下午 5 个 mpv 提交最终内容（vd_lavc/player_command 未编译，"18:02 与工作树一致"验证未完成链接）——任何以 12:01 JAR 为基线的验证范围以此为界。
- **两项待办（用户指示入待办，非回归失败）**：①LYA P5 reshape→PQ 稳态 VO 丢帧偏多且轮间差异大（发布 JAR 8/60s vs 最新 30/60s、复测轮 40–60s 突发 329，container-fps=59.94；decoder 恒 0——4K59.94 重建在 Kirin 980 吞吐边缘，是否新提交加剧未定论）；②marble post-EOS BACK 不触发 dispose（app 侧零日志，三次 P5 全片轮复现含最新构建；同机 pre-EOS 正常、LYA post-EOS 正常——签名 HyperOS API35 × post-EOS）。

## 过程要点

1. 预检：两机 fixture 字节核验一致（p84 两机同名异文件同哈希，marble 侧 cp 出规范名）；marble 补推 mystery-box（346MB）+ hdr10-full（542MB），推送后设备侧 sha256 复验一致；marble 现装 r30g（3968e6fc）先拉取备份作恢复源。
2. 发布 JAR 对照轮（后被用户裁决降为对照）：LYA 三轮与 bc2306 基线全对齐（P5 reshape→PQ/EOS/dispose/SF BT2020_PQ）；marble P5 走 reshape（钉定 v2026.012 JAR 无 nativeDV 桥，解包实锤 native_dv=0）——用户据此指出"路由应该是 nativeDV"并裁决测试版从最新构建。
3. 最新重建：ninja dry-run 发现 7 个待编译目标（推翻"已同步"假设）→ 实际重编译重链；build-mks-r1 管线全预检过（基础 JAR 对 r22 钉定一致、gate 符号在档）；21:05 复跑槽位逐字节一致证明链接可复现。
4. 设备轮：regression-round.sh（matrix-round.sh 修正版：当前日志格式 grep、per-device tap、原亮度记录还原、HyperOS 安装自动化、API 35 解锁字段兼容、BACK 后 15s 观察窗）。首轮 marble 因 `isStatusBarKeyguard` 字段在 API 35 缺席误判 UNLOCK_FAILED 早退（trap 正常还原），修正后全绿。
5. 恢复：marble r30g 字节核验还原 + 自动亮度 + 熄屏；LYA 各轮卸载恢复原状。
