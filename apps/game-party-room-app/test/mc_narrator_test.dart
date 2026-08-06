import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/server/mc_narrator.dart';

/// 사회자 발화 순서.
///
/// LLM 응답은 몇 초씩 걸리고 게임 이벤트는 그보다 빨리 온다. 그냥 던지면
/// 대사가 뒤바뀌어 도착하고, 호출이 겹쳐 쌓이고, 끝난 판의 대사가 다음 판에
/// 떨어진다. 여기 있는 것이 그 세 가지에 대한 계약이다.
void main() {
  /// 응답 시각을 테스트가 직접 정하는 가짜 통로.
  ({
    Future<String?> Function(String, Map<String, dynamic>) narrate,
    Map<String, Completer<String?>> pending,
    List<String> asked,
  })
  fake() {
    final pending = <String, Completer<String?>>{};
    final asked = <String>[];
    return (
      narrate: (event, data) {
        asked.add(event);
        return (pending[event] = Completer<String?>()).future;
      },
      pending: pending,
      asked: asked,
    );
  }

  test('한 번에 하나만 부른다', () async {
    final f = fake();
    final n = McNarrator(() => f.narrate);
    n.speak('a', {});
    n.speak('b', {});
    n.speak('c', {});
    await Future.delayed(Duration.zero);

    expect(f.asked, ['a'], reason: '앞엣것이 도는 동안 새로 부르면 프로세스가 겹친다');
    expect(n.hasPending, isTrue);
  });

  test('밀린 것은 가장 최근 것만 이어서 돈다', () async {
    final f = fake();
    final lines = <String>[];
    final n = McNarrator(() => f.narrate)..onLine = lines.add;

    n.speak('a', {});
    n.speak('b', {}); // 이건 c 에 덮여야 한다
    n.speak('c', {});
    f.pending['a']!.complete('A');
    await Future.delayed(Duration.zero);

    expect(f.asked, ['a', 'c'], reason: '중간에 밀린 b 는 흘려보낸다');
    f.pending['c']!.complete('C');
    await Future.delayed(Duration.zero);
    expect(lines, ['A', 'C']);
  });

  test('순서가 뒤집히지 않는다', () async {
    // 밤(느림) → 낮(빠름) 이어도 "낮" 이 먼저 나오면 안 된다.
    final f = fake();
    final lines = <String>[];
    final n = McNarrator(() => f.narrate)..onLine = lines.add;

    n.speak('night', {});
    n.speak('day', {});
    // day 는 아직 불리지도 않았다 — night 가 끝나야 시작한다.
    expect(f.asked, ['night']);
    f.pending['night']!.complete('밤이 되었습니다');
    await Future.delayed(Duration.zero);
    f.pending['day']!.complete('낮이 밝았습니다');
    await Future.delayed(Duration.zero);

    expect(lines, ['밤이 되었습니다', '낮이 밝았습니다']);
  });

  test('판이 끝나면 돌고 있던 대사를 버린다', () async {
    final f = fake();
    final lines = <String>[];
    final n = McNarrator(() => f.narrate)..onLine = lines.add;

    n.speak('mafia_ended', {});
    n.reset(); // 호스트가 로비로 나갔다
    f.pending['mafia_ended']!.complete('마피아의 승리!');
    await Future.delayed(Duration.zero);

    expect(lines, isEmpty, reason: '이전 판 대사가 다음 판 단톡에 떨어진다');
  });

  test('판이 끝나면 대기 중이던 것도 안 돈다', () async {
    final f = fake();
    final n = McNarrator(() => f.narrate);
    n.speak('a', {});
    n.speak('b', {});
    n.reset();
    f.pending['a']!.complete('A');
    await Future.delayed(Duration.zero);
    expect(f.asked, ['a'], reason: 'reset 후에 대기분을 새로 부르면 안 된다');
  });

  test('사회자가 꺼져 있으면 아무것도 안 부른다', () {
    final n = McNarrator(() => null);
    n.speak('a', {});
    expect(n.busy, isFalse);
    expect(n.hasPending, isFalse);
  });

  test('통로가 터져도 다음 발화가 막히지 않는다', () async {
    var calls = 0;
    final n = McNarrator(
      () => (event, data) {
        calls++;
        if (calls == 1) return Future.error(StateError('CLI 폭발'));
        return Future.value('괜찮습니다');
      },
    );
    final lines = <String>[];
    n.onLine = lines.add;

    n.speak('a', {});
    await Future.delayed(Duration.zero);
    expect(n.busy, isFalse, reason: '실패가 자리를 물고 있으면 사회자가 영영 멈춘다');

    n.speak('b', {});
    await Future.delayed(Duration.zero);
    expect(lines, ['괜찮습니다']);
  });
}
