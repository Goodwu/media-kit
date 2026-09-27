# P5 Glass SurfaceProducer 动态尺寸同步，12504

## Current State

2026-09-27，在隔离诊断包中，仅修改 `AndroidVideoController._applyVideoSizeLocked`：SurfaceProducer 同 wid 改尺寸后也写入 mpv 的 `android-surface-size`。其余固定源、1×1 预建、运行属性和测试页与 12502 相同。12504 APK SHA-256 `bf8183eb49d769a9ee8b3976cd7e2809302fe6fa670b24056d3d27c66a8ddb29`。LYA-AL00/API29，Glass P5 源 SHA-256 `afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c`，自动亮度、竖屏测试页。

12502：预建 1×1 后原生 Surface 扩到 3840×2160，但 mpv 后续读回 `android-surface-size=1x1`，9 秒内无有效固定区域内容，约 86/97 个后续样本近乎均匀。12504：相同 1×1 预建，原生回调报告同 wid 改到 3840×2160；第二轮 mpv 读回 `android-surface-size=3840x2160`。两次从点击回调到固定区域首次非黑为 3.670、3.464 秒；第一轮截图呈现可辨认的吹玻璃画面。支持尺寸属性未同步是 12502 异常的原因；未做同 PTS 数值画质、RPU、真全屏和物理显示验收，不能据此宣称产品首帧达标。

首轮 `media_opened=0.759` 秒，之后 0.038 秒创建 OMX HEVC 组件；第二轮 `media_opened=0.741` 秒，之后约 0.031 秒创建组件。剩余时间包含片源约 2.05 秒黑场与 PixelCopy 间隔。诊断包固定源预验证和固定初始尺寸仅用于排查，产品通用预建策略仍未实现。

主工作树产品修复把 Texture 原生尺寸 ACK 用于实际尺寸，并对非零 wid 的 SurfaceProducer 同步 `android-surface-size`；这是对上述诊断补丁的扩展，尚需独立审查及不同输出/重建回归后才能认定交付。原始证据：`artifacts/android-firstframe-surface-size-12504/tiny1.log.gz` SHA-256 `1a8cf9f131fbd3bf5e8b01722f7fa1810f2d969c0209b3ca30fb2a77b8185426`，`tiny2.log.gz` SHA-256 `98593193686b110a005a3417ee115c80707ec6aee449d2df17eeb5037b88dcdb`，`tiny1.png` SHA-256 `1f467f3d6bdd3ec99bdf86a82321a766c5f14c1ba0bc3160e64840faeb0b242e`。

实验后已强停应用、恢复六个诊断属性为 0、安装原 12492 APK；自动亮度模式 1，设备睡眠且显示 OFF。
