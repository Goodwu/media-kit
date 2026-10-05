import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:media_kit_video/media_kit_video.dart';

const androidHdr10DiagnosticSource = '/data/local/tmp/media-kit-lg-pq-4k30.mp4';
const androidHdr10DiagnosticSourceSha256 =
    '3068be37277a501588ce10dcf15ec5a4536ff0f57db0c25008465bbd3a80c990';
const androidHdr10DiagnosticMaxRows = 256;
const androidHdr10DiagnosticMaxText = 4096;
const androidHdr10DiagnosticSeconds = 120;
const androidHdr10RestoredProperties = <String>[
  'hwdec',
  'cache-on-disk',
  'target-prim',
  'target-trc',
  'target-colorspace-hint',
  'tone-mapping',
];
const androidHdr10DecoderProperties = <String>[
  'vo',
  'hwdec',
  'hwdec-current',
  'time-pos',
  'duration',
  'pause',
  'video-params',
  'video-out-params',
  'current-tracks/video/codec',
  'current-tracks/video/dolby-vision-profile',
  'android-mediacodec-info',
  'frame-drop-count',
  'decoder-frame-drop-count',
];

String? validateAndroidHdr10Diagnostic({
  required bool android,
  required bool transaction,
  required List<String> sources,
  required String label,
  required bool conflictingFlags,
}) {
  if (!android || !transaction) {
    return 'HDR10 journal requires Android Session transaction';
  }
  if (sources.length != 1 ||
      sources.single != androidHdr10DiagnosticSource ||
      label.trim().isEmpty) {
    return 'HDR10 journal requires the fixed PQ source and external identity label';
  }
  if (conflictingFlags) {
    return 'HDR10 journal conflicts with source/route/lifecycle probes';
  }
  return null;
}

Map<String, Object?>? androidHdr10RouteJson(HdrRoute? route) => route == null
    ? null
    : {
        'strategy': route.strategy.name,
        'presentation': route.presentation.name,
        'transfer': route.outputTransfer.name,
        'topology': route.topology.name,
        'vo': route.vo,
        'hwdec': route.hwdec,
        'targetPrim': route.targetPrim,
        'targetTrc': route.targetTrc,
        'surfaceTransfer': route.surfaceTransfer,
        'appliesDynamicMetadata': route.appliesDynamicMetadata,
        'stripDvRpu': route.stripDvRpu,
        'vdLavcOptions': route.vdLavcOptions,
        'mediacodecEmbedRenderMode': route.mediacodecEmbedRenderMode,
        'dependencies': route.dependencies.toList(),
      };

Map<String, Object?> androidHdr10ReportJson(HdrOutputReport report) {
  final source = report.source;
  final prediction = report.prediction;
  return {
    'generation': report.generation,
    'reportPhase': report.verified && report.sourceOrigin?.name == 'decoder'
        ? 'decoder-reviewed'
        : 'planning-or-unverified',
    'source': source == null
        ? null
        : {
            'codec': source.codec,
            'transfer': source.transfer,
            'primaries': source.primaries,
            'dynamicMetadata': source.dynamicMetadata.name,
            'dvProfile': source.dvProfile,
            'dvCompatibilityId': source.dvCompatibilityId,
            'enhancementLayer': source.enhancementLayer,
          },
    'sourceOrigin': report.sourceOrigin?.name,
    'prediction': prediction == null
        ? null
        : {
            'presentation': prediction.presentation.name,
            'confidence': prediction.confidence.name,
            'playable': prediction.playable,
            'selected': {
              'strategy': prediction.selected.strategy.name,
              'maturity': prediction.selected.maturity.name,
              'feasible': prediction.selected.feasible,
              'skipReason': prediction.selected.skipReason?.name,
              'route': androidHdr10RouteJson(prediction.selected.route)
            },
            'candidates': [
              for (final candidate in prediction.candidates)
                {
                  'strategy': candidate.strategy.name,
                  'maturity': candidate.maturity.name,
                  'feasible': candidate.feasible,
                  'skipReason': candidate.skipReason?.name,
                  'route': androidHdr10RouteJson(candidate.route),
                }
            ],
          },
    'actual': androidHdr10RouteJson(report.actual),
    'verified': report.verified,
    'hwdecCurrent': report.hwdecCurrent,
    'dataSpaceRequested': report.dataSpaceRequested,
    'dataSpacePath': report.dataSpacePath,
    'dataSpaceReadback': report.dataSpaceReadback,
    'degradeReason': report.degradeReason?.name,
    'diagnostic': report.diagnostic,
    'error': report.error?.toString(),
    'verificationScope':
        'Session decoder/configuration; panel-and-visible-output-unverified',
  };
}

