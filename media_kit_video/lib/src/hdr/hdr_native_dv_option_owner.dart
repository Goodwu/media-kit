import 'package:media_kit/media_kit.dart' show FileLoadedRecord;

/// Per-backend ownership of the two native Dolby Vision options.
/// This is configuration ownership, not decoder or display verification.
class HdrOptionSourceIdentity {
  const HdrOptionSourceIdentity({
    required this.player,
    required this.path,
    required this.playlistEntryId,
    required this.fileLoadedEpoch,
  });

  final Object player;
  final String path;
  final String playlistEntryId;
  final int fileLoadedEpoch;

  @override
  bool operator ==(Object other) =>
      other is HdrOptionSourceIdentity &&
      identical(player, other.player) &&
      path == other.path &&
      playlistEntryId == other.playlistEntryId &&
      fileLoadedEpoch == other.fileLoadedEpoch;

  @override
  int get hashCode => Object.hash(
      identityHashCode(player), path, playlistEntryId, fileLoadedEpoch);
}

/// Samples the same source endpoints twice in one API-isolate request.
/// Properties are still read in sequence; the Player lock and epoch fence
/// retain the existing managed-source ownership contract.
Future<HdrOptionSourceIdentity> readHdrOptionSourceIdentity({
  required Object player,
  required int Function() fileLoadedEpoch,
  required Future<List<String>> Function(List<String>) readProperties,
}) async {
  final epoch = fileLoadedEpoch();
  final values = await readProperties(
      const ['path', 'playlist/0/id', 'path', 'playlist/0/id']);
  if (values.length != 4 ||
      values[0] != values[2] ||
      values[1] != values[3] ||
      fileLoadedEpoch() != epoch) {
    throw StateError('Media changed while reading native DV option identity');
  }
  return HdrOptionSourceIdentity(
    player: player,
    path: values[0],
    playlistEntryId: values[1],
    fileLoadedEpoch: epoch,
  );
}

/// Captured under the Player lock. It records one stop operation's result,
/// not authority to use that result after releasing the lock. Before an
/// owner update the backend must lock again and verify [stopped] is current.
class HdrNativeDvStoppedCapture {
  const HdrNativeDvStoppedCapture({
    required this.before,
    required this.stopped,
    this.operationError,
    this.operationStack,
  });
  final HdrOptionSourceIdentity before;
  final HdrOptionSourceIdentity stopped;
  final Object? operationError;
  final StackTrace? operationStack;
}

/// The entry verified immediately after this backend's own open. Retained
/// until FILE_LOADED is acknowledged or controlled cleanup finishes. An
/// arbitrary current entry, even one with the same URI, is never adopted.
class HdrNativeDvPendingOpen {
  const HdrNativeDvPendingOpen({
    required this.before,
    required this.mediaUri,
    required this.playlistEntryId,
  });

  final HdrOptionSourceIdentity before;
  final String mediaUri;
  final int playlistEntryId;

  void _validateBoundary() {
    if (before.path.isNotEmpty ||
        before.playlistEntryId.isNotEmpty ||
        playlistEntryId < 0) {
      throw StateError('Native DV open has no verified stopped/entry boundary');
    }
  }

