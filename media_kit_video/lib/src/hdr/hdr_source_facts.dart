/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:media_kit/media_kit.dart' show VideoParams;

import 'hdr_source_descriptor.dart';

/// Evidence used for an effective source field. These are not presentation
/// certifications. In particular, a caller hint never becomes a track fact
/// merely because decoding started or because a later observation was empty.
enum HdrSourceFactOrigin { hint, track, decoder, profileRule }

enum HdrSourceField {
  codec,
  transfer,
  primaries,
  dynamicMetadata,
  dvProfile,
  dvCompatibilityId,
  enhancementLayer,
}

/// Two different affirmative track values were reported for one logical open.
/// A missing value is not a contradiction. A track correcting a caller hint
/// is also not a contradiction; it is a stronger observation.
class HdrSourceFactConflict {
  const HdrSourceFactConflict(this.field, this.previous, this.observed);

  final HdrSourceField field;
  final Object previous;
  final Object observed;
}

/// Immutable source evidence owned by ONE logical open. Reopens of that source
/// carry this value in their plan; a new open creates a new value from its hint.
/// Never cache it by URI or on a process-wide classifier.
///
/// [source] describes the original stream as far as it is known. [videoParams]
/// and [hdrVividOnFrame] are the latest decoder observation, including missing
/// values; they are not overwritten to make them agree with the source.
/// `video-params` is decoder output (with mpv overrides), not proof of original
/// bitstream colors or final window/panel output. Only ordinary color-preserving
/// decode routes may use those tags as a source inference. Native DV processing
/// must pass `inferSourceColorFromDecoder: false`.
class HdrSourceFacts {
  HdrSourceFacts._({
    required this.initialHint,
    required this.source,
    required Map<HdrSourceField, HdrSourceFactOrigin> origins,
    required List<HdrSourceFactConflict> conflicts,
    this.videoParams,
    this.hdrVividOnFrame,
    this.reviewCount = 0,
  }) : origins = Map.unmodifiable(origins),
       conflicts = List.unmodifiable(conflicts);

  factory HdrSourceFacts.fromHint(HdrSourceDescriptor? hint) {
    final source = hint ?? const HdrSourceDescriptor();
    return HdrSourceFacts._(
      initialHint: hint,
      source: source,
      origins: {
        if (source.codec.isNotEmpty)
          HdrSourceField.codec: HdrSourceFactOrigin.hint,
        if (source.transfer != null)
          HdrSourceField.transfer: HdrSourceFactOrigin.hint,
        if (source.primaries != null)
          HdrSourceField.primaries: HdrSourceFactOrigin.hint,
        if (source.dynamicMetadata != HdrDynamicMetadata.none)
          HdrSourceField.dynamicMetadata: HdrSourceFactOrigin.hint,
        if (source.dvProfile != null)
          HdrSourceField.dvProfile: HdrSourceFactOrigin.hint,
        if (source.dvCompatibilityId != null)
          HdrSourceField.dvCompatibilityId: HdrSourceFactOrigin.hint,
        if (source.enhancementLayer != null)
          HdrSourceField.enhancementLayer: HdrSourceFactOrigin.hint,
      },
      conflicts: const [],
    );
  }

  final HdrSourceDescriptor? initialHint;
  final HdrSourceDescriptor source;
  final Map<HdrSourceField, HdrSourceFactOrigin> origins;
  final List<HdrSourceFactConflict> conflicts;
  final VideoParams? videoParams;
  final bool? hdrVividOnFrame;
  final int reviewCount;

  bool get hasConflict => conflicts.isNotEmpty;
  bool get retainsHint => origins.containsValue(HdrSourceFactOrigin.hint);

