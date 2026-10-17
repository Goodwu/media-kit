from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from repair_checks import GOLDEN_NEW, GOLDEN_OLD, UNUSED_THEME, repair, replace_once


class RepairChecksTest(unittest.TestCase):
    def test_exact_replacement_preserves_surrounding_text(self):
        self.assertEqual(replace_once('prefix\nx\nsuffix', '\nx\n', '\ny\n'), 'prefix\ny\nsuffix')

    def test_missing_and_ambiguous_anchors_refuse(self):
        for text in ['', 'xx']:
            with self.assertRaises(ValueError):
                replace_once(text, 'x', 'y')

    def test_golden_changes_missing_el_only(self):
        self.assertEqual(replace_once(GOLDEN_OLD, GOLDEN_OLD, GOLDEN_NEW), GOLDEN_NEW)
        self.assertIn('el=unknown', GOLDEN_NEW)

    def test_failed_validation_does_not_write_earlier_files(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            name = 'media_kit_video/lib/media_kit_video_controls/src/controls/cupertino.dart'
            first = root / name
            first.parent.mkdir(parents=True)
            first.write_text(UNUSED_THEME + 'untouched\n')
            with self.assertRaises(FileNotFoundError):
                repair(root)
            self.assertEqual(first.read_text(), UNUSED_THEME + 'untouched\n')


if __name__ == '__main__':
    unittest.main()