  Future<HdrOptionSourceIdentity> confirmForCleanup({
    required Future<HdrOptionSourceIdentity> Function() readIdentity,
    required Future<String> Function() readPlaylistFilename,
    required Future<FileLoadedRecord> Function(int, int) waitForFileLoadedEntry,
    bool afterOwnStop = false,
    bool requireLoaded = false,
    Duration budget = const Duration(seconds: 8),
  }) async {
    _validateBoundary();
    final current = await readIdentity();
    final stopped = current.path.isEmpty && current.playlistEntryId.isEmpty;
    if (!identical(current.player, before.player) ||
        current.fileLoadedEpoch < before.fileLoadedEpoch ||
        current.fileLoadedEpoch > before.fileLoadedEpoch + 1 ||
        (stopped && !afterOwnStop) ||
        (!stopped &&
            (current.playlistEntryId != playlistEntryId.toString() ||
                (current.path.isNotEmpty && current.path != mediaUri) ||
                await readPlaylistFilename() != mediaUri))) {
      throw StateError('Pending native DV open crossed an unowned source');
    }
    var confirmed = current;
    if (requireLoaded || current.fileLoadedEpoch > before.fileLoadedEpoch) {
      final loaded =
          await waitForFileLoadedEntry(playlistEntryId, before.fileLoadedEpoch)
              .timeout(budget);
      if (loaded.playlistEntryId != playlistEntryId ||
          loaded.epoch != before.fileLoadedEpoch + 1) {
        throw StateError(
            'No matching single FILE_LOADED for owned native DV entry');
      }
      confirmed = await readIdentity();
      if (!identical(confirmed.player, before.player) ||
          confirmed.fileLoadedEpoch != loaded.epoch ||
          (stopped
              ? confirmed.path.isNotEmpty ||
                  confirmed.playlistEntryId.isNotEmpty
              : confirmed.path != mediaUri ||
                  confirmed.playlistEntryId != playlistEntryId.toString())) {
        throw StateError(
            'Native DV source changed before load acknowledgement');
      }
    }
    if ((!stopped && await readPlaylistFilename() != mediaUri) ||
        await readIdentity() != confirmed) {
      throw StateError('Native DV pending entry changed during confirmation');
    }
    return confirmed;
  }
}

/// Keeps both failures visible when applying an option and rolling it back
/// fail. Pending or externally changed values stay owned for an explicit retry.
class HdrNativeDvOptionFailure implements Exception {
  HdrNativeDvOptionFailure(this.operationError, this.restoreErrors);
  final Object? operationError;
  final Map<String, Object> restoreErrors;

  @override
  String toString() => 'HdrNativeDvOptionFailure(operation: $operationError, '
      'restore: $restoreErrors)';
}

class _OwnedOption {
  _OwnedOption(this.original, this.requested);
  final String original;
  final String requested;
}

/// Facts from existing identity-guarded reads only; no extra native reads.
enum HdrNativeDvOptionDiagnosticPurpose {
  originals,
  apply,
  restore,
  restoreNoWrite,
  rebind,
  restoreFailure,
  beginFailure,
}

/// Immutable envelope with an opaque, non-authoritative transaction identity.
/// Do not use identityHashCode as a unique key. Raw errors may be mutable.
/// Notification-only observers must return synchronously without I/O, Player
/// calls, ownership/reentry, or output mutation. Throw isolation does not
/// protect against an observer that blocks or deliberately reenters playback.
class HdrNativeDvOptionDiagnostic {
  const HdrNativeDvOptionDiagnostic({
    required this.transaction,
    required this.sourcePath,
    required this.sourcePlaylistEntryId,
    required this.sourceFileLoadedEpoch,
    required this.purpose,
    this.name,
    this.original,
    this.requested,
    this.observed,
    this.error,
    this.stack,
  });
  final Object transaction;
  final String sourcePath;
  final String sourcePlaylistEntryId;
  final int sourceFileLoadedEpoch;
  final HdrNativeDvOptionDiagnosticPurpose purpose;
  final String? name;
  final String? original;
  final String? requested;
  final String? observed;
  final Object? error;
  final StackTrace? stack;
}

class HdrNativeDvOptionOwner {
  HdrNativeDvOptionOwner({
    required this.readProperty,
    required this.setPropertyStrict,
    required this.readIdentity,
    this.readProperties,
    this.currentFileLoadedEpoch,
    this.onDiagnostic,
  });

  static const vdOption = 'vd-lavc-o';
  static const renderOption = 'mediacodec-embed-render-mode';
  final Future<String> Function(String) readProperty;
  final Future<void> Function(String, String) setPropertyStrict;
  final Future<HdrOptionSourceIdentity> Function() readIdentity;
  final Future<List<String>> Function(List<String>)? readProperties;
  final int Function()? currentFileLoadedEpoch;
  final Map<String, _OwnedOption> _pending = {};
  HdrOptionSourceIdentity? _identity;
  bool _busy = false;
  bool _requiresStoppedRestore = false;
  final void Function(HdrNativeDvOptionDiagnostic)? onDiagnostic;
  Object? _diagnosticTransaction;
  bool _emittingDiagnostic = false;

