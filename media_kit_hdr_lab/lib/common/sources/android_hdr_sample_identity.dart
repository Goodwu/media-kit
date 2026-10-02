// MIGRATED (S10/S13): superseded by HdrRoutePlanner/HdrSourceClassifier in
// media_kit_video/lib/src/hdr/; kept for hdr_lab tests only.
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Identity belongs to file bytes, never to its name or reported track tags.
enum AndroidHdrSample { hdr10, hlgBaseControl, dolbyVisionP84, dolbyVisionP5 }

/// Remove copies left by previous app processes without touching live sessions
/// owned by this process or unrelated files in application support storage.
Future<int> cleanupStaleAndroidHdrSessions(
  Directory parent, {
  required int currentPid,
}) async {
  if (!await parent.exists()) return 0;
  var removed = 0;
  await for (final entry in parent.list(followLinks: false)) {
    if (entry is! Directory) continue;
    final name = entry.uri.pathSegments.where((part) => part.isNotEmpty).last;
    if (!name.startsWith('session-') ||
        name.startsWith('session-$currentPid-')) {
      continue;
    }
    await entry.delete(recursive: true);
    removed++;
  }
  return removed;
}

const androidHdrSampleSha256 = <String, AndroidHdrSample>{
  'e4f869b140e3ef322b7fc63fefe015593708f6443fc79060fa3e7f2234816937':
      AndroidHdrSample.hdr10,
  '7626cac28819ffd1377a712b56c7cc4bbf8677f5db4b39fb0c83f92e58d74443':
      AndroidHdrSample.dolbyVisionP84,
  // Matched 12s diagnostic pair: same decoded base frames and all non-RPU NALs.
  '1755cf6a2ea575816f5f0ab403b9cc47b9577c838289251f7c14b5e33622c2f5':
      AndroidHdrSample.dolbyVisionP84,
  // Rewrapped from the same 12s RPU control for the Texture A/B run; frame
  // MD5 and Profile 8/HLG compatibility were checked after remuxing.
  'd12546647bb9dbb12c00162f3e75f8e1125a7645dc8ba75cd40e39f4a55416e9':
      AndroidHdrSample.dolbyVisionP84,
  '5f7cdd9769068f6e9b0a9a1cf5ecedcd3f47a51d68172ed0fb1469d6e91750f7':
      AndroidHdrSample.hlgBaseControl,
  '328cae5c78ba9b8e579e7352edcfb8f3e9e0c0670849fc8773a8b028d2d1d03e':
      AndroidHdrSample.dolbyVisionP5,
  // GlassBlowing2: Profile 5, 3840x2160, 60000/1001 fps performance sample.
  'afb24b77733a3ca9071f0cfea0d0f7871670a7b6119eb44a314cba974541477c':
      AndroidHdrSample.dolbyVisionP5,
  // Same 4K/50fps P5 video packets, plus a synthetic AAC clock for avsync diagnostics.
  '3d0dd5b00fe8f01add6bfc2eb69feb972748b12f19f2f9d24dd608c919a5daec':
      AndroidHdrSample.dolbyVisionP5,
  // Dolby Laboratories dolby-vision-contents: Sol Levante 1080p/24fps P5.
  '87fe0115f3002a621d2380a9f91852ef91a15854a446efe26de8744f77ef5346':
      AndroidHdrSample.dolbyVisionP5,
  // Dolby Laboratories dolby-vision-contents: Sol Levante 2160p/24fps P5.
  'dacfd04518accd6367530b650dfeea429227df2be171bd99b4bdad36d31bbf9f':
      AndroidHdrSample.dolbyVisionP5,
  // Derived from DV_TestKit_v1 P5 lossless patterns: only HEVC chroma siting
  // was retagged to left, then 24 frames were copied to a 13-second loop.
  // L1 YUV matches the supplied source for every frame; diagnostic use only.
  '74c2cfb6b28095c4bb3b95a57507de699bb8141d62feaedbcb20b964d51a0a98':
      AndroidHdrSample.dolbyVisionP5,
};

class AndroidHdrSampleIdentity {
  const AndroidHdrSampleIdentity(this.sample, this.sha256, this.path);

  final AndroidHdrSample sample;

  /// Empty only for the opt-in, filename-classified diagnostic fixture.
  final String sha256;
  final String path;
}

class StagedAndroidHdrSample {
  StagedAndroidHdrSample(this.identity, this._directory);

  final AndroidHdrSampleIdentity identity;
  final Directory _directory;
  Future<void>? _disposeFuture;

