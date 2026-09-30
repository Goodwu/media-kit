/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'package:flutter/services.dart';

/// Complete identity of one Android platform Surface owner.
///
/// The five-part tuple is what makes a JNI address reuse harmless: a late
/// destroy for old A after B is bound selects exactly A's Java owner even
/// when the same `wid` address was recycled.
class AndroidSurfaceAccountId {
  const AndroidSurfaceAccountId({
    required this.handle,
    required this.generation,
    required this.viewId,
    required this.surfaceGeneration,
    required this.wid,
  });

  final int handle;
  final int generation;
  final int viewId;
  final int surfaceGeneration;
  final int wid;

  Map<String, Object> asChannelArguments() => <String, Object>{
        'handle': handle.toString(),
        'generation': generation,
        'viewId': viewId,
        'surfaceGeneration': surfaceGeneration,
        'wid': wid.toString(),
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AndroidSurfaceAccountId &&
        other.handle == handle &&
        other.generation == generation &&
        other.viewId == viewId &&
        other.surfaceGeneration == surfaceGeneration &&
        other.wid == wid;
  }

  @override
  int get hashCode =>
      Object.hash(handle, generation, viewId, surfaceGeneration, wid);

  @override
  String toString() =>
      '$generation/$viewId/$surfaceGeneration/$wid';
}

/// Injectable MethodChannel boundary for the two-phase Android surface
/// release protocol. Unit tests substitute a fake to drive out-of-order,
/// late and failed acknowledgements without device-injected faults.
abstract class PlatformSurfaceReleaseChannel {
  /// Phase one: release the JNI Surface reference. Returns the platform
  /// status (`released`, `alreadyReleased`, or a rejection reason).
  Future<String?> releaseSurface(AndroidSurfaceAccountId owner);

  /// Phase two: the explicit Dart acknowledgement that may remove the
  /// platform's tombstone. Returns whether the platform acknowledged.
  Future<bool?> acknowledgeReleaseSurfaceOwner(AndroidSurfaceAccountId owner);
}

class MethodChannelPlatformSurfaceReleaseChannel
    implements PlatformSurfaceReleaseChannel {
  const MethodChannelPlatformSurfaceReleaseChannel({
    this.channel = const MethodChannel('com.alexmercerind/media_kit_video'),
    this.releaseTimeout = const Duration(seconds: 10),
    this.acknowledgeTimeout = const Duration(seconds: 10),
  });

  final MethodChannel channel;
  final Duration releaseTimeout;
  final Duration acknowledgeTimeout;

  @override
  Future<String?> releaseSurface(AndroidSurfaceAccountId owner) {
    return channel
        .invokeMethod<String>(
          'PlatformVideoView.ReleaseSurface',
          owner.asChannelArguments(),
        )
        .timeout(releaseTimeout);
  }

  @override
  Future<bool?> acknowledgeReleaseSurfaceOwner(AndroidSurfaceAccountId owner) {
    return channel
        .invokeMethod<bool>(
          'PlatformVideoView.ReleaseSurfaceOwner',
          owner.asChannelArguments(),
        )
        .timeout(acknowledgeTimeout);
  }
}

/// The two-phase release state machine:
///
/// 1. `ReleaseSurface` must report `released` or `alreadyReleased` — the call
///    is idempotent until its result has reached Dart.
/// 2. `ReleaseSurfaceOwner` is the explicit Dart acknowledgement that may
///    remove the platform's tombstone.
///
/// Any failure throws and leaves the owner pending: the caller retains it so
/// a retry observes `alreadyReleased` and can repeat the exact
/// acknowledgement.
class SurfaceReleaseProtocol {
  const SurfaceReleaseProtocol(this._channel);

  final PlatformSurfaceReleaseChannel _channel;

  /// Releases [owner] and acknowledges it. Throws on any rejection,
  /// non-acknowledgement or timeout; the owner must stay pending then.
  Future<void> release(AndroidSurfaceAccountId owner) async {
    final status = await _channel.releaseSurface(owner);
    if (status != 'released' && status != 'alreadyReleased') {
      throw StateError(
        'PlatformVideoView.ReleaseSurface rejected $owner: $status',
      );
    }
    final acknowledged = await _channel.acknowledgeReleaseSurfaceOwner(owner);
    if (acknowledged != true) {
      throw StateError(
        'PlatformVideoView.ReleaseSurfaceOwner did not acknowledge $owner.',
      );
    }
  }
}