/// Release-only lab journal. All native reads run in the existing Player lock.
/// It records observations; it never writes playback options or opens media.
class AndroidHdrSessionDiagnostic {
  AndroidHdrSessionDiagnostic({
    required this.label,
    required this.readProperty,
    required this.readEpoch,
    required this.readIdentity,
    required this.withPlayerLock,
    this.writeOverride,
  });

  final String label;
  final Future<String> Function(String name) readProperty;
  final int Function() readEpoch;
  final Future<Map<String, Object?>> Function() readIdentity;
  final Future<void> Function(Future<void> Function() work) withPlayerLock;
  final Future<void> Function(Map<String, Object?> payload)? writeOverride;
  final String runId = '${DateTime.now().toUtc().microsecondsSinceEpoch}-hdr10';
  final String startUtc = DateTime.now().toUtc().toIso8601String();
  final Stopwatch _clock = Stopwatch()..start();
  final List<Map<String, Object?>> _rows = [];
  final List<String> _errors = [];
  final List<String> _gaps = [];
  Map<String, String>? _baseline;
  Map<String, Object?>? _cleanup;
  Map<String, Object?>? _capabilities;
  Future<void> _writes = Future<void>.value();
  Future<void>? _sample;
  Future<void>? _finish;
  bool _closing = false;
  bool _closed = false;
  bool _terminated = false;
  bool _restored = false;
  bool _debt = false;
  bool _gapsOverflow = false;
  bool _finalWriteSucceeded = false;
  int? _boundEpoch;
  int? _boundGeneration;
  String? _boundEntry;
  String? _boundSessionOutputIdentity;
  String? _firstError;

  bool get samplingAllowed =>
      !_closing &&
      !_closed &&
      _clock.elapsed < const Duration(seconds: androidHdr10DiagnosticSeconds) &&
      _rows.length < androidHdr10DiagnosticMaxRows;
  bool get closed => _closed;
  bool get debt => _debt;

  void _gap(String value) {
    if (_gaps.contains(value)) return;
    if (_gaps.length < 64) {
      _gaps.add(value);
    } else {
      _gapsOverflow = true;
    }
  }

  Object? _bounded(Object? value, String field, [int depth = 0]) {
    if (depth > 8) {
      _gap('depth-limit:$field');
      return null;
    }
    if (value == null || value is bool || value is int) return value;
    if (value is double) return value.isFinite ? value : null;
    if (value is String) {
      if (value.length <= androidHdr10DiagnosticMaxText) return value;
      _gap('text-truncated:$field');
      return value.substring(0, androidHdr10DiagnosticMaxText);
    }
    if (value is Map) {
      if (value.length > 64) _gap('map-truncated:$field');
      return {
        for (final entry in value.entries.take(64))
          entry.key.toString():
              _bounded(entry.value, '$field.${entry.key}', depth + 1)
      };
    }
    if (value is List) {
      if (value.length > 64) _gap('list-truncated:$field');
      return [
        for (var i = 0; i < value.length && i < 64; i++)
          _bounded(value[i], '$field.$i', depth + 1)
      ];
    }
    return _bounded(value.toString(), field, depth);
  }

  String _errorText(Object error) {
    try {
      return error.toString();
    } catch (_) {
      return 'error-toString-unavailable';
    }
  }

  void recordError(Object error, [StackTrace? stack]) {
    final raw = '${_errorText(error)}${stack == null ? '' : '\n$stack'}';
    final text = _bounded(raw, 'error') as String;
    _firstError ??= text;
    if (_errors.length < 64) {
      _errors.add(text);
    } else {
      _gap('errors-overflow');
    }
  }

  void _record(String kind, Map<String, Object?> fields) {
    if (_closed) return;
    if (_rows.length >= androidHdr10DiagnosticMaxRows) {
      _gap('rows-overflow');
      return;
    }
    final row = _bounded({
      'index': _rows.length,
      'elapsedMs': _clock.elapsedMilliseconds,
      'kind': kind,
      ...fields
    }, 'row') as Map;
    if (kind == 'sample' && (_gaps.isNotEmpty || _gapsOverflow)) {
      row['accepted'] = false;
      row['nativeHdr10Configuration'] = false;
      row['rejection'] = 'journal-value-truncated-or-overflow';
    }
    _rows.add(Map<String, Object?>.from(row));
  }