  void _emit(
    HdrNativeDvOptionDiagnosticPurpose purpose, {
    String? name,
    String? original,
    String? requested,
    String? observed,
    Object? error,
    StackTrace? stack,
  }) {
    final observer = onDiagnostic;
    if (observer == null || _emittingDiagnostic) return;
    _emittingDiagnostic = true;
    try {
      final identity = _identity;
      final transaction = _diagnosticTransaction;
      if (identity == null || transaction == null) return;
      observer(HdrNativeDvOptionDiagnostic(
        transaction: transaction,
        sourcePath: identity.path,
        sourcePlaylistEntryId: identity.playlistEntryId,
        sourceFileLoadedEpoch: identity.fileLoadedEpoch,
        purpose: purpose,
        name: name,
        original: original,
        requested: requested,
        observed: observed,
        error: error,
        stack: stack,
      ));
    } catch (_) {
      // Projection/callback failures cannot affect ownership or error precedence.
    } finally {
      _emittingDiagnostic = false;
    }
  }

  bool get active => _identity != null;
  HdrOptionSourceIdentity? get identity => _identity;

  Future<void> assertCurrent() async {
    final expected = _identity;
    if (expected == null) return;
    if (await readIdentity() != expected || _identity != expected) {
      throw StateError('Native DV option source identity changed');
    }
  }

  /// Called only after the backend proves its own stop/open boundary. It
  /// does not automatically adopt whichever source happens to be current.
  Future<void> rebind(
    HdrOptionSourceIdentity previous,
    HdrOptionSourceIdentity next,
  ) async {
    if (_busy ||
        _identity != previous ||
        !identical(previous.player, next.player)) {
      throw StateError('Invalid native DV option identity transition');
    }
    _busy = true;
    try {
      if (await readIdentity() != next || _identity != previous) {
        throw StateError(
            'Native DV option transition changed while confirming');
      }
      _identity = next;
      _emit(HdrNativeDvOptionDiagnosticPurpose.rebind);
    } finally {
      _busy = false;
    }
  }

  Future<List<String>> _readMany(List<String> names) async {
    final batchReader = readProperties;
    final epochReader = currentFileLoadedEpoch;
    final expected = _identity;
    if (batchReader != null && epochReader != null && expected != null) {
      if (_identity != expected || epochReader() != expected.fileLoadedEpoch) {
        throw StateError('Native DV option source identity changed');
      }
      final properties = <String>[];
      for (final name in names) {
        properties.addAll([
          'path',
          'playlist/0/id',
          'path',
          'playlist/0/id',
          name,
          'path',
          'playlist/0/id',
          'path',
          'playlist/0/id',
        ]);
      }
      final values = await batchReader(properties);
      if (_identity != expected ||
          epochReader() != expected.fileLoadedEpoch ||
          values.length != names.length * 9) {
        throw StateError('Native DV option source identity changed');
      }
      final result = <String>[];
      for (var group = 0; group < names.length; group++) {
        final offset = group * 9;
        if (values[offset] != expected.path ||
            values[offset + 1] != expected.playlistEntryId ||
            values[offset + 2] != expected.path ||
            values[offset + 3] != expected.playlistEntryId ||
            values[offset + 5] != expected.path ||
            values[offset + 6] != expected.playlistEntryId ||
            values[offset + 7] != expected.path ||
            values[offset + 8] != expected.playlistEntryId) {
          throw StateError('Native DV option source identity changed');
        }
        result.add(values[offset + 4]);
      }
      return result;
    }
    final values = <String>[];
    for (final name in names) {
      await assertCurrent();
      values.add(await readProperty(name));
      await assertCurrent();
    }
    return values;
  }

  Future<String> _read(String name) async {
    return (await _readMany([name])).single;
  }

