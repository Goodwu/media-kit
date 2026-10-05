import 'dart:async';
import 'package:media_kit/media_kit.dart';

const androidPlaybackPerformanceDiagnosticProperties = <String>[
  'time-pos',
  'duration',
  'pause',
  'frame-drop-count',
  'decoder-frame-drop-count',
  'vo-delayed-frame-count',
  'video-params',
  'video-out-params',
  'vo-passes',
  'avsync',
  'container-fps',
  'mistimed-frame-count',
];

const androidPlaybackPerformanceDiagnosticMaxRows = 300;
const androidPlaybackPerformanceDiagnosticMaxRawErrors = 64;
const androidPlaybackPerformanceDiagnosticMaxErrorText = 2048;
const androidPlaybackPerformanceDiagnosticMaxPropertyText = 2048;

/// An explicitly driven, read-only sampler for an already-running Player.
/// It has no timer, persistence, Player lifecycle, or UI integration.
class AndroidPlaybackPerformanceDiagnostic {
  AndroidPlaybackPerformanceDiagnostic({
    required Player player,
    this.maxRows = 120,
  })  : _player = player,
        _started = Stopwatch()..start() {
    if (maxRows < 1 || maxRows > androidPlaybackPerformanceDiagnosticMaxRows) {
      throw RangeError.range(
          maxRows, 1, androidPlaybackPerformanceDiagnosticMaxRows, 'maxRows');
    }
  }

  final Player _player;
  final int maxRows;
  final Stopwatch _started;
  final List<Map<String, Object?>> _rows = [];
  final List<AndroidPlaybackPerformanceRawError> _rawErrors = [];
  bool _sampling = false;
  bool _rawErrorOverflow = false;
  int _rawErrorCount = 0;
  Future<AndroidPlaybackPerformanceSampleResult>? _active;

  List<Map<String, Object?>> get rows =>
      List.unmodifiable(_rows.map((row) => _freezeMap(row)));
  List<AndroidPlaybackPerformanceRawError> get rawErrors =>
      List.unmodifiable(_rawErrors);
  bool get rawErrorOverflow => _rawErrorOverflow;
  int get elapsedMicroseconds => _started.elapsedMicroseconds;

  /// Samples once. Concurrent calls are rejected immediately and never queued.
  /// The caller must bind the expected route identity from its own evidence.
  Future<AndroidPlaybackPerformanceSampleResult> sample({
    required String expectedSource,
    required int expectedFileLoadedEpoch,
    required String expectedVo,
    required String expectedHwdecCurrent,
  }) {
    if (_sampling) {
      return Future.value(AndroidPlaybackPerformanceSampleResult.rejected(
        reason: 'sample-already-in-progress',
      ));
    }
    if (_rows.length >= maxRows) {
      return Future.value(AndroidPlaybackPerformanceSampleResult.rejected(
        reason: 'row-capacity-reached',
      ));
    }
    _sampling = true;
    final future = _sampleUnderLock(
      expectedSource: expectedSource,
      expectedFileLoadedEpoch: expectedFileLoadedEpoch,
      expectedVo: expectedVo,
      expectedHwdecCurrent: expectedHwdecCurrent,
    );
    _active = future;
    return future.whenComplete(() {
      _sampling = false;
      _active = null;
    });
  }

  /// Waits for the current read, then returns a frozen snapshot. It does not
  /// stop future explicit samples or dispose the Player.
  Future<List<Map<String, Object?>>> drain() async {
    final active = _active;
    if (active != null) await active;
    return rows;
  }