  /// Preserve raw input/output format logs without inferring display output.
  void recordCodecFormatLog({
    required String prefix,
    required String level,
    required String text,
  }) {
    if (_closing || _closed) return;
    final input = text.contains('hdr10_config_input event=configure ');
    final output = text.contains('Output MediaFormat changed to');
    if (!input && !output) return;
    _record(input ? 'codec-input-format-log' : 'codec-output-format-log', {
      'prefix': prefix,
      'level': level,
      'text': text,
      'scope': input
          ? 'raw configure input/status log; CSD/SEI contents, decoder attempt, Surface and panel unverified'
          : 'native log text; input configure format and panel unverified',
    });
  }

  /// Retain each degradation before a later decoder report replaces its text.
  /// This is passive public Session evidence, not a playback failure verdict.
  void recordEvent(HdrOutputEvent event) {
    if (_closing || _closed || event is! HdrDegradedEvent) return;
    _record('session-degradation', {
      'generation': event.generation,
      'reason': event.reason.name,
      'diagnostic': event.diagnostic,
      'fromStrategy': event.from?.strategy.name,
      'toStrategy': event.to?.strategy.name,
      'scope': 'Session degradation notification; panel output unverified',
    });
  }

  void recordReport(HdrOutputReport report) {
    if (_closing || _closed) return;
    try {
      _record('session-report', androidHdr10ReportJson(report));
    } catch (error, stack) {
      recordError(error, stack);
      _gap('report-projection-failed');
    }
  }

  void recordCapabilities(HdrCapabilities capabilities) {
    _capabilities = {
      'sdkInt': capabilities.sdkInt,
      'displayHdrTypes': capabilities.displayHdrTypes?.toList(),
      'snapshotScope':
          'separate real HdrCapabilities.query; not Session private snapshot'
    };
  }

  Future<Map<String, String>> _readProperties(
      List<String> names, Map<String, Object?> errors) async {
    final values = <String, String>{};
    for (final name in names) {
      try {
        final raw = await readProperty(name);
        if (raw.length > androidHdr10DiagnosticMaxText) {
          _gap('property-truncated:$name');
        }
        values[name] = _bounded(raw, name) as String;
      } catch (error, stack) {
        errors[name] = {
          'error': _bounded(_errorText(error), name),
          'stack': _bounded(stack.toString(), '$name.stack')
        };
        // Missing optional decoder properties stay explicit, not a fatal open error.
        if (errors.length > 64) {
          _gap('property-errors-overflow');
          break;
        }
        if (stack.toString().isEmpty) _gap('property-stack-unavailable:$name');
      }
    }
    return values;
  }

  Future<void> captureBaseline() async {
    await withPlayerLock(() async {
      final errors = <String, Object?>{};
      final before = readEpoch();
      final path = await readProperty('path');
      final values =
          await _readProperties(androidHdr10RestoredProperties, errors);
      if (path.isNotEmpty ||
          before != readEpoch() ||
          errors.isNotEmpty ||
          values.values.any((v) => v.isEmpty) ||
          _gaps.isNotEmpty) {
        _record('baseline-rejected',
            {'path': path, 'errors': errors, 'values': values});
        throw StateError(
            'HDR10 requires a complete stable idle option baseline');
      }
      _baseline = Map<String, String>.unmodifiable(values);
      _record(
          'baseline', {'epoch': before, 'path': path, 'properties': values});
    });
    await writeNow();
  }

  Future<void> sample() {
    if (!samplingAllowed) return Future<void>.value();
    final current = _sample;
    if (current != null) return current;
    final attempt = _sampleOnce();
    _sample = attempt;
    return attempt.whenComplete(() {
      if (identical(_sample, attempt)) _sample = null;
    });
  }

  bool _boundOutputComplete(Map<String, Object?> identity) {
    final output = identity['boundOutput'];
    return identity['sessionIdentity'] is int &&
        identity['sessionInstanceId'] is String &&
        (identity['sessionInstanceId'] as String).isNotEmpty &&
        output is Map &&
        output['bound'] == true &&
        output['videoControllerIdentity'] is int &&
        output['platformControllerIdentity'] is int &&
        [
          for (final key in [
            'handle',
            'generation',
            'surfaceGeneration',
            'wid'
          ])
            output[key] is int && (output[key] as int) > 0
        ].every((v) => v) &&
        output['viewId'] is int &&
        (output['viewId'] as int) >= 0;
  }

