/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'hdr_source_descriptor.dart';

/// {@template hdr_strategy}
///
/// The routing strategies of the HDR output pipeline (requirement 3.2).
///
/// A strategy is an abstract way of presenting a source; [HdrRoute] (in
/// `hdr_route.dart`) is the concrete mpv property set one realizes into.
/// Strategies are chosen from a per-source-class preference list by the route
/// planner, gated by [HdrStrategyMaturity].
///
/// {@endtemplate}
enum HdrStrategy {
  /// DV decoder plus DV display, mapping done by the system and the Dolby
  /// engine. Reserved (R7) for every class except `dvP5` (verified since
  /// 2026-10-10: user-adjudicated default promotion after the genbump2 LG
  /// 30 s realtime pass; unlocked to `experimental` on 2026-10-06) and
  /// `dvP84` (verified since 2026-10-10 via the marble r30g single-device
  /// acceptance; `experimental` from the same 2026-10-06 unlock, N/A on LG
  /// which declares no P8.4 DV signaling); other classes still never select
  /// it.
  nativeDolbyVision,

  /// Decoder direct output to the surface (`mediacodec_embed`), emitting the
  /// base-layer transfer function and ignoring dynamic metadata.
  baseLayerDirect,

  /// `gpu-next` converts the base layer to a display-supported HDR transfer
  /// function (e.g. HLG to PQ), ignoring dynamic metadata.
  baseLayerConvert,

  /// `gpu-next`/libplacebo applies the dynamic metadata (DV RPU etc.) and
  /// rebuilds the signal, outputting HDR (PQ).
  metadataReshape,

  /// Texture output tone-mapped to SDR; whether dynamic metadata is applied
  /// depends on the profile rules.
  toneMapSdr,

  /// SDR base layer presented directly as SDR.
  sdrDirect,
}

/// {@template hdr_strategy_maturity}
///
/// How thoroughly a "source class × strategy" combination has been verified
/// on real hardware (requirement 3.5). The fact source is the status table in
/// section 6 of `docs/requirements/android-hdr-auto-output.md`, mirrored by
/// the constant table [HdrStrategyMaturityTable].
///
/// {@endtemplate}
enum HdrStrategyMaturity {
  /// Verified directly on real hardware.
  verified,

  /// The mechanism (decoder input, vo/hwdec, output transfer, dataspace
  /// path) is identical to a verified combination and evidence shows the
  /// differing parts have no effect. Selected by default like [verified].
  inherited,

  /// Never verified. Only selected when the routing policy explicitly sets
  /// `allowExperimental`.
  experimental,

  /// The current pipeline cannot implement the combination. Never selected
  /// from a preference list (the tone-map/SDR safety net still applies).
  unsupported,
}

/// {@template hdr_source_class}
///
/// The key of the preference and maturity tables: a coarse source family
/// derived from an [HdrSourceDescriptor]. The naming is provisional and gets
/// finalized in plan step S5.
///
/// {@endtemplate}
enum HdrSourceClass {
  dvP5,
  dvP81,
  dvP82,
  dvP84,
  dvP7,
  dvP10,
  hdr10,
  hlg,
  hdrVivid,
  hdr10Plus,
  sdr;

  /// Derives the preference/maturity key from a source description.
  ///
  /// Dolby Vision is identified from the dynamic metadata plus the profile
  /// and compatibility id; HDR10+ and HDR Vivid from their dynamic metadata
  /// format; everything else follows the base-layer transfer function
  /// (`hlg`, or `pq` with BT.2020 primaries, is HDR; the rest is SDR).
  ///
  /// DV metadata without a decodable profile is treated as profile 5: the
  /// only family whose routes never ignore the RPU, so a malformed hint can
  /// never select a route that mis-colors the picture (requirement R3.3).
  static HdrSourceClass of(HdrSourceDescriptor source) {
    if (source.dynamicMetadata == HdrDynamicMetadata.hdrVivid) {
      return HdrSourceClass.hdrVivid;
    }
    if (source.dynamicMetadata == HdrDynamicMetadata.hdr10Plus) {
      return HdrSourceClass.hdr10Plus;
    }
    if (source.dynamicMetadata == HdrDynamicMetadata.dolbyVision) {
      switch (source.dvProfile) {
        case 5:
          return HdrSourceClass.dvP5;
        case 7:
          return HdrSourceClass.dvP7;
        case 10:
          return HdrSourceClass.dvP10;
        case 8:
          switch (source.dvCompatibilityId) {
            case 1:
              return HdrSourceClass.dvP81;
            case 4:
              return HdrSourceClass.dvP84;
            case 2:
              return HdrSourceClass.dvP82;
          }
          // Unknown compatibility id: infer from the base layer, the same
          // rule the classifier uses to infer the id itself.
          return _dvP8FromBaseLayer(source.transfer);
      }
      // DV metadata without a profile: profile 5, conservatively (see the
      // doc comment above).
      return HdrSourceClass.dvP5;
    }
    if (source.transfer == 'hlg') return HdrSourceClass.hlg;
    if (source.transfer == 'pq' && source.primaries == 'bt.2020') {
      return HdrSourceClass.hdr10;
    }
    return HdrSourceClass.sdr;
  }

