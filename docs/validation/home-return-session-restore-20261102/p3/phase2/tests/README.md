# P3 阶段二 · 修后测试执行证据（绑定源码身份）

执行：Lead 本机，2026-11-02 深夜，紧接 P3 (a) 守护式构建（Lab `46c22154…` / PiliPlus `dd07a4a0…`）之后；源码身份见 `source-identity.txt`（HEAD 761e29a8 + 工作树状态 + 11 个源文件 SHA256，与 `../build/build-identity.json` 记录的同一树）。

| 项 | 结果 | 文件 | 基线对照 |
|---|---|---|---|
| `dart analyze`（media_kit_video） | 9 issues（exit 3） | `dart-analyze.txt` | **与基线集合相同**：web_video_controller 2 error + 1 warning（未触碰文件）、simple_video 2 warning + 1 info、routed_video_playback.dart:161 info、两个既有测试文件 info。本任务触碰的文件零 issue。 |
| JVM host 测试 `tool/test_platform_bridge_activation.py` | **PASS: 20 activation scenarios, 560 checks**（真实 Plugin/Factory/View/Authorizer 链） | `jvm-bridge-activation.txt` | 首轮 14/456 → 条件项后 20/560 |
| `flutter test` 全量（media_kit_video） | **+1344 通过 / ~9 跳过 / -1 失败** | `flutter-test-full.txt` | 基线 +1272/~9/-1；唯一失败 `hdr_operation_diagnostics_test.dart: default Session backend forwards actual option owner; no backend override` 为既有已知失败（TASKS.md ROUTED-REPORT-EXPOSURE 条目记录，stash 干净树复现与本任务无关）。净增 72 个测试全部通过。 |

说明：`flutter test exit=1` 完全由上述唯一既有失败导致。
