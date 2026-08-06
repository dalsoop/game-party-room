import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';

GameContext _ctx(List<Player> players) => GameContext(
  players: () => players,
  broadcast: (_) {},
  sendTo: (_, _) {},
  onGameEvent: (_, _) {},
);

void main() {
  group('GameRoster', () {
    test('연결된 참가자만 앉힌다', () {
      // channel 이 없으면 connected == false — 실제 소켓 없이 그 경로만 검사한다.
      final players = [
        Player(sessionToken: 's1', tag: 'A1B2', nickname: '지훈'),
        Player(sessionToken: 's2', tag: 'C3D4', nickname: '민서'),
      ];
      final roster = GameRoster()..seatConnected(_ctx(players));
      expect(roster.isEmpty, isTrue, reason: '아무도 연결 안 됨');
    });

    test('자기 자신을 뺀 대상 목록을 만든다', () {
      final roster = GameRoster()
        ..restore([
          {'session': 's1', 'nickname': '지훈'},
          {'session': 's2', 'nickname': '민서'},
          {'session': 's3', 'nickname': '성호'},
        ]);
      final others = roster.othersOf('s2');
      expect(others.length, 2);
      expect(others.any((o) => o['session'] == 's2'), isFalse);
    });

    test('세션으로 닉네임을 찾는다', () {
      final roster = GameRoster()
        ..restore([
          {'session': 's1', 'nickname': '지훈'},
        ]);
      expect(roster.nicknameOf('s1'), '지훈');
      expect(roster.nicknameOf('없음'), isNull);
      expect(roster.contains('s1'), isTrue);
      expect(roster.contains('없음'), isFalse);
    });

    test('저장·복구를 왕복한다', () {
      final roster = GameRoster()
        ..restore([
          {'session': 's1', 'nickname': '지훈'},
          {'session': 's2', 'nickname': '민서'},
        ]);
      final again = GameRoster()..restore(roster.toJson());
      expect(again.snapshot(), roster.snapshot());
    });

    test('복구 입력이 없으면 빈 명단이다', () {
      expect((GameRoster()..restore(null)).isEmpty, isTrue);
    });
  });
}
