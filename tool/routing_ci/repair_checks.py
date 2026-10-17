#!/usr/bin/env python3
"""One-shot exact-anchor repairs for observed CI failures; no lint suppression.

The guarded workflow commits the repaired source before independent CI.
All anchors are validated before any file is written. Retained as evidence;
do not rerun after the generated fix commit has landed.
"""
from pathlib import Path
import argparse

GOLDEN_OLD = "        'primaries=bt.2020 meta=dolbyVision dv=8 compat=4 el=false',"
GOLDEN_NEW = "        'primaries=bt.2020 meta=dolbyVision dv=8 compat=4 el=unknown',"
UNUSED_THEME = '''/// [MaterialDesktopVideoControlsThemeData] available in this [context].
CupertinoVideoControlsThemeData _theme(BuildContext context) =>
    !isFullscreen(context)
        ? CupertinoVideoControlsTheme.maybeOf(context)?.normal ??
            kDefaultCupertinoVideoControlsThemeData
        : CupertinoVideoControlsTheme.maybeOf(context)?.fullscreen ??
            kDefaultCupertinoVideoControlsThemeDataFullscreen;

'''
NULL_TESTS = '''  test('a null release reply remains a failure and never acknowledges', () async {
    final channel = _FakeReleaseChannel(
      releaseReplies: [null],
      acknowledgeReplies: [true],
    );
    await expectLater(
      SurfaceReleaseProtocol(channel).release(_ownerA),
      throwsStateError,
    );
    expect(channel.releaseCalls, 1);
    expect(channel.acknowledgeCalls, 0);
  });

  test('a null acknowledgement fails rather than releasing the owner', () async {
    final channel = _FakeReleaseChannel(
      releaseReplies: ['released'],
      acknowledgeReplies: [null],
    );
    await expectLater(
      SurfaceReleaseProtocol(channel).release(_ownerA),
      throwsStateError,
    );
    expect(channel.releaseCalls, 1);
    expect(channel.acknowledgeCalls, 1);
  });

'''
EL_TEST = '''    test('explicit single-layer fact remains false in the diagnostic', () {
      enable();
      const HdrSourceClassifier().classify(
        videoParams: const VideoParams(gamma: 'hlg', primaries: 'bt.2020'),
        dolbyVisionProfile: 8,
        dvElPresent: false,
        hint: p84,
      );
      expect(lines.single, endsWith('dv=8 compat=4 el=false'));
    });

'''


def replace_once(text: str, old: str, new: str) -> str:
    count = text.count(old)
    if count != 1:
        raise ValueError(f'Expected one exact source anchor, got {count}: {old[:70]!r}')
    return text.replace(old, new, 1)


def repair(root: Path) -> list[str]:
    specs = {
        'media_kit_video/lib/media_kit_video_controls/src/controls/cupertino.dart': [(UNUSED_THEME, '')],
        'media_kit_video/lib/src/video_controller/android_video_controller/real.dart': [
            ('        _detachRetryTimers.containsKey(owner)) return;',
             '        _detachRetryTimers.containsKey(owner)) {\n      return;\n    }'),
            ('        _bindRetryTimers.containsKey(owner)) return;',
             '        _bindRetryTimers.containsKey(owner)) {\n      return;\n    }'),
        ],
        'media_kit_video/test/platform_surface_release_test.dart': [
            ('  final List<Object> releaseReplies;', '  final List<Object?> releaseReplies;'),
            ('  final List<Object> acknowledgeReplies;', '  final List<Object?> acknowledgeReplies;'),
            ('void main() {\n', 'void main() {\n' + NULL_TESTS),
        ],
        'media_kit_video/test/hdr_output_diagnostics_test.dart': [
            (GOLDEN_OLD, GOLDEN_NEW),
            ("    test('hint without facts keeps the hint origin', () {",
             EL_TEST + "    test('hint without facts keeps the hint origin', () {"),
        ],
    }
    pending = {}
    for name, edits in specs.items():
        text = (root / name).read_text(encoding='utf-8')
        for old, new in edits:
            text = replace_once(text, old, new)
        pending[name] = text
    for name, text in pending.items():
        (root / name).write_text(text, encoding='utf-8')
        print(name)
    return list(pending)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    repair(parser.parse_args().root.resolve())
