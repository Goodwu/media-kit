import 'dart:async';

import 'package:media_kit/media_kit.dart' show FileLoadedRecord;
import 'package:synchronized/synchronized.dart';

import 'hdr_decoder_review.dart';

/// Stable container-level Dolby Vision facts captured for one opened entry.
class HdrContainerSourceSnapshot {
  const HdrContainerSourceSnapshot({
    required this.mediaUri,
    required this.playlistEntryId,
    required this.fileLoadedEpoch,
    required this.videoTrackId,
    required this.codec,
    required this.dvProfile,
    required this.dvCompatibilityId,
    required this.elPresent,
  });

  final String mediaUri;
  final int playlistEntryId;
  final int fileLoadedEpoch;
  final String videoTrackId;
  final String codec;
  final int dvProfile;
  final int dvCompatibilityId;
  final bool elPresent;
}

/// Reads only container/track metadata. A null result means the caller should
/// continue through its ordinary fallback path; source drift is a hard failure.
Future<HdrContainerSourceSnapshot?> gatherContainerSourceSnapshot({
  required Lock lock,
  required String mediaUri,
  required Future<List<String>> Function(List<String>) readProperties,
  required Future<FileLoadedRecord> Function(int, int) waitForFileLoadedEntry,
  required int playlistEntryId,
  required int openedAfterEpoch,
  required int Function() fileLoadedEpoch,
  required bool Function() isCurrent,
  Duration budget = const Duration(seconds: 20),
  Duration Function()? monotonicNow,
  bool unselectedProbe = false,
  Future<void> Function()? verifyUnselectedProbe,
}) async {
  final stopwatch = Stopwatch()..start();
  final wallClock = Stopwatch()..start();
  final now = monotonicNow ?? (() => stopwatch.elapsed);
  final started = now();

  Duration remaining() {
    if (!isCurrent()) {
      throw const HdrDecoderReviewFailure('Superseded container discovery');
    }
    final elapsed = now() - started;
    final wallElapsed = wallClock.elapsed;
    final left = budget - (elapsed > wallElapsed ? elapsed : wallElapsed);
    if (left <= Duration.zero) {
      throw TimeoutException('Container discovery budget exhausted');
    }
    return left;
  }

  Future<T> bounded<T>(Future<T> Function() operation) async {
    final left = remaining();
    final pending = operation();
    try {
      final result = await pending.timeout(left);
      remaining();
      return result;
    } on TimeoutException {
      // A native read cannot be cancelled. Drain it before a surrounding
      // Player lock can be released.
      try {
        await pending;
      } catch (_) {}
      if (!isCurrent()) {
        throw const HdrDecoderReviewFailure('Superseded container discovery');
      }
      throw TimeoutException('Container discovery budget exhausted');
    }
  }

  Future<List<String>> readGroup(List<String> names) async {
    final values = await bounded(() => readProperties(names));
    if (values.length != names.length) {
      throw const HdrDecoderReviewFailure(
          'Incomplete container property batch');
    }
    return values;
  }

  Future<T> passiveWait<T>(Future<T> future) async {
    final result = Completer<T>();
    future.then<void>(result.complete,
        onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    });
    while (true) {
      final left = remaining();
      final tick = Completer<void>();
      final timer = Timer(
          left < const Duration(milliseconds: 50)
              ? left
              : const Duration(milliseconds: 50),
          tick.complete);
      await Future.any<void>([result.future.then<void>((_) {}), tick.future]);
      timer.cancel();
      if (result.isCompleted) {
        final value = await result.future;
        remaining();
        return value;
      }
      remaining();
    }
  }

  final loaded = await passiveWait(
      waitForFileLoadedEntry(playlistEntryId, openedAfterEpoch));
  final expectedEpoch = openedAfterEpoch + 1;
  if (loaded.playlistEntryId != playlistEntryId ||
      loaded.epoch != expectedEpoch ||
      fileLoadedEpoch() != expectedEpoch) {
    throw const HdrDecoderReviewFailure(
        'File-loaded container entry/epoch differs');
  }

  const identityProperties = <String>[
    'path',
    'playlist/0/id',
    'playlist/0/filename',
  ];
  const trackProperty = 'current-tracks/video/id';
  const trackSelectionProperties = <String>[
    'current-tracks/video/main-selection',
    'current-tracks/video/selected',
  ];
  const metadataProperties = <String>[
    'current-tracks/video/codec',
    'current-tracks/video/dolby-vision-profile',
    'current-tracks/video/dolby-vision-compatibility-id',
    'current-tracks/video/dolby-vision-el-present',
  ];

  Future<void> verifySource() async {
    remaining();
    if (fileLoadedEpoch() != expectedEpoch) {
      throw const HdrDecoderReviewFailure('Container source epoch drifted');
    }
    final values = await readGroup(identityProperties);
    remaining();
    if (values[0] != mediaUri ||
        values[1] != playlistEntryId.toString() ||
        values[2] != mediaUri ||
        fileLoadedEpoch() != expectedEpoch) {
      throw const HdrDecoderReviewFailure('Container source identity drifted');
    }
  }

  Future<void> verifyProbeOwnership() async {
    final verify = verifyUnselectedProbe;
    if (verify == null) {
      throw ArgumentError('Unselected probe requires an ownership verifier');
    }
    await bounded(verify);
  }

  Future<HdrContainerSourceSnapshot?> readUnselectedProbe() async {
    await verifyProbeOwnership();
    final countRaw = (await readGroup(const ['track-list/count'])).single;
    final count = int.tryParse(countRaw);
    if (count == null || count < 0 || count > 64) return null;
    const trackFields = <String>[
      'id',
      'type',
      'external',
      'albumart',
      'image',
      'selected',
      'main-selection',
      'codec',
      'dolby-vision-profile',
      'dolby-vision-compatibility-id',
      'dolby-vision-el-present',
    ];
    final names = <String>[
      'track-list/count',
      for (var i = 0; i < count; i++)
        for (final field in trackFields) 'track-list/$i/$field',
    ];
    final first = await readGroup(names);
    final second = await readGroup(names);
    await verifyProbeOwnership();
    if (first[0] != countRaw || second[0] != countRaw) return null;
    for (var i = 1; i < first.length; i++) {
      if (first[i] != second[i]) return null;
    }

    final fieldsPerTrack = trackFields.length;
    final candidates = <List<String>>[];
    for (var i = 0; i < count; i++) {
      final start = 1 + i * fieldsPerTrack;
      final values = first.sublist(start, start + fieldsPerTrack);
      final selected = values[5].trim().toLowerCase();
      final mainSelection = values[6].trim();
      if (selected == 'yes' || mainSelection.isNotEmpty) {
        throw const HdrDecoderReviewFailure(
            'A track became selected during container probe');
      }
      if (selected.isNotEmpty && selected != 'no' && selected != 'false') {
        return null;
      }
      final type = values[1].trim().toLowerCase();
      if (type != 'video') continue;
      final external = _parseTrackFlag(values[2]);
      final albumart = _parseTrackFlag(values[3]);
      final image = _parseTrackFlag(values[4]);
      if (external == null || albumart == null || image == null) return null;
      if (!external && !albumart && !image) candidates.add(values);
    }
    if (candidates.length != 1) return null;
    final candidate = candidates.single;
    final id = candidate[0].trim();
    final codec = candidate[7].trim().toLowerCase();
    final profile = int.tryParse(candidate[8]);
    final compatibility = int.tryParse(candidate[9]);
    final el = _parseTrackFlag(candidate[10]);
    if (id.isEmpty ||
        codec != 'hevc' ||
        profile == null ||
        compatibility == null ||
        el == null) {
      return null;
    }
    if (el ||
        !((profile == 5 && compatibility == 0) ||
            (profile == 8 && compatibility == 4))) {
      return null;
    }
    return HdrContainerSourceSnapshot(
      mediaUri: mediaUri,
      playlistEntryId: playlistEntryId,
      fileLoadedEpoch: expectedEpoch,
      videoTrackId: id,
      codec: codec,
      dvProfile: profile,
      dvCompatibilityId: compatibility,
      elPresent: el,
    );
  }

  var admitted = false;
  final lockWork = lock.synchronized(() async {
    admitted = true;
    remaining(); // A late admission must not issue any property reads.
    await verifySource();
    if (unselectedProbe) {
      final snapshot = await readUnselectedProbe();
      await verifySource();
      return snapshot;
    }
    final trackBefore = (await readGroup(const [trackProperty])).single;
    final selectionBefore = await readGroup(trackSelectionProperties);
    final first = await readGroup(metadataProperties);
    final second = await readGroup(metadataProperties);
    final selectionAfter = await readGroup(trackSelectionProperties);
    final trackAfter = (await readGroup(const [trackProperty])).single;
    await verifySource();
    if (trackBefore.isEmpty || trackAfter.isEmpty) return null;
    if (trackAfter != trackBefore) {
      throw const HdrDecoderReviewFailure('Video track identity drifted');
    }
    if (selectionBefore[0] != selectionAfter[0] ||
        selectionBefore[1] != selectionAfter[1] ||
        selectionBefore[0] != '0' ||
        selectionBefore[1] != 'yes') {
      return null;
    }
    if (first.any((value) => value.isEmpty) ||
        first.length != second.length ||
        List<int>.generate(first.length, (index) => index)
            .any((index) => first[index] != second[index])) {
      return null;
    }

    final codec = first[0].trim().toLowerCase();
    final profile = int.tryParse(first[1]);
    final compatibility = int.tryParse(first[2]);
    final elRaw = first[3].trim().toLowerCase();
    final el = switch (elRaw) {
      '1' || 'yes' || 'true' => true,
      '0' || 'no' || 'false' => false,
      _ => null,
    };
    if (codec != 'hevc' ||
        profile == null ||
        compatibility == null ||
        el == null) {
      return null;
    }
    if (el ||
        !((profile == 5 && compatibility == 0) ||
            (profile == 8 && compatibility == 4))) {
      return null;
    }
    return HdrContainerSourceSnapshot(
      mediaUri: mediaUri,
      playlistEntryId: playlistEntryId,
      fileLoadedEpoch: expectedEpoch,
      videoTrackId: trackBefore,
      codec: codec,
      dvProfile: profile,
      dvCompatibilityId: compatibility,
      elPresent: el,
    );
  });
  final observed = Completer<Object?>();
  // The first outer deadline check may fail synchronously, before Future.any
  // subscribes. Observe errors even then; the original lockWork is drained
  // and its failure is propagated by the owning catch below.
  unawaited(observed.future.catchError((Object _) => null));
  lockWork.then<void>(observed.complete,
      onError: (Object error, StackTrace stack) {
    if (!observed.isCompleted) observed.completeError(error, stack);
  });
  try {
    while (true) {
      final left = remaining();
      final tick = Completer<void>();
      final timer = Timer(
          left < const Duration(milliseconds: 50)
              ? left
              : const Duration(milliseconds: 50),
          tick.complete);
      try {
        await Future.any<void>([observed.future, tick.future]);
      } finally {
        timer.cancel();
      }
      if (observed.isCompleted) {
        final value = await lockWork;
        remaining();
        return value;
      }
      remaining();
    }
  } catch (_) {
    if (admitted) {
      try {
        await lockWork;
      } catch (_) {}
    }
    // A queued callback remains attached and rejects late admission before
    // any reads. Admitted work is always drained, including synchronous
    // expiry at the very first outer deadline check.
    rethrow;
  }
}

bool? _parseTrackFlag(String raw) => switch (raw.trim().toLowerCase()) {
      'yes' || 'true' || '1' => true,
      'no' || 'false' || '0' => false,
      _ => null,
    };