  /// Profile 8 with an unknown compatibility id: `hlg` identifies 8.4, `pq`
  /// maps to 8.1, an SDR (or unknown) gamma maps to 8.2.
  static HdrSourceClass _dvP8FromBaseLayer(String? transfer) {
    if (transfer == 'hlg') return HdrSourceClass.dvP84;
    if (transfer == 'pq') return HdrSourceClass.dvP81;
    return HdrSourceClass.dvP82;
  }
}

/// {@template hdr_strategy_maturity_table}
///
/// HdrStrategyMaturityTable
/// ------------------------
/// The constant maturity of every "source class × strategy" combination.
///
/// The fact source is the status table in section 6 of
/// `docs/requirements/android-hdr-auto-output.md`; cells the status table
/// does not list carry the conservative `experimental` default, with two
/// documented exceptions: `nativeDolbyVision` stays `unsupported` for the
/// classes R7 still reserves (every class except `dvP5`/`dvP84`), and
/// `sdr × sdrDirect` is `verified` (the always-on SDR Texture baseline
/// every non-HDR playback uses today).
///
/// The 2026-10-10 user-adjudicated A-group promotions (`dvP5`/`dvP84` ×
/// `nativeDolbyVision`, `hdr10` × `baseLayerConvert`/`metadataReshape`) are
/// documented rows in the status table — `hdr10 × baseLayerConvert` in
/// particular is no longer the unlisted "preferGpuOutput matrix pending"
/// conservative cell.
///
/// `hdr_maturity_table_test.dart` parses the requirement's table and locks
/// this constant table to it; upgrading a cell (plan S10 step 7) requires
/// updating both.
///
/// {@endtemplate}
class HdrStrategyMaturityTable {
  const HdrStrategyMaturityTable._();

