# HDR lab 测试效率改造：一次构建 + 运行时场景 + 批量测试

## Current State

2026-10-11：总体方案产出、归档并**完成用户裁决，可进入 WP0/WP1 实施**（实施尚未开始）。

1. **方案**：`docs/plans/hdr-lab-runtime-scenario-batch-20261011.md`（v1+裁决修订）。核心：固定被测二进制 + 启动时冻结配置（Intent base64url 信封 + 显式文件引用，禁止自动发现与运行中热改）+ 不可变批清单 + 顺序执行器（默认每 case 新 Player/Session）+ host 独立看门狗 + 结果 app 私有目录原子落盘后 adb 镜像。
2. **用户裁决（2026-10-11）**：① 接受 build identity 划界——生产库消费的 5 个同名 define（CONVERT_SURFACE_TRANSFER/CONVERT_ROUTE_LOCK/SURFACETEXTURE_POC/SURFACE_FORMAT/REVIEW_TRACE）为 build-bound，对应 PoC 场景保留独立构建；② 故障批允许 host watchdog 自动重启恢复（attemptId 显式记录、次数封顶）；③ 结果写 app 私有目录 + adb 镜像；④ **A3 扩展注销留在构建期，不纳入 WP1**（对 Specialist 建议的否决，WP1 Kotlin 范围相应收缩为 ScenarioChannel 注册/LoadOnce）。建议项 ⑤⑥⑦（WP2 首版限定普通矩阵、非 Android 暂保持 define 工作流、温度预算按设备基线）按裁决精神采纳为默认。
3. **对既往口径的两处纠偏（Lead 已独立抽查证实）**：① lab 编译期开关实为 **150 处调用 / 139 key / 6 文件**（主页面 126）；② 生产库 `media_kit_video` 直接消费上述 5 个同名编译期开关。
4. **分期**：WP0 文档与 139 key 清单冻结（0.5–1 人日）→ WP1 运行时配置一次构建多场景冷启动（3–5+1–2 人日，含 `tool/build-android-test.sh` runtime-lab 模式改造）→ WP2 batch 一次启动跑整批（5–8+2–3 人日，host watchdog/run_batch.py/check_results.py）。两期共同硬验收：生产库与 PiliPlusX 零 diff。

历史区（按时间）

- 2026-10-11 需求确立：用户报"一次测试构建 3 个 APK 太慢"，根因为 `fromEnvironment` 编译期场景开关（主页面 126 处）与 `MEDIA_KIT_ANDROID_LOCAL_SOURCE` 源片路径常量（`sources_native.dart:11`）——一个片段×一个场景一个包；并确认 GATE_OPEN/experimental 作为 lab 验证仪器保留、永不引入生产（此前对话已定）。
- 2026-10-11 首次派发 team-specialist 因供应商 oauth 失效失败两次；用户修复认证后重新派发成功。
- 2026-10-11 Specialist 交付方案（约 198 万 token 只读核查，HEAD `d7619227`，未写文件未构建）；Lead 抽查计数（150/139/6 文件）与生产耦合（5 个生产消费 define）均证实，方案 V0 复查通过并入档。
- 2026-10-11 用户四项裁决入档（见 Current State 第 2 条），方案文档按裁决修订（A3 相关 WP1 条目收缩），TASKS.md 任务条目同步。