  HdrSourceFacts observe({
    VideoParams? videoParams,
    int? dolbyVisionProfile,
    String codec = '',
    int? dvCompatibilityId,
    bool? dvElPresent,
    bool? hdrVivid,
    required bool inferSourceColorFromDecoder,
  }) {
    final nextOrigins = Map<HdrSourceField, HdrSourceFactOrigin>.of(origins);
    final nextConflicts = List<HdrSourceFactConflict>.of(conflicts);

    T? track<T extends Object>(HdrSourceField field, T? value, T? previous) {
      if (value == null) {
        return previous;
      }
      if (origins[field] == HdrSourceFactOrigin.track &&
          previous != null &&
          previous != value) {
        nextConflicts.add(HdrSourceFactConflict(field, previous, value));
      }
      nextOrigins[field] = HdrSourceFactOrigin.track;
      return value;
    }

    final reportedProfile = dolbyVisionProfile != null && dolbyVisionProfile > 0
        ? dolbyVisionProfile
        : null;
    final profile = track(
      HdrSourceField.dvProfile,
      reportedProfile,
      source.dvProfile,
    );
    // Do not combine a newly observed profile with another profile's hinted
    // compatibility/EL/colors. Missing fields stay missing after that correction.
    final profileChanged = reportedProfile != null &&
        reportedProfile != source.dvProfile;
    if (profileChanged) {
      for (final field in [
        HdrSourceField.dvCompatibilityId,
        HdrSourceField.enhancementLayer,
        HdrSourceField.transfer,
        HdrSourceField.primaries,
      ]) {
        nextOrigins.remove(field);
      }
    }

    final reportedCompatibility =
        dvCompatibilityId != null && dvCompatibilityId >= 0
        ? dvCompatibilityId
        : null;
    var compatibility = track(
      HdrSourceField.dvCompatibilityId,
      reportedCompatibility,
      profileChanged ? null : source.dvCompatibilityId,
    );
    var enhancementLayer = track(
      HdrSourceField.enhancementLayer,
      dvElPresent,
      profileChanged ? null : source.enhancementLayer,
    );
    final reportedCodec = codec.trim();
    var resolvedCodec = track(
      HdrSourceField.codec,
      reportedCodec.isEmpty ? null : reportedCodec,
      source.codec.isEmpty ? null : source.codec,
    ) ?? '';

    var metadata = source.dynamicMetadata;
    if (profile != null || reportedCompatibility != null || dvElPresent != null) {
      metadata = HdrDynamicMetadata.dolbyVision;
      nextOrigins[HdrSourceField.dynamicMetadata] =
          nextOrigins[HdrSourceField.dvProfile] ?? HdrSourceFactOrigin.track;
    } else if (metadata != HdrDynamicMetadata.dolbyVision && hdrVivid == true) {
      metadata = HdrDynamicMetadata.hdrVivid;
      nextOrigins[HdrSourceField.dynamicMetadata] = HdrSourceFactOrigin.decoder;
    }
    // A frame without side data cannot disprove the stream's dynamic metadata.
    // This also preserves HDR10+ hints on backends lacking an HDR10+ property.
    var transfer = profileChanged ? null : source.transfer;
    var primaries = profileChanged ? null : source.primaries;
    final gamma = _nonempty(videoParams?.gamma);
    final incomingPrimaries = _nonempty(videoParams?.primaries);
    if (inferSourceColorFromDecoder) {
      if (gamma != null &&
          HdrSourceDescriptor.compatibilityFromTransfer(gamma) != null) {
        transfer = gamma;
        nextOrigins[HdrSourceField.transfer] = HdrSourceFactOrigin.decoder;
      }
      if (incomingPrimaries != null) {
        primaries = incomingPrimaries;
        nextOrigins[HdrSourceField.primaries] = HdrSourceFactOrigin.decoder;
      }
    }

    if (metadata == HdrDynamicMetadata.dolbyVision) {
      // Existing explicit track compatibility always outranks a frame gamma.
      // A decoded gamma may supply missing compatibility on a color-preserving
      // route, but cannot overwrite an explicit hint/track compatibility or
      // authorize inference on a native-DV decoder that transformed pixels.
      final inferred = inferSourceColorFromDecoder
          ? HdrSourceDescriptor.compatibilityFromTransfer(gamma)
          : null;
      if ((profile == 8 || profile == 10) &&
          reportedCompatibility == null &&
          (compatibility == null ||
              nextOrigins[HdrSourceField.dvCompatibilityId] ==
                  HdrSourceFactOrigin.decoder) &&
          inferred != null) {
        compatibility = inferred;
        nextOrigins[HdrSourceField.dvCompatibilityId] =
            HdrSourceFactOrigin.decoder;
      }
      if (compatibility == null && (profile == 5 || profile == 7)) {
        compatibility = profile == 5 ? 0 : 6;
        nextOrigins[HdrSourceField.dvCompatibilityId] =
            HdrSourceFactOrigin.profileRule;
      }
      // A compatibility family describes the original base layer, even when
      // native decoding reports a different transfer for its output frame.
      if ((profile == 8 || profile == 10 || profile == 7) &&
          compatibility != null) {
        if (compatibility == 1 || compatibility == 4 ||
            (profile == 7 && compatibility == 6)) {
          transfer = compatibility == 4 ? 'hlg' : 'pq';
          nextOrigins[HdrSourceField.transfer] =
              nextOrigins[HdrSourceField.dvCompatibilityId] ??
              HdrSourceFactOrigin.profileRule;
        } else if (compatibility == 2 &&
            HdrSourceDescriptor.compatibilityFromTransfer(transfer) != 2) {
          // SDR compatibility does not identify one precise SDR gamma.
          transfer = null;
          nextOrigins.remove(HdrSourceField.transfer);
        }
      }
      if (profile == 10 && resolvedCodec.isEmpty) {
        resolvedCodec = 'av1';
        nextOrigins[HdrSourceField.codec] = HdrSourceFactOrigin.profileRule;
      }
    } else if (videoParams != null && enhancementLayer == null) {
      enhancementLayer = false;
      nextOrigins[HdrSourceField.enhancementLayer] =
          HdrSourceFactOrigin.profileRule;
    }

    return HdrSourceFacts._(
      initialHint: initialHint,
      source: HdrSourceDescriptor(
        codec: resolvedCodec,
        transfer: transfer,
        primaries: primaries,
        dynamicMetadata: metadata,
        dvProfile: profile,
        dvCompatibilityId: compatibility,
        enhancementLayer: enhancementLayer,
      ),
      origins: nextOrigins,
      conflicts: nextConflicts,
      videoParams: videoParams,
      hdrVividOnFrame: hdrVivid,
      reviewCount: reviewCount + 1,
    );
  }

  static String? _nonempty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ||
            normalized == 'unknown' || normalized == 'auto' ||
            normalized == 'unspecified'
        ? null
        : normalized;
  }
}
