import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:media_kit_video/src/hdr/hdr_strategy.dart';

/// One expanded "source class × strategy → maturity" expectation parsed from
/// the requirement's status table.
class _Cell {
  const _Cell(this.cls, this.strategy, this.maturity);

  final HdrSourceClass cls;
  final HdrStrategy strategy;
  final HdrStrategyMaturity maturity;

  String get key => '${cls.name}|${strategy.name}';
}

/// Requirement section 6 source names → source classes. "任意 DV" expands to
/// every Dolby Vision family.
const Map<String, List<HdrSourceClass>> _sourceNames =
    <String, List<HdrSourceClass>>{
  'HDR10': <HdrSourceClass>[HdrSourceClass.hdr10],
  'HLG': <HdrSourceClass>[HdrSourceClass.hlg],
  'DV P5': <HdrSourceClass>[HdrSourceClass.dvP5],
  'DV P8.1': <HdrSourceClass>[HdrSourceClass.dvP81],
  'DV P8.2': <HdrSourceClass>[HdrSourceClass.dvP82],
  'DV P8.4': <HdrSourceClass>[HdrSourceClass.dvP84],
  'DV P8.1 / DV P8.2 / DV P8.4 / DV P7': <HdrSourceClass>[
    HdrSourceClass.dvP81,
    HdrSourceClass.dvP82,
    HdrSourceClass.dvP84,
    HdrSourceClass.dvP7,
  ],
  'DV P8.1 / DV P8.2 / DV P7': <HdrSourceClass>[
    HdrSourceClass.dvP81,
    HdrSourceClass.dvP82,
    HdrSourceClass.dvP7,
  ],
  'DV P7': <HdrSourceClass>[HdrSourceClass.dvP7],
  'DV P10': <HdrSourceClass>[HdrSourceClass.dvP10],
  'HDR Vivid': <HdrSourceClass>[HdrSourceClass.hdrVivid],
  '任意 DV': <HdrSourceClass>[
    HdrSourceClass.dvP5,
    HdrSourceClass.dvP81,
    HdrSourceClass.dvP82,
    HdrSourceClass.dvP84,
    HdrSourceClass.dvP7,
    HdrSourceClass.dvP10,
  ],
};

const Map<String, HdrStrategy> _strategyNames = <String, HdrStrategy>{
  'nativeDolbyVision': HdrStrategy.nativeDolbyVision,
  'baseLayerDirect': HdrStrategy.baseLayerDirect,
  'baseLayerConvert': HdrStrategy.baseLayerConvert,
  'metadataReshape': HdrStrategy.metadataReshape,
  'toneMapSdr': HdrStrategy.toneMapSdr,
  'sdrDirect': HdrStrategy.sdrDirect,
};

/// "全部" expands to the five concrete strategies; `nativeDolbyVision` is
/// covered by the dedicated per-class rows (DV P5 `verified` since the
/// 2026-10-10 promotion, DV P8.4 `experimental` since the 2026-10-06
/// unlock, the R7-reserved classes `unsupported`), which override the
/// "全部" rows of P8.2 and P10.
const List<HdrStrategy> _allStrategies = <HdrStrategy>[
  HdrStrategy.baseLayerDirect,
  HdrStrategy.baseLayerConvert,
  HdrStrategy.metadataReshape,
  HdrStrategy.toneMapSdr,
  HdrStrategy.sdrDirect,
];

const Map<String, HdrStrategyMaturity> _maturities =
    <String, HdrStrategyMaturity>{
  'verified': HdrStrategyMaturity.verified,
  'inherited': HdrStrategyMaturity.inherited,
  'experimental': HdrStrategyMaturity.experimental,
  'unsupported': HdrStrategyMaturity.unsupported,
};