  /// Call only after Player.stop has released the staged media path.
  Future<void> dispose() async {
    final pending = _disposeFuture ??= _directory.delete(recursive: true);
    try {
      await pending;
    } catch (_) {
      if (identical(_disposeFuture, pending)) _disposeFuture = null;
      rethrow;
    }
  }
}

class _DigestCollector implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

class SampleStagingCleanupFailure implements Exception {
  const SampleStagingCleanupFailure(
    this.originalError,
    this.originalStack,
    this.cleanupErrors,
  );

  final Object originalError;
  final StackTrace originalStack;
  final List<Object> cleanupErrors;
}

/// Copies the exact verified bytes into a private directory for Player.open.
/// The returned copy is owned by the caller and must be removed after stop.
Future<StagedAndroidHdrSample> stageAndroidHdrSample(
  String source,
  Directory privateRoot, {
  bool Function()? cancelled,
  Map<String, AndroidHdrSample> knownSha256 = androidHdrSampleSha256,
}) async {
  final uri = Uri.tryParse(source);
  if (uri == null || (uri.hasScheme && uri.scheme != 'file')) {
    throw UnsupportedError('Only local file samples can be staged: $source');
  }
  final input = File(uri.hasScheme ? uri.toFilePath() : source);
  if ((await input.stat()).type != FileSystemEntityType.file) {
    throw StateError('Sample is not a regular file: ${input.path}');
  }
  await privateRoot.create(recursive: true);
  final staging = await privateRoot.createTemp('hdr-open-');
  final output = File('${staging.path}/sample.mp4');
  RandomAccessFile? writer;
  try {
    writer = await output.open(mode: FileMode.write);
    final collector = _DigestCollector();
    final hash = sha256.startChunkedConversion(collector);
    await for (final chunk in input.openRead()) {
      if (cancelled?.call() ?? false) {
        throw StateError('Sample staging cancelled');
      }
      hash.add(chunk);
      await writer.writeFrom(chunk);
    }
    hash.close();
    await writer.flush();
    await writer.close();
    writer = null;
    if (cancelled?.call() ?? false) {
      throw StateError('Sample staging cancelled');
    }
    final digest = collector.value.toString();
    final sample = knownSha256[digest];
    if (sample == null) throw StateError('Unknown sample SHA-256: $digest');
    return StagedAndroidHdrSample(
      AndroidHdrSampleIdentity(sample, digest, output.path),
      staging,
    );
  } catch (error, stack) {
    final cleanupErrors = <Object>[];
    try {
      await writer?.close();
    } catch (cleanupError) {
      cleanupErrors.add(cleanupError);
    }
    try {
      await staging.delete(recursive: true);
    } catch (cleanupError) {
      cleanupErrors.add(cleanupError);
    }
    if (cleanupErrors.isNotEmpty) {
      throw SampleStagingCleanupFailure(error, stack, cleanupErrors);
    }
    Error.throwWithStackTrace(error, stack);
  }
}

/// Hashes a local sample without buffering the entire movie. A replacement
/// during hashing is rejected; the caller must still prevent replacement
/// between verification and Player.open (for example with a private copy).
Future<AndroidHdrSampleIdentity> identifyAndroidHdrSample(
  String source, {
  bool Function()? cancelled,
  Map<String, AndroidHdrSample> knownSha256 = androidHdrSampleSha256,
}) async {
  final uri = Uri.tryParse(source);
  if (uri == null || (uri.hasScheme && uri.scheme != 'file')) {
    throw UnsupportedError('Only local file samples can be verified: $source');
  }
  final file = File(uri.hasScheme ? uri.toFilePath() : source);
  final before = await file.stat();
  if (before.type != FileSystemEntityType.file) {
    throw StateError('Sample is not a regular file: ${file.path}');
  }
  if (cancelled?.call() ?? false) {
    throw StateError('Sample verification cancelled');
  }
  Stream<List<int>> checkedBytes() async* {
    await for (final chunk in file.openRead()) {
      if (cancelled?.call() ?? false) {
        throw StateError('Sample verification cancelled');
      }
      yield chunk;
    }
  }

  final digest = (await sha256.bind(checkedBytes()).first).toString();
  if (cancelled?.call() ?? false) {
    throw StateError('Sample verification cancelled');
  }
  final after = await file.stat();
  if (before.size != after.size ||
      before.modified != after.modified ||
      before.changed != after.changed ||
      after.type != FileSystemEntityType.file) {
    throw StateError('Sample changed during verification: ${file.path}');
  }
  final sample = knownSha256[digest];
  if (sample == null) throw StateError('Unknown sample SHA-256: $digest');
  return AndroidHdrSampleIdentity(sample, digest, file.absolute.path);
}
