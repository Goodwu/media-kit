import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/src/compat/legacy_media_headers.dart';
import 'package:media_kit/src/compat/legacy_media_options.dart';

// Independent reader for the generated key/value byte-length syntax. Returning
// pairs rather than a map lets the tests reject duplicate native option keys.
List<(String, String)> pairs(String text) {
  final bytes = utf8.encode(text);
  var offset = 0;
  final result = <(String, String)>[];
  while (offset < bytes.length) {
    final equals = bytes.indexOf(61, offset);
    expect(equals, greaterThan(offset));
    final name = ascii.decode(bytes.sublist(offset, equals));
    expect(bytes[equals + 1], 37);
    final endLength = bytes.indexOf(37, equals + 2);
    final length = int.parse(ascii.decode(bytes.sublist(equals + 2, endLength)));
    offset = endLength + 1;
    final value = utf8.decode(bytes.sublist(offset, offset + length));
    offset += length;
    result.add((name, value));
    if (offset < bytes.length) expect(bytes[offset++], 44);
  }
  return result;
}

void main() {
  test('headers are normalized, frozen and not kept by URI', () {
    final input = {'X-Entry': 'A'};
    final a = LegacyMediaOptions.fromExtras(null, httpHeaders: input);
    input['X-Entry'] = 'B';
    final b = LegacyMediaOptions.fromExtras(null, httpHeaders: input);
    expect(a.httpHeaders, {'x-entry': 'A'});
    expect(b.httpHeaders, {'x-entry': 'B'});
    expect(() => a.httpHeaders['x-entry'] = 'C', throwsUnsupportedError);
    expect(a.appendArguments('same://source', apiVersion: 0x20003),
        isNot(b.appendArguments('same://source', apiVersion: 0x20003)));
  });

  test('captured defaults cannot be changed by a later setter', () {
    final defaults = LegacyMediaHeaders()..update(userAgent: 'before',
        headers: {'X-Default': 'first'});
    final captured = LegacyMediaOptions.fromExtras(null,
        httpHeaders: defaults.resolve({'USER-AGENT': 'media'}));
    defaults.update(userAgent: 'after', headers: {'X-Default': 'second'});
    expect(captured.httpHeaders, {'user-agent': 'media', 'x-default': 'first'});
  });

  test('one header block preserves comma, percent, UTF-8 and trailing slash', () {
    final headers = {'X-Test': 'one,two=3%[四]', 'X-Tail': 'ends\\'};
    final options = LegacyMediaOptions.fromExtras(null, httpHeaders: headers);
    expect(pairs(options.encoded), [
      ('http-header-fields', 'x-test: one\\,two=3%[四]\r\nx-tail: ends\\'),
    ]);
  });

  test('multiple trailing backslashes never escape a field separator', () {
    final options = LegacyMediaOptions.fromExtras(null, httpHeaders: {
      'X-First': 'first\\', 'X-Middle': r'part\,tail', 'X-Last': 'last\\',
    });
    final nativePairs = pairs(options.encoded);
    expect(nativePairs.map((entry) => entry.$1).toSet().length,
        nativePairs.length);
    expect(nativePairs.single.$2.replaceAll(r'\,', ','),
        'x-first: first\\\r\nx-middle: part\\,tail\r\nx-last: last\\');
  });

  test('header-looking delimiters cannot acquire VO or decoder options', () {
    final options = LegacyMediaOptions.fromExtras({'vo': 'null'},
        httpHeaders: {'X-Test': 'a,vo=null,hwdec=no'});
    expect(pairs(options.encoded), [
      ('http-header-fields', r'x-test: a\,vo=null\,hwdec=no'),
    ]);
  });

  test('absent or empty headers do not replace a configured native baseline', () {
    expect(LegacyMediaOptions.fromExtras(null).isEmpty, isTrue);
    expect(LegacyMediaOptions.fromExtras(null, httpHeaders: {}).encoded, '');
  });

  test('invalid headers fail before any load command can be created', () {
    for (final headers in [
      {'invalid name': 'value'}, {'X-Test': 'one\r\ntwo'},
      {'X-Test': 'one\u0000two'}, {'': 'value'},
    ]) {
      expect(() => LegacyMediaOptions.fromExtras(null, httpHeaders: headers),
          throwsArgumentError);
    }
  });

  test('start/end are per-entry fields, never arbitrary extras', () {
    final options = LegacyMediaOptions.fromExtras({'start': '900', 'end': '901'},
        start: const Duration(milliseconds: 1234),
        end: const Duration(milliseconds: 5678));
    expect(pairs(options.encoded), [('start', '1.234'), ('end', '5.678')]);
    expect(LegacyMediaOptions.fromExtras({'start': '900'}).isEmpty, isTrue);
  });

  test('zero and negative intervals retain existing millisecond semantics', () {
    final options = LegacyMediaOptions.fromExtras(null,
        start: Duration.zero, end: const Duration(milliseconds: -250));
    expect(pairs(options.encoded), [('start', '0.000'), ('end', '-0.250')]);
  });

  test('header-only and interval-only inputs get both client API layouts', () {
    for (final options in [
      LegacyMediaOptions.fromExtras(null, httpHeaders: {'X': 'value'}),
      LegacyMediaOptions.fromExtras(null, start: Duration.zero),
    ]) {
      expect(options.isEmpty, isFalse);
      expect(options.appendArguments('edl://opaque', apiVersion: 0x20002),
          ['loadfile', 'edl://opaque', 'append', options.encoded]);
      expect(options.appendArguments('edl://opaque', apiVersion: 0x20003),
          ['loadfile', 'edl://opaque', 'append', '-1', options.encoded]);
    }
  });
}