  Future<AndroidPlaybackPerformanceSampleResult> _sampleUnderLock({
    required String expectedSource,
    required int expectedFileLoadedEpoch,
    required String expectedVo,
    required String expectedHwdecCurrent,
  }) async {
    final rowNumber = _rows.length + 1;
    final startedMicros = _started.elapsedMicroseconds;
    try {
      final result = await _player.lock.synchronized(() async {
        final before = await _readIdentity(rowNumber, 'before');
        if (before.error != null) {
          return AndroidPlaybackPerformanceSampleResult.rejected(
            reason: 'identity-read-failed-before',
            identityBefore: before.values,
            rawErrors: [before.error!],
          );
        }
        if (before.oversizedProperty != null) {
          return AndroidPlaybackPerformanceSampleResult.rejected(
            reason: 'identity-property-too-large:${before.oversizedProperty}',
            identityBefore: before.values,
          );
        }
        final mismatches = _identityMismatches(
          before,
          expectedSource: expectedSource,
          expectedFileLoadedEpoch: expectedFileLoadedEpoch,
          expectedVo: expectedVo,
          expectedHwdecCurrent: expectedHwdecCurrent,
        );
        if (mismatches.isNotEmpty) {
          return AndroidPlaybackPerformanceSampleResult.rejected(
            reason: 'identity-mismatch-before:${mismatches.join(',')}',
            identityBefore: before.values,
          );
        }

        final values = <String, Object?>{};
        final propertyErrors = <String, Object?>{};
        final propertyTruncation = <String, Object?>{};
        final callErrors = <AndroidPlaybackPerformanceRawError>[];
        for (final name in androidPlaybackPerformanceDiagnosticProperties) {
          try {
            final value = await _player.getProperty(
              name,
              waitForInitialization: false,
            );
            if (value.length >
                androidPlaybackPerformanceDiagnosticMaxPropertyText) {
              values[name] = value.substring(
                  0, androidPlaybackPerformanceDiagnosticMaxPropertyText);
              propertyTruncation[name] = {
                'truncated': true,
                'originalLength': value.length,
                'storedLength':
                    androidPlaybackPerformanceDiagnosticMaxPropertyText,
              };
            } else {
              values[name] = value;
            }
          } catch (error, stack) {
            final raw = _recordRawError(
              row: rowNumber,
              phase: 'sample-property',
              property: name,
              error: error,
              stackTrace: stack,
            );
            callErrors.add(raw);
            propertyErrors[name] = {
              'error': _boundedText(error),
              'stack': _boundedText(stack),
              'rawErrorIndex': raw.index,
            };
          }
        }

        final after = await _readIdentity(rowNumber, 'after');
        if (after.error != null) {
          return AndroidPlaybackPerformanceSampleResult.rejected(
            reason: 'identity-read-failed-after',
            identityBefore: before.values,
            identityAfter: after.values,
            rawErrors: [...callErrors, after.error!],
          );
        }
        if (after.oversizedProperty != null) {
          return AndroidPlaybackPerformanceSampleResult.rejected(
            reason: 'identity-property-too-large:${after.oversizedProperty}',
            identityBefore: before.values,
            identityAfter: after.values,
            rawErrors: callErrors,
          );
        }
        final drift = _identityDrift(before.rawValues, after.rawValues);
        final afterMismatches = _identityMismatches(
          after,
          expectedSource: expectedSource,
          expectedFileLoadedEpoch: expectedFileLoadedEpoch,
          expectedVo: expectedVo,
          expectedHwdecCurrent: expectedHwdecCurrent,
        );
        if (drift.isNotEmpty || afterMismatches.isNotEmpty) {
          return AndroidPlaybackPerformanceSampleResult.rejected(
            reason: [
              if (drift.isNotEmpty) 'identity-drift:${drift.join(',')}',
              if (afterMismatches.isNotEmpty)
                'identity-mismatch-after:${afterMismatches.join(',')}',
            ].join(';'),
            identityBefore: before.values,
            identityAfter: after.values,
            rawErrors: callErrors,
          );
        }

        final row = <String, Object?>{
          'sampleOrdinal': rowNumber,
          'hostElapsedMicros': _started.elapsedMicroseconds,
          'sampleReadElapsedMicros':
              _started.elapsedMicroseconds - startedMicros,
          'accepted': true,
          'identityBefore': before.values,
          'identityAfter': after.values,
          'properties': values,
          'propertyErrors': propertyErrors,
          'propertyTruncation': propertyTruncation,
        };
        _rows.add(_freezeMap(row));
        return AndroidPlaybackPerformanceSampleResult.accepted(
          row: _rows.last,
          rawErrors: callErrors,
        );
      });
      return result;
    } catch (error, stack) {
      final raw = _recordRawError(
        row: rowNumber,
        phase: 'sample-operation',
        error: error,
        stackTrace: stack,
      );
      return AndroidPlaybackPerformanceSampleResult.rejected(
        reason: 'sample-operation-failed',
        rawErrors: [raw],
      );
    }
  }

  Future<_IdentityRead> _readIdentity(int row, String phase) async {
    final epochBefore = _player.fileLoadedEpoch;
    final rawValues = <String, Object?>{};
    final values = <String, Object?>{};
    String? oversizedProperty;
    for (final name in const ['path', 'vo', 'hwdec-current']) {
      try {
        final value = await _player.getProperty(
          name,
          waitForInitialization: false,
        );
        rawValues[name] = value;
        if (value.length >
            androidPlaybackPerformanceDiagnosticMaxPropertyText) {
          oversizedProperty ??= name;
          values[name] = value.substring(
              0, androidPlaybackPerformanceDiagnosticMaxPropertyText);
          values['${name}Truncated'] = true;
          values['${name}OriginalLength'] = value.length;
        } else {
          values[name] = value;
        }
      } catch (error, stack) {
        final raw = _recordRawError(
          row: row,
          phase: 'identity-$phase',
          property: name,
          error: error,
          stackTrace: stack,
        );
        return _IdentityRead(values, rawValues, raw, oversizedProperty);
      }
    }
    final epochAfter = _player.fileLoadedEpoch;
    values['fileLoadedEpoch'] = epochBefore;
    values['fileLoadedEpochAfterProperties'] = epochAfter;
    rawValues['fileLoadedEpoch'] = epochBefore;
    rawValues['fileLoadedEpochAfterProperties'] = epochAfter;
    return _IdentityRead(values, rawValues, null, oversizedProperty);
  }