  Future<void> _write(String name, String value,
      HdrNativeDvOptionDiagnosticPurpose purpose) async {
    await assertCurrent();
    await setPropertyStrict(name, value);
    await assertCurrent();
    final actual = await _read(name);
    if (actual != value) {
      throw StateError('$name rejected: requested=$value actual=$actual');
    }
    _emit(purpose,
        name: name,
        original: _pending[name]?.original,
        requested: value,
        observed: actual);
  }

  Future<void> begin({
    required HdrOptionSourceIdentity stoppedIdentity,
    required String vd,
    required String renderMode,
  }) async {
    if (_busy || active) {
      throw StateError('Native DV option transaction is still owned');
    }
    if (vd != 'native_dv=1' ||
        (renderMode != 'timed' && renderMode != 'boolean')) {
      throw StateError('Unsupported native DV option pair');
    }
    if (stoppedIdentity.path.isNotEmpty ||
        stoppedIdentity.playlistEntryId.isNotEmpty) {
      throw StateError('Native DV requires a verified stopped source');
    }
    _busy = true;
    try {
      // A current source is never newly adopted here. The caller captured
      // this stopped proof in the same Player admission lock as its stop.
      if (await readIdentity() != stoppedIdentity) {
        throw StateError('Stopped source changed before native DV options');
      }
      _identity = stoppedIdentity;
      if (onDiagnostic != null) _diagnosticTransaction = Object();
      // Capture BOTH before any write. Empty vd-lavc-o is a legal value.
      final originalVd = await _read(vdOption);
      final originalMode = await _read(renderOption);
      if (originalVd.isNotEmpty) {
        throw StateError('Native DV cannot replace existing vd-lavc-o');
      }
      if (originalMode != 'boolean' && originalMode != 'timed') {
        throw StateError('Cannot capture native DV render-mode');
      }
      _emit(HdrNativeDvOptionDiagnosticPurpose.originals,
          name: vdOption,
          original: originalVd,
          requested: vd,
          observed: originalVd);
      _emit(HdrNativeDvOptionDiagnosticPurpose.originals,
          name: renderOption,
          original: originalMode,
          requested: renderMode,
          observed: originalMode);
      for (final item in [
        MapEntry(vdOption, _OwnedOption(originalVd, vd)),
        MapEntry(renderOption, _OwnedOption(originalMode, renderMode)),
      ]) {
        // A strict setter can fail after changing the value, so record the
        // attempted write before awaiting its acknowledgement.
        _pending[item.key] = item.value;
        await _write(item.key, item.value.requested,
            HdrNativeDvOptionDiagnosticPurpose.apply);
      }
    } catch (error, stack) {
      _emit(HdrNativeDvOptionDiagnosticPurpose.beginFailure,
          error: error, stack: stack);
      final failures = await _restore();
      if (failures.isNotEmpty) {
        throw HdrNativeDvOptionFailure(error, failures);
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      _busy = false;
    }
  }

  /// Takes ownership of an existing, still decoderless probe entry. The
  /// caller holds Player.lock and supplies the probe's entry-specific proof.
  /// Unlike [begin], failure retains ownership: terminate this entry before
  /// restoring the native pair, since a setter may have changed native state.
  Future<void> beginFromDecoderlessProbe({
    required HdrOptionSourceIdentity entryIdentity,
    required String originalVd,
    required String originalRenderMode,
    required Future<void> Function() verifyDecoderlessProbe,
    required String vd,
    required String renderMode,
  }) async {
    if (_busy || active) {
      throw StateError('Native DV option transaction is still owned');
    }
    if (entryIdentity.path.isEmpty ||
        entryIdentity.playlistEntryId.isEmpty ||
        vd != 'native_dv=1' ||
        (renderMode != 'timed' && renderMode != 'boolean') ||
        originalVd.isNotEmpty ||
        (originalRenderMode != 'boolean' && originalRenderMode != 'timed')) {
      throw StateError('Invalid decoderless probe native DV admission');
    }
    _busy = true;
    _identity = entryIdentity;
    _requiresStoppedRestore = true;
    if (onDiagnostic != null) _diagnosticTransaction = Object();
    try {
      await assertCurrent();
      await verifyDecoderlessProbe();
      final originals = await _readMany([vdOption, renderOption]);
      await verifyDecoderlessProbe();
      if (originals[0] != originalVd || originals[1] != originalRenderMode) {
        throw StateError('Native DV probe baseline changed before promotion');
      }
      for (final item in [
        MapEntry(vdOption, _OwnedOption(originalVd, vd)),
        MapEntry(renderOption, _OwnedOption(originalRenderMode, renderMode)),
      ]) {
        _pending[item.key] = item.value;
        _emit(HdrNativeDvOptionDiagnosticPurpose.originals,
            name: item.key,
            original: item.value.original,
            requested: item.value.requested,
            observed: item.value.original);
      }
      final expectedPair = [originalVd, originalRenderMode];
      var pairIndex = 0;
      for (final item in _pending.entries) {
        await verifyDecoderlessProbe();
        final actualPair = await _readMany([vdOption, renderOption]);
        if (actualPair[0] != expectedPair[0] ||
            actualPair[1] != expectedPair[1]) {
          throw StateError('Native DV probe pair changed during promotion');
        }
        await verifyDecoderlessProbe();
        await _write(item.key, item.value.requested,
            HdrNativeDvOptionDiagnosticPurpose.apply);
        expectedPair[pairIndex++] = item.value.requested;
        await verifyDecoderlessProbe();
      }
      final appliedPair = await _readMany([vdOption, renderOption]);
      await verifyDecoderlessProbe();
      if (appliedPair[0] != vd || appliedPair[1] != renderMode) {
        throw StateError('Native DV probe pair changed after promotion');
      }
    } catch (error, stack) {
      _emit(HdrNativeDvOptionDiagnosticPurpose.beginFailure,
          error: error, stack: stack);
      Error.throwWithStackTrace(error, stack);
    } finally {
      _busy = false;
    }
  }

  Future<void> verify() async {
    if (_busy || !active) {
      throw StateError('No settled native DV option transaction');
    }
    _busy = true;
    try {
      final entries = _pending.entries.toList();
      final values = await _readMany(entries.map((item) => item.key).toList());
      for (var i = 0; i < entries.length; i++) {
        if (values[i] != entries[i].value.requested) {
          throw StateError('Native DV owned option changed: ${entries[i].key}');
        }
      }
    } finally {
      _busy = false;
    }
  }

  Future<Map<String, Object>> _restore() async {
    final failures = <String, Object>{};
    if (_requiresStoppedRestore &&
        (_identity?.path.isNotEmpty == true ||
            _identity?.playlistEntryId.isNotEmpty == true)) {
      return {
        'sourceIdentity': StateError(
            'Promoted native DV requires its owned stop before restore')
      };
    }
    if (_requiresStoppedRestore) {
      try {
        await assertCurrent();
      } catch (error) {
        return {'sourceIdentity': error};
      }
    }
    for (final name in _pending.keys.toList().reversed) {
      try {
        final item = _pending[name]!;
        final actual = await _read(name);
        if (actual != item.original) {
          if (actual != item.requested) {
            throw StateError('Externally changed owned option $name');
          }
          await _write(
              name, item.original, HdrNativeDvOptionDiagnosticPurpose.restore);
        } else {
          _emit(HdrNativeDvOptionDiagnosticPurpose.restoreNoWrite,
              name: name,
              original: item.original,
              requested: item.original,
              observed: actual);
        }
        _pending.remove(name);
      } catch (error, stack) {
        _emit(HdrNativeDvOptionDiagnosticPurpose.restoreFailure,
            name: name,
            original: _pending[name]?.original,
            requested: _pending[name]?.original,
            error: error,
            stack: stack);
        failures[name] = error;
      }
    }
    if (_pending.isEmpty) {
      _identity = null;
      _requiresStoppedRestore = false;
      _diagnosticTransaction = null;
    }
    return failures;
  }

  Future<void> restore() async {
    if (_busy) throw StateError('Native DV option transaction is busy');
    _busy = true;
    try {
      final failures = await _restore();
      if (failures.isNotEmpty) {
        throw HdrNativeDvOptionFailure(null, failures);
      }
    } finally {
      _busy = false;
    }
  }
}
