import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/server/control_service.dart';

/// 제어 표면의 계약.
///
/// 이 앱의 호스트 화면은 오래도록 자동화로 검증되지 못했다 — 판을 시작하거나
/// 상태를 볼 길이 화면 버튼뿐이라, 에이전트는 스크린샷을 찍고 좌표를 눌러야
/// 했고 창이 다른 Space 에 있으면 캡처조차 못 했다. 그 구멍을 메우는 표면이라
/// **오류의 종류를 정확히 갈라야** 한다: CLI 의 exit code 가 이 구분을 그대로
/// 쓴다(64 사용법 · 1 실행 실패).
void main() {
  group('오류 종류', () {
    test('사용법 오류와 실행 실패는 다른 타입이다', () {
      // 같은 타입으로 뭉뚱그리면 스크립트가 "내가 틀렸나 상황이 안 됐나" 를
      // 구분하지 못해 무한 재시도에 빠진다.
      expect(ControlUsageError('x'), isNot(isA<ControlFailure>()));
      expect(ControlFailure('x'), isNot(isA<ControlUsageError>()));
    });

    test('메시지가 사람 말이다', () {
      expect(ControlUsageError('모르는 명령: zzz').toString(), contains('zzz'));
      expect(ControlFailure('4명 필요').toString(), contains('4명'));
    });
  });

  group('액션 목록', () {
    // 예전에는 이 목록이 각 throw 문의 문자열로만 있어서, 밖에서는 틀리게
    // 불러 봐야 알 수 있었다 — 실제로 `marble run`·`ladder reveal` 로 두 번
    // 헛짚었다. 이제 표가 정본이고 안내 문구가 거기서 나온다.
    test('실제로 쓰는 액션이 표에 있다', () {
      // 굴린 순서 그대로. 이 이름이 바뀌면 손에 익은 명령이 죽는다.
      expect(ControlService.actions['marble'], contains('launch'));
      expect(ControlService.actions['ladder'], contains('next'));
      expect(ControlService.actions['mafia'], containsAll(['night', 'vote']));
      expect(ControlService.actions['liar'], contains('vote'));
      expect(ControlService.actions['room'], containsAll(['new', 'pin']));
    });

    test('자물쇠를 거는 명령은 값 없이는 안 돈다', () {
      // 실제로 당한 자리: `room pin --pin 4907` 로 불렀더니 CLI 가 모르는
      // 플래그를 값째로 버렸고, 빈 값이 "해제" 로 읽혀서 **자물쇠를 풀고**
      // ok 를 돌려줬다. 호스트는 잠갔다고 믿고, 링크를 주운 사람은 들어온다.
      expect(
        () => ControlService.readPinArg(null),
        throwsA(isA<ControlUsageError>()),
      );
      expect(
        () => ControlService.readPinArg(''),
        throwsA(isA<ControlUsageError>()),
      );
      expect(
        () => ControlService.readPinArg('  '),
        throwsA(isA<ControlUsageError>()),
      );

      // 해제는 적어야만 된다.
      expect(ControlService.readPinArg('off'), isNull);
      expect(ControlService.readPinArg('4907'), '4907');
      expect(ControlService.readPinArg(' 4907 '), '4907');
    });

    test('빈 목록이나 중복은 없다', () {
      for (final e in ControlService.actions.entries) {
        expect(e.value, isNotEmpty, reason: '${e.key} 에 액션이 하나도 없다');
        expect(
          e.value.toSet().length,
          e.value.length,
          reason: '${e.key} 에 같은 액션이 두 번 있다',
        );
      }
    });
  });

  group('상태 게시', () {
    late Directory dir;
    late StateMirror mirror;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('mirror');
      mirror = StateMirror(overrideDir: dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('게시한 내용을 그대로 읽을 수 있다', () {
      mirror.publish({
        'schemaVersion': 1,
        'room': {'token': 'ABC123'},
      });
      final read = jsonDecode(mirror.file.readAsStringSync()) as Map;
      expect(read['schemaVersion'], 1);
      expect((read['room'] as Map)['token'], 'ABC123');
    });

    test('반쯤 쓰인 파일이 보이지 않는다', () {
      // 에이전트가 읽는 순간과 쓰는 순간이 겹친다 — 통째로 갈아 끼워야 한다.
      mirror.publish({'n': 1});
      for (var i = 2; i < 40; i++) {
        mirror.publish({'n': i});
        final read = jsonDecode(mirror.file.readAsStringSync()) as Map;
        expect(read['n'], isA<int>(), reason: '깨진 JSON 이 보였다');
      }
      expect(dir.listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
    });

    test('제어 토큰은 한 번 만들면 유지된다', () {
      final a = mirror.ensureToken();
      expect(a.length, greaterThanOrEqualTo(24));
      expect(mirror.ensureToken(), a, reason: '매번 바뀌면 CLI 가 계속 튕긴다');
    });

    test('토큰 파일이 깨져 있으면 새로 만든다', () {
      mirror.ensureToken();
      mirror.tokenFile.writeAsStringSync('{ 깨짐');
      final t = mirror.ensureToken();
      expect(t.length, greaterThanOrEqualTo(24));
    });

    test('토큰은 남이 못 읽는다', () {
      mirror.ensureToken();
      final mode = mirror.tokenFile.statSync().modeString();
      // 이 토큰을 읽으면 방을 조종할 수 있다 — 소유자 말고는 못 읽어야 한다.
      // modeString() 은 rwxrwxrwx 9자: 0-2 소유자 · 3-5 그룹 · 6-8 그 밖.
      expect(mode.substring(3), '------', reason: '권한이 $mode 다');
    });
  });
}