  /// Maturity per source class and strategy. Every cell is explicit so a
  /// missing entry is a compile-time-visible table gap, not a silent lookup.
  static const Map<HdrSourceClass, Map<HdrStrategy, HdrStrategyMaturity>>
      cells = <HdrSourceClass, Map<HdrStrategy, HdrStrategyMaturity>>{
    HdrSourceClass.hdr10: <HdrStrategy, HdrStrategyMaturity>{
      HdrStrategy.nativeDolbyVision: HdrStrategyMaturity.unsupported,
      HdrStrategy.baseLayerDirect: HdrStrategyMaturity.verified, // 12703–12708
      // 2026-10-10 用户裁决提升（experimental → verified）：LG genbump2 轮
      // 哔哩哔哩 PQ 长片 30s，ACTUAL=baseLayerConvert 全路由
      // （platformView/surfacetexture/offscreen pq-full）、path=ext:lg-pq、
      // hal_hdr 单次稳定、decDrop=0，用户"3 个视频均人验通过"明确含
      // HDR10；历史 R33–r40 LG 多轮实测。原"preferGpuOutput 矩阵未单列"
      // 的保守档取消，正式立条。
      HdrStrategy.baseLayerConvert: HdrStrategyMaturity.verified,
      // 2026-10-10 用户裁决提升（experimental → verified，间接证据格）：
      // gpu-next/libplacebo 重建管线已在 dvP5 verified（同一管线）；用户
      // 裁决 A 组含本格（产品裁决背书）。无 HDR10 源 metadataReshape 直接
      // 入验记录。
      HdrStrategy.metadataReshape: HdrStrategyMaturity.verified,
      HdrStrategy.toneMapSdr: HdrStrategyMaturity.verified, // Texture→SDR 轮
      HdrStrategy.sdrDirect: HdrStrategyMaturity.experimental,
    },
    HdrSourceClass.hlg: <HdrStrategy, HdrStrategyMaturity>{
      HdrStrategy.nativeDolbyVision: HdrStrategyMaturity.unsupported,
      HdrStrategy.baseLayerDirect: HdrStrategyMaturity
          .verified, // a1-hlg-gate-85 + 2026-10-02 人工观察（真实 HLG 内容直出）
      HdrStrategy.baseLayerConvert: HdrStrategyMaturity.experimental,
      HdrStrategy.metadataReshape: HdrStrategyMaturity.experimental,
      HdrStrategy.toneMapSdr: HdrStrategyMaturity.experimental,
      HdrStrategy.sdrDirect: HdrStrategyMaturity.experimental,
    },
    HdrSourceClass.dvP5: <HdrStrategy, HdrStrategyMaturity>{
      // 2026-10-06 LG DV 设备实机解锁（原 R7 保留）：LG 面板声明 DV
      // （displayHdrTypes 含 1）、qcom DV 硬解器在位、native DV bridge v1
      // 已加载（HDR_CAP_QUERY nativeDvBridgeApi=1），且 R22 N4 诊断模式已
      // 证明该路由在 LG 上可达。experimental 起步。
      // 2026-10-10 用户裁决直通默认化（experimental → verified）：genbump2
      // 代际 LG 原文件直通 ACTUAL=nativeDolbyVision 30s 实时（dvProfile 5
      // verified、decDrop=0、vfps=24.0 源率），用户人工观察通过；历史证据
      // r26b（2026-10-07 LG，"P5 nativeDV 画面没问题"）与 r30b（marble，
      // "颜色正常/画面流畅"）。`allowExperimental` 门槛与其它格零改动。
      HdrStrategy.nativeDolbyVision: HdrStrategyMaturity.verified,
      HdrStrategy.baseLayerDirect: HdrStrategyMaturity
          .experimental, // 忽略 RPU 会偏色；realize 直接判不可行
      HdrStrategy.baseLayerConvert: HdrStrategyMaturity
          .experimental, // 同上
      HdrStrategy.metadataReshape: HdrStrategyMaturity
          .verified, // 12703–12708，全片 EOS
      HdrStrategy.toneMapSdr: HdrStrategyMaturity
          .verified, // P0 P5→Texture SDR 默认开启
      HdrStrategy.sdrDirect: HdrStrategyMaturity.experimental,
    },
    HdrSourceClass.dvP81: <HdrStrategy, HdrStrategyMaturity>{
      HdrStrategy.nativeDolbyVision: HdrStrategyMaturity.unsupported, // R7
      HdrStrategy.baseLayerDirect: HdrStrategyMaturity
          .inherited, // 机制同 HDR10 直出；缺样片确认
      HdrStrategy.baseLayerConvert: HdrStrategyMaturity.experimental,
      HdrStrategy.metadataReshape: HdrStrategyMaturity.experimental,
      HdrStrategy.toneMapSdr: HdrStrategyMaturity.experimental,
      HdrStrategy.sdrDirect: HdrStrategyMaturity.experimental,
    },
    HdrSourceClass.dvP82: <HdrStrategy, HdrStrategyMaturity>{
      HdrStrategy.nativeDolbyVision: HdrStrategyMaturity.unsupported, // R7
      HdrStrategy.baseLayerDirect: HdrStrategyMaturity
          .experimental, // 全部 experimental（缺样片）
      HdrStrategy.baseLayerConvert: HdrStrategyMaturity.experimental,
      HdrStrategy.metadataReshape: HdrStrategyMaturity.experimental,
      HdrStrategy.toneMapSdr: HdrStrategyMaturity.experimental,
      HdrStrategy.sdrDirect: HdrStrategyMaturity.experimental,
    },
    HdrSourceClass.dvP84: <HdrStrategy, HdrStrategyMaturity>{
      // 2026-10-06 与 dvP5 同批解锁（用户导演的 LG DV 设备直通验证）。
      // 2026-10-10 用户裁决提升（experimental → verified）：marble r30g
      // （2026-10-07）实机 ACTUAL=nativeDolbyVision，用户验收"颜色正常/
      // 亮度好/流畅性好"；LG 无 P8.4 DV 信令该路线不可达（N/A，非失败）
      // —— marble 单设备人工验收。
      HdrStrategy.nativeDolbyVision: HdrStrategyMaturity.verified,
      HdrStrategy.baseLayerDirect: HdrStrategyMaturity.verified, // 12703–12708
      HdrStrategy.baseLayerConvert: HdrStrategyMaturity
          .verified, // A3-2 模拟无 HLG 落 convert + 2026-10-02 人工观察
      HdrStrategy.metadataReshape: HdrStrategyMaturity
          .experimental, // 重建管线只在 P5 验证过
      HdrStrategy.toneMapSdr: HdrStrategyMaturity
          .verified, // 12703–12708 SDR 对照
      HdrStrategy.sdrDirect: HdrStrategyMaturity.experimental,
    },
    HdrSourceClass.dvP7: <HdrStrategy, HdrStrategyMaturity>{
      HdrStrategy.nativeDolbyVision: HdrStrategyMaturity.unsupported, // R7
      HdrStrategy.baseLayerDirect: HdrStrategyMaturity
          .experimental, // 缺样片；增强层识别方式待定
      HdrStrategy.baseLayerConvert: HdrStrategyMaturity.experimental,
      HdrStrategy.metadataReshape: HdrStrategyMaturity
          .experimental, // 仅 MEL；FEL 由 realize 拒绝
      HdrStrategy.toneMapSdr: HdrStrategyMaturity.experimental,
      HdrStrategy.sdrDirect: HdrStrategyMaturity.experimental,
    },
    HdrSourceClass.dvP10: <HdrStrategy, HdrStrategyMaturity>{
      // Phase 1 不涉及 AV1：全部 unsupported（nativeDolbyVision 无 realizer
      // 分支；R7 的 dvP5 解锁不适用于本类）。
      HdrStrategy.nativeDolbyVision: HdrStrategyMaturity.unsupported,
      HdrStrategy.baseLayerDirect: HdrStrategyMaturity.unsupported,
      HdrStrategy.baseLayerConvert: HdrStrategyMaturity.unsupported,
      HdrStrategy.metadataReshape: HdrStrategyMaturity.unsupported,
      HdrStrategy.toneMapSdr: HdrStrategyMaturity.unsupported,
      HdrStrategy.sdrDirect: HdrStrategyMaturity.unsupported,
    },
    HdrSourceClass.hdrVivid: <HdrStrategy, HdrStrategyMaturity>{
      HdrStrategy.nativeDolbyVision: HdrStrategyMaturity.unsupported,
      HdrStrategy.baseLayerDirect: HdrStrategyMaturity
          .experimental, // 本地有样片，待单列验证
      HdrStrategy.baseLayerConvert: HdrStrategyMaturity.experimental,
      HdrStrategy.metadataReshape: HdrStrategyMaturity
          .unsupported, // 未实现（realize 拒绝）
      HdrStrategy.toneMapSdr: HdrStrategyMaturity.experimental,
      HdrStrategy.sdrDirect: HdrStrategyMaturity.experimental,
    },
    HdrSourceClass.hdr10Plus: <HdrStrategy, HdrStrategyMaturity>{
      // 状态表未列出 HDR10+（mpv 尚不可识别其元数据）：全部保守 experimental。
      HdrStrategy.nativeDolbyVision: HdrStrategyMaturity.unsupported,
      HdrStrategy.baseLayerDirect: HdrStrategyMaturity.experimental,
      HdrStrategy.baseLayerConvert: HdrStrategyMaturity.experimental,
      HdrStrategy.metadataReshape: HdrStrategyMaturity.experimental,
      HdrStrategy.toneMapSdr: HdrStrategyMaturity.experimental,
      HdrStrategy.sdrDirect: HdrStrategyMaturity.experimental,
    },
    HdrSourceClass.sdr: <HdrStrategy, HdrStrategyMaturity>{
      HdrStrategy.nativeDolbyVision: HdrStrategyMaturity.unsupported,
      HdrStrategy.baseLayerDirect: HdrStrategyMaturity.experimental,
      HdrStrategy.baseLayerConvert: HdrStrategyMaturity.experimental,
      HdrStrategy.metadataReshape: HdrStrategyMaturity.experimental,
      HdrStrategy.toneMapSdr: HdrStrategyMaturity.experimental,
      HdrStrategy.sdrDirect: HdrStrategyMaturity
          .verified, // SDR Texture 直出是现有默认播放路径（SDR 回归样片已验证）
    },
  };

  /// The maturity of one combination. Every cell is populated; a missing
  /// entry is a table bug and throws.
  static HdrStrategyMaturity of(HdrSourceClass cls, HdrStrategy strategy) {
    return cells[cls]![strategy]!;
  }
}
