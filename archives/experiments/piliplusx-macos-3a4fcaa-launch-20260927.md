# PiliPlusX macOS 产品调用链尝试（2026-09-27）

- `PiliPlusX/pubspec_overrides.yaml` 的 media-kit 依赖是 `../media-kit` 本地路径，故 `flutter pub get` 与 `flutter build macos --debug --no-pub` 实际读取当前工作树；构建成功。
- 将构建包复制为独立 app，再替换成已验证的 final16 Goodwu mpv 0.41 框架和动态库；mpv 二进制 SHA-256 为 `44112e778650a87160028f4a9efb60e9c02cb506db5da1924605bee492205f24`，重签名和 `codesign --verify --deep --strict` 通过。
- 两次启动均有存活进程，但 macOS UI 查询没有窗口。第二次标准输出显示 Flutter Metal 后端启动、Dart VM service、`media_kit` 原生引用分配、应用初始化和网络请求/响应；因此不能把它判为播放器崩溃，也不能据此验证播放退出。
- 本次没有播放视频，没有取得 Surface、render context 释放或无 abort 的产品链路证据。PiliPlusX 的临时版本引用已恢复；独立 app 和原始启动日志已清理。下一步应定位测试包为何没有窗口，再进行目标场景。