/// Parses the markdown pipe table in section 6 of the requirement into
/// expanded maturity cells. Robust to surrounding prose: it only reads rows
/// of the table under the `## 6.` heading and ignores everything else.
List<_Cell> _parseSection6(List<String> lines) {
  final List<_Cell> cells = <_Cell>[];
  var inSection = false;
  for (final String raw in lines) {
    final String line = raw.trim();
    if (line.startsWith('## ')) {
      inSection = line.startsWith('## 6.');
      continue;
    }
    if (!inSection || !line.startsWith('|')) continue;
    var body = line.substring(1);
    if (body.endsWith('|')) body = body.substring(0, body.length - 1);
    final List<String> fields =
        body.split('|').map((String field) => field.trim()).toList();
    if (fields.length < 3) continue;
    final String sourceCell = fields[0];
    // Header and separator rows of the pipe table.
    if (sourceCell.isEmpty ||
        sourceCell == '源' ||
        sourceCell.contains('--')) {
      continue;
    }
    final List<HdrSourceClass>? classes = _sourceNames[sourceCell];
    expect(classes, isNotNull, reason: 'unmapped source cell: "$sourceCell"');
    final HdrStrategyMaturity? maturity = _maturities[fields[2]];
    expect(maturity, isNotNull, reason: 'unmapped maturity cell: "$line"');
    final List<HdrStrategy> strategies = <HdrStrategy>[];
    if (fields[1] == '全部') {
      strategies.addAll(_allStrategies);
    } else {
      for (final String token in fields[1].split('/')) {
        final HdrStrategy? strategy = _strategyNames[token.trim()];
        expect(strategy, isNotNull,
            reason: 'unmapped strategy cell: "$line"');
        strategies.add(strategy!);
      }
    }
    for (final HdrSourceClass cls in classes!) {
      for (final HdrStrategy strategy in strategies) {
        cells.add(_Cell(cls, strategy, maturity!));
      }
    }
  }
  return cells;
}

/// Locates the requirement document relative to the process working
/// directory (flutter test runs from the package root). The repository root
/// is one level up; the further candidates keep the test working if it is
/// ever run from a different checkout depth.
File _findRequirement() {
  const String relative = 'docs/requirements/android-hdr-auto-output.md';
  for (final String prefix in const <String>['../', '../../', './']) {
    final File candidate = File('$prefix$relative');
    if (candidate.existsSync()) return candidate;
  }
  return File('../$relative');
}

void main() {
  final File requirement = _findRequirement();

  group('HdrStrategyMaturityTable vs requirement section 6', () {
    test('every documented cell matches the constant table', () {
      expect(requirement.existsSync(), isTrue,
          reason: 'requirement document not found relative to the package '
              '(tried ../, ../../, ./ of docs/requirements/); maturity '
              'tests must run inside the media-kit checkout');
      final List<_Cell> cells = _parseSection6(requirement.readAsLinesSync());
      expect(cells.length, 33,
          reason: 'section 6 expands to 33 cells; when the requirement table '
              'changes, update the constant table and this count together');
      for (final _Cell cell in cells) {
        expect(
          HdrStrategyMaturityTable.of(cell.cls, cell.strategy),
          cell.maturity,
          reason: '${cell.cls.name} × ${cell.strategy.name}',
        );
      }
    });

    test('the constant table covers every class × strategy pair', () {
      for (final HdrSourceClass cls in HdrSourceClass.values) {
        for (final HdrStrategy strategy in HdrStrategy.values) {
          expect(
            () => HdrStrategyMaturityTable.of(cls, strategy),
            returnsNormally,
            reason: '${cls.name} × ${strategy.name} is missing from the table',
          );
        }
      }
    });

    test('undocumented cells keep the conservative default', () {
      expect(requirement.existsSync(), isTrue);
      final Set<String> documented =
          _parseSection6(requirement.readAsLinesSync())
              .map((_Cell cell) => cell.key)
              .toSet();
      for (final HdrSourceClass cls in HdrSourceClass.values) {
        for (final HdrStrategy strategy in HdrStrategy.values) {
          final String key = '${cls.name}|${strategy.name}';
          if (documented.contains(key)) continue;
          final HdrStrategyMaturity maturity =
              HdrStrategyMaturityTable.of(cls, strategy);
          final bool isDocumentedDefault =
              maturity == HdrStrategyMaturity.experimental ||
                  // R7: the reserved strategy is unsupported for every class.
                  (strategy == HdrStrategy.nativeDolbyVision &&
                      maturity == HdrStrategyMaturity.unsupported) ||
                  // The always-on SDR Texture baseline of every playback.
                  (cls == HdrSourceClass.sdr &&
                      strategy == HdrStrategy.sdrDirect &&
                      maturity == HdrStrategyMaturity.verified);
          expect(isDocumentedDefault, isTrue,
              reason: '$key = ${maturity.name} is neither documented in '
                  'section 6 nor one of the documented conservative defaults');
        }
      }
    });
  });
}
