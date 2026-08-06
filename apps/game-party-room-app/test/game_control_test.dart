import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/games/game_control.dart';
import 'package:game_party_room_app/settings/host_settings.dart';
import 'package:party_room_server/party_room_server.dart';
import 'package:party_room_server/testing.dart';

/// 판을 시작하고 굴리고 끝내는 일 — **호스트 없이** 시험한다.
///
/// `HostController` 에서 떼어 낸 이유가 이거였다. 그쪽은 서버를 띄우고
/// 포트를 잡고 바깥 주소까지 찔러 보므로, 판 진행 하나를 확인하려고
/// 그걸 다 세울 수는 없다.
void main() {
  /// 방과 [GameControl] 을 세우고, 화면이 몇 번 깨졌는지 세어 준다.
  ({GameControl games, Room room, int Function() wakes}) rig({int people = 5}) {
    final room = Room();
    for (var i = 0; i < people; i++) {
      room.seat('손님$i')!.link = RecordingLink();
    }
    var wakes = 0;
    var ended = 0;
    final games = GameControl(
      room: () => room,
      settings: () => HostSettings.empty(),
      changed: () => wakes++,
      onEnded: () => ended++,
    );
    addTearDown(games.dispose);
    return (games: games, room: room, wakes: () => wakes);
  }

  group('시작 조건', () {
    test('사람이 모자라면 시작하지 않는다', () {
      final r = rig(people: 2);
      expect(r.games.startMafia(), isFalse, reason: '마피아는 4명부터다');
      expect(r.room.activeGame, isNull, reason: '거절했는데 판이 열렸다');
    });

    test('충분하면 시작하고 화면을 깨운다', () {
      final r = rig();
      final before = r.wakes();
      expect(r.games.startMafia(), isTrue);
      expect(r.room.activeGame, isA<MafiaGame>());
      expect(r.wakes(), greaterThan(before), reason: '판이 열렸는데 화면이 그대로다');
    });

    test('접속자 수는 방에서 읽는다', () {
      final r = rig(people: 3);
      expect(r.games.connectedCount, 3);
      r.room.players.first.link = null;
      expect(r.games.connectedCount, 2, reason: '끊긴 사람을 세면 시작 조건이 틀어진다');
    });
  });

  group('보고 있는 방을 따라간다', () {
    test('방이 바뀌면 새 방의 판을 조작한다', () {
      // 방을 값으로 넘겼다면 만든 시점의 방에 얼어붙어, 옆 방 판을
      // 조작하게 된다 — 다방에서 조용히 틀리는 종류다.
      var current = Room();
      for (var i = 0; i < 5; i++) {
        current.seat('가$i')!.link = RecordingLink();
      }
      final first = current;
      final games = GameControl(
        room: () => current,
        settings: () => HostSettings.empty(),
        changed: () {},
        onEnded: () {},
      );
      addTearDown(games.dispose);

      final second = Room();
      for (var i = 0; i < 5; i++) {
        second.seat('나$i')!.link = RecordingLink();
      }
      current = second;

      expect(games.startMafia(), isTrue);
      expect(second.activeGame, isA<MafiaGame>(), reason: '새 방에 안 열렸다');
      expect(first.activeGame, isNull, reason: '옛 방에 열렸다');
    });

    test('판 종류 게터도 보고 있는 방을 본다', () {
      final r = rig();
      expect(r.games.mafia, isNull);
      r.games.startMafia();
      expect(r.games.mafia, isNotNull);
      expect(r.games.liar, isNull, reason: '다른 종목으로 읽히면 화면이 엉뚱한 걸 그린다');
    });
  });

  group('끝내기', () {
    test('끝내면 방의 판이 사라지고 화면 상태도 지워진다', () {
      final r = rig();
      r.games.startMafia();
      r.games.mafiaPhase = 'night';
      r.games.gameStatus = '1일차 밤';

      r.games.endGame();
      expect(r.room.activeGame, isNull);
      expect(r.games.mafiaPhase, '');
      expect(r.games.gameStatus, '', reason: '끝난 판의 문구가 다음 판까지 남는다');
    });

    test('사다리 추적 도중에 끝내도 시계가 선다', () {
      final r = rig(people: 3);
      expect(r.games.startLadder(['꽝', '당첨', '꽝']), isTrue);
      r.games.traceNextLadder();
      expect(r.games.timedProgressRunning, isTrue);

      r.games.endGame();
      expect(
        r.games.timedProgressRunning,
        isFalse,
        reason: '판이 끝났는데 시계가 돌면 다음 판에 옛 연출이 끼어든다',
      );
      expect(r.games.ladderTracing, isNull);
    });

    test('비우기는 화면 상태만 되돌린다', () {
      final r = rig();
      r.games.gameStatus = '뭔가';
      r.games.mafiaRoles = {'가': '마피아'};
      r.games.resetState();
      expect(r.games.gameStatus, '');
      expect(r.games.mafiaRoles, isEmpty);
    });
  });

  group('구슬', () {
    test('출발시키면 시계가 돈다', () {
      final r = rig();
      expect(r.games.startMarble(), isTrue);
      expect(r.games.timedProgressRunning, isFalse, reason: '배정만 하고 아직 안 굴린다');
      r.games.launchMarble();
      expect(r.games.timedProgressRunning, isTrue);
    });

    test('건너뛰면 결과가 나오고 시계가 선다', () {
      final r = rig();
      r.games.startMarble();
      r.games.launchMarble();
      r.games.skipMarble();
      expect(r.games.marble!.finished, isTrue);
      expect(r.games.timedProgressRunning, isFalse);
    });
  });
}
