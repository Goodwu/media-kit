/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:flutter/foundation.dart' show debugPrint;

import 'hdr_route.dart';

/// The YUV window route's accepted presentation contract (architecture
/// decision 3, plan A4; P8.4 A5 V2 review fix): the offscreen and the window
/// are different contract surfaces, and on the YUV route they must hold the
/// accepted quad at once.
///
/// The YUV shape is judged by CARRIER, not by the requested window label
/// (P8.4 A5 V2 root cause): `hwdec == 'surfacetexture'` is the one and only
/// carrier of the LG yuv-diag presentation path, and on it the vendor
/// FORCES the window label to 0x11C60000 in yuvDiag mode regardless of
/// whether the route requested `pq` (full) or `pq-itu` (limited). The
/// requested surfaceTransfer therefore cannot tell what is actually
/// presented — the euv17 pairing requested plain `pq`, ran the
/// surfacetexture carrier, and still presented the forced NV12/limited
/// window while bypassing this contract when the contract keyed on the
/// request.
///
/// The quad (the euv13 human-accepted / euv17 re-tested configuration):
///
/// 1. offscreen = `pq-full` — full-range normalized PQ in the RGBA16F FBO
///    ([HdrRoute.offscreenTransfer], realized mpv-side by the owned
///    `video-output-levels=full` write the backend must issue);
/// 2. window content = NV12 limited (16-235, the single 16+219p packing of
///    the mpv fork's final pass — realized outside Dart; the Dart-side
///    counterpart is the YUV window route shape itself, see
///    [isYuvWindowRoute]);
/// 3. window label = BT2020 PQ / LIMITED 0x11C60000 — VENDOR-FORCED in
///    yuvDiag mode (the vendor gate's dual-layer range contract: offscreen
///    full, window limited), whatever PQ variant the route requested;
/// 4. metadata identity triplet = (9, 1, 16) as injected per buffer by the
///    mpv fork's mks_p1 path.
///
/// The triplet is DECLARED here verbatim from the mpv-side constant and only
/// compared against — the Dart side never invents or remaps metadata values
/// (the euv14-rng2 lesson: metadata identity must strictly match the buffer
/// content contract, and a drifted label flips the composer's per-frame
/// verdict). [validate] is the lab page's pairing hard check promoted into
/// the main library path: any route declaring the YUV window shape that does
/// not carry the whole quad is refused before a buffer can be presented.
class HdrYuvPresentationContract {
  const HdrYuvPresentationContract._();

  /// Offscreen contract value carried by [HdrRoute.offscreenTransfer].
  static const String offscreenTransfer = 'pq-full';

  /// Window request value carried by [HdrRoute.surfaceTransfer]: a PQ
  /// variant over the NV12 limited window. Both accepted requests —
  /// `pq-itu` (BT2020 PQ / LIMITED, the explicit limited request) and `pq`
  /// (BT2020 PQ, the product default) — are in scope; the vendor forces the
  /// window label below for either in yuvDiag mode.
  static const List<String> windowRequests = <String>['pq', 'pq-itu'];

  /// The limited-label request value (`pq-itu`), kept as its own constant
  /// for the explicit limited-label pairing.
  static const String windowTransfer = 'pq-itu';

  /// The VENDOR-FORCED window dataspace label in yuvDiag mode: BT2020 PQ /
  /// LIMITED 0x11C60000. The vendor gate performs this value for every PQ
  /// variant request while the diag is armed (its dual-layer range
  /// contract); declared here as a documentation constant so the Dart
  /// contract does not depend on a vendor header.
  static const int windowDataSpace = 0x11C60000;

  /// Metadata identity triplet (mks_p1, verbatim): primaries 9 (BT.2020),
  /// range 1, transfer 16 (PQ). HONESTY BOUNDARY: this is a
  /// documentation-level consistency declaration between the route fields
  /// and the mpv fork's constants — [validate] ties the route's
  /// target-prim/target-trc to these values but does NOT (cannot) verify
  /// what the native side actually writes into each buffer. Native buffer
  /// content is device-verification scope and is only ever confirmed on the
  /// device, never by this Dart-side check.
  static const int metadataPrimaries = 9;
  static const int metadataRange = 1;
  static const int metadataTransfer = 16;

  /// Whether [route] is on the YUV presentation carrier: the
  /// `surfacetexture` hwdec is the LG yuv-diag path's ONLY carrier, and a
  /// PQ window request (`pq` or `pq-itu`) on it presents the actual YUV
  /// shape described above — the requested label does not matter (the
  /// vendor forces 0x11C60000 in yuvDiag mode). Only this shape is
  /// asserted against the quad; RGB window routes (including the
  /// limited-label mediacodec-copy convert route, whose carrier is
  /// `mediacodec`/`mediacodec-copy`) have no separate offscreen contract
  /// and are out of scope.
  static bool isYuvWindowRoute(HdrRoute route) =>
      route.hwdec == 'surfacetexture' && windowRequests.contains(route.surfaceTransfer);

  /// The mpv `video-output-levels` value that realizes [offscreenTransfer].
  /// Only the accepted offscreen contract has a mapping; anything else must
  /// never reach mpv.
  static String mpvOutputLevels(String routeOffscreenTransfer) {
    if (routeOffscreenTransfer == offscreenTransfer) return 'full';
    throw StateError(
        'No mpv output-levels mapping for offscreen contract '
        '$routeOffscreenTransfer');
  }

  /// Fail-closed quad assertion. A no-op for every route that is not on the
  /// YUV carrier; otherwise the whole quad must be the accepted
  /// configuration — any single mismatch logs and throws before the backend
  /// issues or applies anything.
  static void validate(HdrRoute route) {
    if (!isYuvWindowRoute(route)) return;
    // Accepted-value guard (compile-time constants vs the euv13/euv17
    // acceptance): a drifted documentation constant must fail loudly in
    // every test run instead of silently redefining the contract.
    assert(windowDataSpace == 0x11C60000);
    assert(metadataPrimaries == 9);
    assert(metadataRange == 1);
    assert(metadataTransfer == 16);
    final List<String> mismatches = <String>[
      if (route.offscreenTransfer != offscreenTransfer)
        'offscreen=${route.offscreenTransfer ?? 'null'} (need $offscreenTransfer)',
      if (route.vo != 'gpu-next') 'vo=${route.vo} (need gpu-next)',
      if (route.topology != HdrTopology.platformView)
        'topology=${route.topology.name} (need platformView)',
      if (route.targetPrim != 'bt.2020')
        'prim=${route.targetPrim ?? 'null'} '
            '(metadata primaries $metadataPrimaries = BT.2020)',
      if (route.targetTrc != 'pq')
        'trc=${route.targetTrc ?? 'null'} '
            '(metadata transfer $metadataTransfer = PQ)',
    ];
    if (mismatches.isNotEmpty) {
      debugPrint('YUV-CONTRACT: presentation contract rejected '
          '(${mismatches.join('; ')})');
      throw StateError(
          'YUV presentation contract rejected: ${mismatches.join('; ')}');
    }
  }
}
