import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/pages/diagnostics_page.dart';
import 'package:game_party_room_app/server/diagnostics.dart';

void main() {
  late Directory dir;
  late Diagnostics diag;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('party-diag');
    diag = Diagnostics(overrideDir: dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('오류를 파일로 남긴다', () {
    diag.record(StateError('바퀴 빠짐'), StackTrace.current, context: 'marble');
    final text = diag.logFile.readAsStringSync();
    expect(text, contains('바퀴 빠짐'));
    expect(text, contains('marble'));
  });

  test('같은 오류가 쏟아져도 로그가 터지지 않는다', () {
    // 빌드 중 예외는 프레임마다 다시 난다 — 200번 나도 항목은 손에 꼽아야 한다.
    for (var i = 0; i < 200; i++) {
      diag.record(StateError('매 프레임'), null, context: 'build');
    }
    expect(diag.recent(limit: 100).length, lessThan(12));
    // 그래도 몇 번째 반복인지는 남아 있어야 진단이 된다.
    expect(diag.logFile.readAsStringSync(), contains('번째 반복'));
  });

  test('다른 오류는 접지 않는다', () {
    diag.record(StateError('가'), null);
    diag.record(StateError('나'), null);
    diag.record(StateError('다'), null);
    expect(diag.recent().length, 3);
  });

  test('파일이 무한정 자라지 않는다', () {
    final long = 'ㄱ' * 4000;
    for (var i = 0; i < 400; i++) {
      diag.record(StateError('$long $i'), null); // 매번 다른 서명 → 접히지 않음
    }
    expect(diag.logFile.lengthSync(), lessThan(512 * 1024));
    // 잘려도 최신 것은 살아 있어야 한다.
    expect(diag.logFile.readAsStringSync(), contains('399'));
  });

  test('최근 것이 위로 온다', () {
    diag.record(StateError('먼저'), null);
    diag.record(StateError('나중'), null);
    expect(diag.recent().first, contains('나중'));
  });

  test('기록이 없으면 빈 목록', () => expect(diag.recent(), isEmpty));

  testWidgets('기록이 없으면 안심시키는 화면', (t) async {
    await t.pumpWidget(MaterialApp(home: DiagnosticsPage(diagnostics: diag)));
    await t.pumpAndSettle();
    expect(find.text('기록된 오류가 없습니다'), findsOneWidget);
  });

  testWidgets('전송되지 않는다고 화면에서 밝힌다', (t) async {
    // 오류 기록을 조용히 어딘가로 보내는 앱이라는 의심을 남기지 않는다.
    diag.record(StateError('보여줄 것'), null);
    await t.pumpWidget(MaterialApp(home: DiagnosticsPage(diagnostics: diag)));
    await t.pumpAndSettle();
    expect(find.textContaining('전송되지 않습니다'), findsOneWidget);
    expect(find.textContaining('보여줄 것'), findsOneWidget);
  });
}