  Future<void> _sampleOnce() async {
    await withPlayerLock(() async {
      final errors = <String, Object?>{};
      final epochBefore = readEpoch();
      final identityBefore = Map<String, Object?>.from(
          jsonDecode(jsonEncode(await readIdentity())) as Map);
      final before = await _readProperties(['path', 'playlist/0/id'], errors);
      final properties =
          await _readProperties(androidHdr10DecoderProperties, errors);
      final after = await _readProperties(['path', 'playlist/0/id'], errors);
      final identityAfter = await readIdentity();
      final epochAfter = readEpoch();
      final generation = identityBefore['sessionGeneration'];
      final stable = before['path'] == androidHdr10DiagnosticSource &&
          before['path'] == after['path'] &&
          before['playlist/0/id'] != null &&
          before['playlist/0/id']!.isNotEmpty &&
          before['playlist/0/id'] == after['playlist/0/id'] &&
          epochBefore == epochAfter &&
          generation is int &&
          generation > 0 &&
          jsonEncode(identityBefore) == jsonEncode(identityAfter) &&
          _boundOutputComplete(identityBefore) &&
          _boundOutputComplete(identityAfter) &&
          !errors.containsKey('path') &&
          !errors.containsKey('playlist/0/id');
      final sessionOutputIdentity = jsonEncode({
        'sessionIdentity': identityBefore['sessionIdentity'],
        'sessionInstanceId': identityBefore['sessionInstanceId'],
        'boundOutput': identityBefore['boundOutput'],
      });
      final segmentMatches = _boundEpoch == null ||
          (_boundEpoch == epochBefore &&
              _boundGeneration == generation &&
              _boundEntry == before['playlist/0/id'] &&
              _boundSessionOutputIdentity == sessionOutputIdentity);
      final accepted =
          stable && segmentMatches && _gaps.isEmpty && !_gapsOverflow;
      if (accepted && _boundEpoch == null) {
        _boundEpoch = epochBefore;
        _boundGeneration = generation;
        _boundEntry = before['playlist/0/id'];
        _boundSessionOutputIdentity = sessionOutputIdentity;
      }
      final actual = identityBefore['actual'];
      final source = identityBefore['source'];
      final nativeConfiguration = accepted &&
          identityBefore['verified'] == true &&
          identityBefore['sourceOrigin'] == 'decoder' &&
          actual is Map &&
          source is Map &&
          source['transfer'] == 'pq' &&
          source['primaries'] == 'bt.2020' &&
          source['dvProfile'] == null &&
          source['dynamicMetadata'] == 'none' &&
          actual['strategy'] == 'baseLayerDirect' &&
          actual['presentation'] == 'nativeHdr' &&
          actual['transfer'] == 'pq' &&
          actual['topology'] == 'platformView' &&
          actual['vo'] == 'mediacodec_embed' &&
          actual['hwdec'] == 'mediacodec' &&
          properties['vo'] == 'mediacodec_embed' &&
          properties['hwdec-current'] == 'mediacodec';
      _record('sample', {
        'accepted': accepted,
        'nativeHdr10Configuration': nativeConfiguration,
        'rejection':
            accepted ? null : 'source-session-output-identity-drift-or-gap',
        'epochBefore': epochBefore,
        'epochAfter': epochAfter,
        'sourceBefore': before,
        'sourceAfter': after,
        'identityBefore': identityBefore,
        'identityAfter': identityAfter,
        'properties': properties,
        'propertyErrors': errors,
        'scope':
            'matching endpoints; continuous output and panel HDR unverified'
      });
    });
    await writeNow();
  }

