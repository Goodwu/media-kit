import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/hdr/android_mediacodec_configuration.dart';

void main() {
  Map<String, Object?> facts() => {
        'api': 1,
        'mime': 'video/dolby-vision',
        'codec': 'OMX.qcom.video.decoder.dolby-vision',
        'native-dv-active': true,
      };
  test('accepts configured DV and preserves configuration-only facts', () {
    final parsed = AndroidMediaCodecConfiguration.parse(jsonEncode(facts()));
    expect(parsed!.nativeDvActive, isTrue);
    expect(parsed.mime, 'video/dolby-vision');
    expect(parsed.codec, 'OMX.qcom.video.decoder.dolby-vision');
  });
  test('allows unknown codec name only for inactive configuration', () {
    final value = facts()
      ..['mime'] = 'video/avc'
      ..['codec'] = ''
      ..['native-dv-active'] = false;
    expect(
        AndroidMediaCodecConfiguration.parse(jsonEncode(value))!.nativeDvActive,
        isFalse);
  });
  test('rejects missing, unavailable and malformed responses', () {
    for (final raw in [null, '', 'ERROR', '{}', 'null', '[]', '1']) {
      expect(AndroidMediaCodecConfiguration.parse(raw), isNull);
    }
  });
  test('rejects unknown schemas and mistyped or contradictory fields', () {
    for (final entry in <String, List<Object?>>{
      'api': [null, 0, 2, 1.0, '1'],
      'mime': [null, '', 'audio/aac', 'video/', ' video/hevc', 'video/hevc'],
      'codec': [null, '', 1, ' codec '],
      'native-dv-active': [null, 1, 'true'],
    }.entries) {
      for (final value in entry.value) {
        final input = facts()..[entry.key] = value;
        expect(AndroidMediaCodecConfiguration.parse(jsonEncode(input)), isNull,
            reason: '${entry.key}: $value');
      }
    }
  });
}
