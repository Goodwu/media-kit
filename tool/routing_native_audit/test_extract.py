import unittest
from run import block_end, extract_lookup, extract_selection


class ExtractionTest(unittest.TestCase):
    def test_nested_blocks_ignore_comment_and_literal_braces(self):
        block = '''{ if (x) { /* } */ f("{\\\"}"); } // }\n c = '}'; }'''
        self.assertEqual(block_end(block + ' trailing', 0), len(block))

    def test_unterminated_block_is_rejected(self):
        with self.assertRaises(ValueError):
            block_end('{ /* } */', 0)

    def test_function_extraction_is_exact(self):
        body = 'char *ff_AMediaCodecList_getCodecNameByType(int x) { return "}"; }'
        self.assertEqual(extract_selection('header\n' + body + '\nother'), body + '\n')

    def test_multiple_anchors_are_rejected(self):
        body = 'char *ff_AMediaCodecList_getCodecNameByType(int x) { return 0; }'
        with self.assertRaises(ValueError):
            extract_selection(body + '\n' + body)

    def test_lookup_includes_else_and_preserves_contents(self):
        body = 'if (format_profile == 0x20) { profile = 32; } else { profile = -1; }'
        self.assertEqual(extract_lookup('before\n' + body + '\nafter'), body + '\n')

    def test_changed_lookup_shape_requires_review(self):
        with self.assertRaises(ValueError):
            extract_lookup('if (format_profile == 0x20) { profile = 32; }')


if __name__ == '__main__':
    unittest.main()
