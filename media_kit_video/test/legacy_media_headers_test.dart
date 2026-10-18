import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/src/compat/legacy_media_headers.dart';

void main() {
  test('custom headers replace and empty map clears custom Referer', () {
    final headers = LegacyMediaHeaders();
    headers.update(userAgent: 'ua', headers: {'Referer': 'first'});
    expect(headers.resolve(), {'user-agent': 'ua', 'referer': 'first'});
    headers.update(headers: {});
    expect(headers.resolve(), {'user-agent': 'ua'});
  });
  test('precedence is media > custom > named, case insensitive', () {
    final headers = LegacyMediaHeaders();
    headers.update(referer: 'named', headers: {'REFERER': 'custom'});
    expect(headers.resolve(), {'referer': 'custom'});
    expect(headers.resolve({'Referer': 'media'}), {'referer': 'media'});
    expect(headers.resolve(), {'referer': 'custom'});
  });
  test('maps are copied and observations cannot mutate defaults', () {
    final headers = LegacyMediaHeaders();
    final input = {'X-Test': 'one'};
    headers.update(headers: input);
    input['X-Test'] = 'two';
    expect(headers.resolve()['x-test'], 'one');
    expect(() => headers.resolve()['x-test'] = 'three', throwsUnsupportedError);
  });
  test('invalid update is atomic and invalid media does not change defaults', () {
    final headers = LegacyMediaHeaders();
    headers.update(userAgent: 'old', headers: {'Referer': 'old-ref'});
    for (final bad in [
      {'Bad:Name': 'value'}, {'X-Test': 'line\nbreak'}, {'': 'value'},
      {'X-Test': '\u0000'}, {'X-Test': 'line\rbreak'},
    ]) {
      expect(() => headers.update(userAgent: 'new', headers: bad), throwsArgumentError);
      expect(() => headers.resolve(bad), throwsArgumentError);
      expect(headers.resolve(), {'user-agent': 'old', 'referer': 'old-ref'});
    }
  });
}
