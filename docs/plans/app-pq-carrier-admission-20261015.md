# App integration: explicit no-carrier admission / MK-ROUTING-20261011

Continue Goodwu/media-kit PR4 and Goodwu/PiliPlusX PR1 on the existing routing/MK-ROUTING-20261011 branches. Upstream2276715 and App b78bfbba/0f0d91e already integrate channel declarations and eight App regressions. Do not redo them.

During App integration, the explicit pqPresentation={rgbSurface:false,yuvWindow:false} case exposed a C4 fallback hole: _baseLayerConvert selected its RGB hardware importer even when that channel was explicitly unavailable. App6bcab371 adds three automatic HLG/P8.4/Vivid-HLG query/predict negatives and one independent explicit-SDR control before the repair; their actual CI evidence must be read separately (no preclaimed red/green).

This narrow library change refuses C4 with existing pqRgbPresentationUnavailable when both channels are false. The existing RGB rejection reason describes the unavailable fallback after the YUV alternative is excluded. It adds no enum or switch, does not reject older applicable adapters with missing channel fields (their migration remains RGB), and leaves YUV-only, RGB-only and both-channel selection unchanged. Twelve realizer/planner cases cover three HLG families times four channel combinations. App will update all eight references to the new current library HEAD and revalidate the combined source vector.

No changes to owner/ACK/lease, automatic production owner lifecycle, YUV arming side effects, native binaries, display validation, SDR policy, dynamic HDR10+/Vivid B1-B4 deferrals or acceptance ledger. Missing production YUV owner remains a separate explicit blocker; neither predicted feasibility nor this fix grants it. Source-only CI and actual native/device acceptance remain separate.