  Future<void> writeNow({bool finalCandidate = false}) {
    final payload = snapshot();
    if (finalCandidate) payload['closed'] = true;
    final attempt = _writes.then((_) async {
      if (writeOverride != null) {
        await writeOverride!(payload);
        return;
      }
      final directory = Directory(
          '/storage/emulated/0/Android/data/com.example.media_kit_hdr_lab/files/media-kit-hdr-diagnostic');
      await directory.create(recursive: true);
      final text = jsonEncode(payload);
      final temporary = File('${directory.path}/hdr10-session-$runId.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename('${directory.path}/hdr10-session.json');
    });
    _writes =
        attempt.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      recordError(error, stack);
      _debt = true;
    });
    return attempt;
  }

  Future<void> finish({
    required Future<void> Function() disposeSession,
    required Map<String, Object?> Function() sessionCleanupFacts,
    required Future<void> Function() terminatePlayer,
  }) =>
      _finish ??= _finishOnce(
          disposeSession: disposeSession,
          sessionCleanupFacts: sessionCleanupFacts,
          terminatePlayer: terminatePlayer);

  Future<void> _finishOnce({
    required Future<void> Function() disposeSession,
    required Map<String, Object?> Function() sessionCleanupFacts,
    required Future<void> Function() terminatePlayer,
  }) async {
    _closing = true;
    final pending = _sample;
    if (pending != null) {
      try {
        await pending;
      } catch (error, stack) {
        recordError(error, stack);
        _debt = true;
      }
    }
    await _writes;
    try {
      await disposeSession();
    } catch (error, stack) {
      recordError(error, stack);
      _debt = true;
    }
    try {
      await withPlayerLock(() async {
        final errors = <String, Object?>{};
        final before = readEpoch();
        final values =
            await _readProperties(androidHdr10RestoredProperties, errors);
        final facts = sessionCleanupFacts();
        final baseline = _baseline;
        final checks = {
          for (final name in androidHdr10RestoredProperties)
            name: baseline != null &&
                values[name] == baseline[name] &&
                !errors.containsKey(name)
        };
        _restored = errors.isEmpty &&
            before == readEpoch() &&
            checks.values.every((v) => v) &&
            facts['sessionReportClean'] == true &&
            facts['controllerRetired'] == true;
        _cleanup = {
          'session': facts,
          'properties': values,
          'propertyErrors': errors,
          'baseline': baseline,
          'checks': checks,
          'verified': _restored,
          'surfaceReleaseAcknowledgement': 'unverified'
        };
        if (!_restored) {
          _debt = true;
        }
        _record('session-cleanup', _cleanup!);
      });
    } catch (error, stack) {
      recordError(error, stack);
      _debt = true;
    }
    try {
      await terminatePlayer();
      _terminated = true;
    } catch (error, stack) {
      recordError(error, stack);
      _debt = true;
    }
    _record('player-termination', {'completed': _terminated});
    await writeNow(finalCandidate: true);
    _closed = true;
    _finalWriteSucceeded = true;
    if (_debt || !_restored || !_terminated) {
      throw StateError('HDR10 owned cleanup is incomplete');
    }
  }

  Map<String, Object?> snapshot() {
    final samples = _rows.where((r) {
      final properties = r['properties'];
      final identity = r['identityBefore'];
      return r['kind'] == 'sample' &&
          r['accepted'] == true &&
          properties is Map &&
          properties['pause'] == 'no' &&
          identity is Map &&
          identity['playing'] == true &&
          identity['completed'] == false &&
          identity['buffering'] == false;
    }).toList();
    double? position(Map<String, Object?> row) {
      final p = row['properties'];
      final value =
          p is Map ? double.tryParse(p['time-pos']?.toString() ?? '') : null;
      return value != null && value.isFinite && value >= 0 ? value : null;
    }

    final first = samples.isEmpty ? null : position(samples.first);
    final last = samples.isEmpty ? null : position(samples.last);
    final progress = first != null && last != null && last - first >= 10;
    return jsonDecode(jsonEncode({
      'schema': 1,
      'diagnosticMode': 'hdr10-session',
      'runId': runId,
      'startUtc': startUtc,
      'externalIdentityLabel': label,
      'durationLimitSeconds': androidHdr10DiagnosticSeconds,
      'elapsedMs': _clock.elapsedMilliseconds,
      'sourcePath': androidHdr10DiagnosticSource,
      'sourceExpectedSha256': androidHdr10DiagnosticSourceSha256,
      'sourceIdentityScope':
          'external byte-verified asset required; not hashed by journal',
      'capabilities': _capabilities,
      'closed': _closed,
      'debt': _debt,
      'error': _firstError,
      'errors': _errors,
      'evidenceGaps': _gaps,
      'evidenceGapsOverflow': _gapsOverflow,
      'finalWriteSucceededInProcess': _finalWriteSucceeded,
      'finalPersistenceScope':
          'closed journal requires external byte readback; not self-acknowledged',
      'sessionRestorationVerified': _restored,
      'playerTerminated': _terminated,
      'cleanup': _cleanup,
      'progressSupport': {
        'tenSecondsPositionAdvance': progress,
        'firstTimePos': first,
        'lastTimePos': last,
        'acceptedSampleCount': samples.length,
        'scope':
            'matching source/generation endpoints; visible output and smoothness unverified'
      },
      'rows': _rows,
    })) as Map<String, Object?>;
  }
}
