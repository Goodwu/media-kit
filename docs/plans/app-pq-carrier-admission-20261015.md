# App integration: explicit no-carrier admission / MK-ROUTING-20261011

> 2026-10-15 后续设计入口：[受管 YUV 分层契约](managed-yuv-layering-contract-20261015.md)，版本 `MK-ROUTING-20261011/LAYERING-20261015-r1`。普通 owner 后续实现与 L-A01—L-A16 验收按该契约；App 责任见其跨仓链接。本文件以下保留 C4 修复时的历史范围与证据，不将 owner 自动化记成已实现，不要求 App 补 token，不改变动态 HDR 延期或 accepted ledger。

Continue Goodwu/media-kit PR4 and Goodwu/PiliPlusX PR1 on the existing routing/MK-ROUTING-20261011 branches. Upstream2276715 and App b78bfbba/0f0d91e already integrate channel declarations and eight App regressions. Do not redo them.

During App integration, the explicit pqPresentation={rgbSurface:false,yuvWindow:false} case exposed a C4 fallback hole: _baseLayerConvert selected its RGB hardware importer even when that channel was explicitly unavailable. App6bcab371 adds three automatic HLG/P8.4/Vivid-HLG query/predict negatives and one independent explicit-SDR control before the repair; their actual CI evidence must be read separately (no preclaimed red/green).

This narrow library change refuses C4 with existing pqRgbPresentationUnavailable when both channels are false. The existing RGB rejection reason describes the unavailable fallback after the YUV alternative is excluded. It adds no enum or switch, does not reject older applicable adapters with missing channel fields (their migration remains RGB), and leaves YUV-only, RGB-only and both-channel selection unchanged. Twelve realizer/planner cases cover three HLG families times four channel combinations. App will update all eight references to the new current library HEAD and revalidate the combined source vector.

No changes to owner/ACK/lease, automatic production owner lifecycle, YUV arming side effects, native binaries, display validation, SDR policy, dynamic HDR10+/Vivid B1-B4 deferrals or acceptance ledger. Missing production YUV owner remains a separate explicit blocker; neither predicted feasibility nor this fix grants it. Source-only CI and actual native/device acceptance remain separate.