  List<String> _identityMismatches(
    _IdentityRead identity, {
    required String expectedSource,
    required int expectedFileLoadedEpoch,
    required String expectedVo,
    required String expectedHwdecCurrent,
  }) {
    final values = identity.rawValues;
    final mismatches = <String>[];
    if (values['path'] != expectedSource) mismatches.add('path');
    if (values['fileLoadedEpoch'] != expectedFileLoadedEpoch) {
      mismatches.add('fileLoadedEpoch');
    }
    if (values['vo'] != expectedVo) mismatches.add('vo');
    if (values['hwdec-current'] != expectedHwdecCurrent) {
      mismatches.add('hwdec-current');
    }
    if (values['fileLoadedEpoch'] != values['fileLoadedEpochAfterProperties']) {
      mismatches.add('fileLoadedEpoch-drift-during-identity-read');
    }
    return mismatches;
  }

  List<String> _identityDrift(
      Map<String, Object?> before, Map<String, Object?> after) {
    return [
      for (final key in const [
        'path',
        'fileLoadedEpoch',
        'fileLoadedEpochAfterProperties',
        'vo',
        'hwdec-current',
      ])
        if (before[key] != after[key]) key,
    ];
  }

  AndroidPlaybackPerformanceRawError _recordRawError({
    required int row,
    required String phase,
    required Object error,
    StackTrace? stackTrace,
    String? property,
  }) {
    final record = AndroidPlaybackPerformanceRawError(
      index: _rawErrorCount++,
      row: row,
      phase: phase,
      property: property,
      error: error,
      stackTrace: stackTrace,
    );
    if (_rawErrors.length < androidPlaybackPerformanceDiagnosticMaxRawErrors) {
      _rawErrors.add(record);
    } else {
      _rawErrorOverflow = true;
    }
    return record;
  }
}

class AndroidPlaybackPerformanceSampleResult {
  AndroidPlaybackPerformanceSampleResult._({
    required this.accepted,
    required this.reason,
    required this.row,
    required this.identityBefore,
    required this.identityAfter,
    required this.rawErrors,
  });

  factory AndroidPlaybackPerformanceSampleResult.accepted({
    required Map<String, Object?> row,
    List<AndroidPlaybackPerformanceRawError> rawErrors = const [],
  }) =>
      AndroidPlaybackPerformanceSampleResult._(
        accepted: true,
        reason: null,
        row: row,
        identityBefore: null,
        identityAfter: null,
        rawErrors: List.unmodifiable(rawErrors),
      );

  factory AndroidPlaybackPerformanceSampleResult.rejected({
    required String reason,
    Map<String, Object?>? identityBefore,
    Map<String, Object?>? identityAfter,
    List<AndroidPlaybackPerformanceRawError> rawErrors = const [],
  }) =>
      AndroidPlaybackPerformanceSampleResult._(
        accepted: false,
        reason: reason,
        row: null,
        identityBefore:
            identityBefore == null ? null : _freezeMap(identityBefore),
        identityAfter: identityAfter == null ? null : _freezeMap(identityAfter),
        rawErrors: List.unmodifiable(rawErrors),
      );

  final bool accepted;
  final String? reason;
  final Map<String, Object?>? row;
  final Map<String, Object?>? identityBefore;
  final Map<String, Object?>? identityAfter;
  final List<AndroidPlaybackPerformanceRawError> rawErrors;
}

class AndroidPlaybackPerformanceRawError {
  const AndroidPlaybackPerformanceRawError({
    required this.index,
    required this.row,
    required this.phase,
    required this.error,
    this.property,
    this.stackTrace,
  });

  final int index;
  final int row;
  final String phase;
  final String? property;
  final Object error;
  final StackTrace? stackTrace;
}

class _IdentityRead {
  const _IdentityRead(
      this.values, this.rawValues, this.error, this.oversizedProperty);
  final Map<String, Object?> values;
  final Map<String, Object?> rawValues;
  final AndroidPlaybackPerformanceRawError? error;
  final String? oversizedProperty;
}

String _boundedText(Object value) {
  final text = value.toString();
  return text.length <= androidPlaybackPerformanceDiagnosticMaxErrorText
      ? text
      : text.substring(0, androidPlaybackPerformanceDiagnosticMaxErrorText);
}

Map<String, Object?> _freezeMap(Map<String, Object?> input) {
  Object? freeze(Object? value) {
    if (value is Map) {
      return Map.unmodifiable(
          value.map((key, value) => MapEntry(key, freeze(value))));
    }
    if (value is List) return List.unmodifiable(value.map(freeze));
    return value;
  }

  return Map.unmodifiable(
      input.map((key, value) => MapEntry(key, freeze(value))));
}
