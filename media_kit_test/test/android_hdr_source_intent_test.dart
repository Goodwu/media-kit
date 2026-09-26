import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_test/common/sources/android_hdr_source_intent.dart';

void main() {
  test('older completion cannot replace a newer selected source', () {
    final intent = AndroidHdrSourceIntent<Object>();
    final a = intent.begin();
    final b = intent.begin();
    final bSession = Object();
    intent.succeed(b, 'B', bSession);
    intent.succeed(a, 'A', Object());
    expect(intent.source, 'B');
    expect(intent.session, same(bSession));
    expect(intent.pending, 0);
  });

  test('resume snapshot is invalid while a new choice is pending', () {
    final intent = AndroidHdrSourceIntent<Object>();
    final a = intent.begin();
    final aSession = Object();
    intent.succeed(a, 'A', aSession);
    final resume = intent.snapshot();
    expect(intent.mayResume(resume), isTrue);
    final b = intent.begin();
    expect(intent.mayResume(resume), isFalse);
    intent.fail(b);
    expect(intent.mayResume(resume), isFalse);
    expect(intent.source, isNull);
    expect(intent.session, isNull);
    expect(intent.mayResume(intent.snapshot()), isFalse);
  });

  test('automatic request cannot regain priority after manual choice', () {
    final intent = AndroidHdrSourceIntent<Object>();
    final automatic = intent.begin();
    final manual = intent.begin();
    intent.succeed(automatic, 'default', Object());
    expect(intent.source, isNull);
    final manualSession = Object();
    intent.succeed(manual, 'chosen', manualSession);
    expect(intent.source, 'chosen');
    expect(intent.session, same(manualSession));
  });
}
