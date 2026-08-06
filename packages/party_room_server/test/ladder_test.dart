import 'package:party_room_server/party_room_server.dart';
import 'package:party_room_server/testing.dart';
import 'package:test/test.dart';

/// 사다리타기의 계약.
///
/// 뽑기 도구인 이상 (1) 도착이 겹치면 안 되고(전단사) (2) 같은 시드는 같은
/// 사다리를 만들어야 하며 (3) 결과는 연출이 끝난 줄에만, 한 번씩만 나가야 한다.
void main() {
  GameContext ctx(
    List<Player> players, {
    void Function(Map<String, dynamic>)? broadcast,
    void Function(String, Map<String, dynamic>)? sendTo,
  }) => GameContext(
    players: () => players,
    broadcast: broadcast ?? (_) {},
    sendTo: sendTo ?? (_, _) {},
    onGameEvent: (_, _) {},
  );

  List<Player> makePlayers(int n) => [
    for (var i = 0; i < n; i++)
      Player(sessionToken: 's$i', tag: 'T$i', nickname: 'p$i')
        ..link = RecordingLink(),
  ];

  group('사다리 뼈대', () {
    test('도착 줄은 전단사다 — 어떤 인원에서도 겹치지 않는다', () {
      for (final n in [2, 3, 7, 20]) {
        for (var seed = 0; seed < 30; seed++) {
          final ladder = Ladder.generate(columns: n, seed: seed);
          final ends = {for (var i = 0; i < n; i++) ladder.endOf(i)};
          expect(ends.length, n, reason: '$n명 seed=$seed 에서 도착이 겹쳤다');
        }
      }
    });

    test('같은 행에서 이웃 가로대가 겹치지 않는다', () {
      for (var seed = 0; seed < 30; seed++) {
        final ladder = Ladder.generate(columns: 12, seed: seed);
        for (var row = 0; row < ladder.rows; row++) {
          for (var col = 0; col < 11; col++) {
            expect(
              ladder.rungAt(row, col) && ladder.rungAt(row, col + 1),
              isFalse,
              reason: 'row=$row col=$col 겹침 (seed=$seed)',
            );
          }
        }
      }
    });

    test('모든 이웃 쌍에 가로대가 최소 하나 있다 (섞임 보장)', () {
      for (var seed = 0; seed < 30; seed++) {
        final ladder = Ladder.generate(columns: 10, seed: seed);
        for (var col = 0; col < 9; col++) {
          final has = List.generate(
            ladder.rows,
            (r) => ladder.rungAt(r, col),
          ).any((v) => v);
          expect(has, isTrue, reason: '쌍 $col 에 가로대 없음 (seed=$seed)');
        }
      }
    });

    test('trace 는 한 칸씩만 움직인다', () {
      final ladder = Ladder.generate(columns: 8, seed: 5);
      for (var start = 0; start < 8; start++) {
        final path = ladder.trace(start);
        expect(path.length, ladder.rows + 1);
        for (var i = 1; i < path.length; i++) {
          expect((path[i] - path[i - 1]).abs(), lessThanOrEqualTo(1));
        }
      }
    });
  });

  group('게임 모듈', () {
    test('결과 칸이 인원만큼 채워지고, 비우면 당첨 1 + 꽝', () {
      final players = makePlayers(5);
      final game = LadderGame()..start(ctx(players));

      expect(game.outcomes.length, 5);
      expect(game.outcomes.where((o) => o == '당첨').length, 1);
      expect(game.outcomes.where((o) => o == '꽝').length, 4);
    });

    test('커스텀 결과는 그대로 쓰고 모자라면 꽝으로 채운다', () {
      final players = makePlayers(4);
      final game = LadderGame()
        ..setup(outcomes: ['벌칙', '아이스크림'])
        ..start(ctx(players));

      expect(game.outcomes.where((o) => o == '벌칙').length, 1);
      expect(game.outcomes.where((o) => o == '아이스크림').length, 1);
      expect(game.outcomes.where((o) => o == '꽝').length, 2);
    });

    test('reveal 은 그 줄에만 결과를 보내고, 전원 공개 시 전체 표를 발표한다', () {
      final players = makePlayers(3);
      final sent = <String, List<Map<String, dynamic>>>{};
      Map<String, dynamic>? endScene;
      final c = ctx(
        players,
        sendTo: (s, m) => sent.putIfAbsent(s, () => []).add(m),
        broadcast: (m) {
          if (m['scene'] == 'ladder_end') endScene = m;
        },
      );
      final game = LadderGame()..start(c);

      // 시작 시엔 전원 ready 만 받는다.
      for (final msgs in sent.values) {
        expect(msgs.single['scene'], 'ladder_ready');
      }

      game.reveal(c, 0);
      expect(endScene, isNull, reason: '전원 공개 전에 발표하면 안 된다');
      game.reveal(c, 0); // 중복 공개는 무시
      game.reveal(c, 1);
      game.reveal(c, 2);

      expect(endScene, isNotNull);
      final results = endScene!['results'] as List;
      expect(results.length, 3);
      // 결과 개인 전송은 줄마다 정확히 한 번.
      final resultCounts = [
        for (final msgs in sent.values)
          msgs.where((m) => m['scene'] == 'ladder_result').length,
      ];
      expect(resultCounts, [1, 1, 1]);
      expect(game.finished, isTrue);
    });

    test('저장·복원해도 같은 사다리·같은 결과다', () {
      final players = makePlayers(6);
      final c = ctx(players);
      final game = LadderGame()
        ..setup(outcomes: ['당첨', '벌칙'])
        ..start(c);
      final mapping = [for (var i = 0; i < 6; i++) game.outcomeOf(i)];
      game.reveal(c, 2);

      final restored = LadderGame()..restore(ctx(players), game.toJson());
      expect(
        [for (var i = 0; i < 6; i++) restored.outcomeOf(i)],
        mapping,
        reason: '복원 후 결과 배치가 달라지면 안 된다',
      );
      expect(restored.revealed, [2]);
      expect(
        [for (final s in restored.roster.seats) s.tag],
        [for (final s in game.roster.seats) s.tag],
        reason: '자리 배치도 그대로여야 한다',
      );
    });

    test('연결 안 된 참가자는 자리를 받지 않는다', () {
      final players = makePlayers(5);
      players[1].link = null;
      final game = LadderGame()..start(ctx(players));
      expect(game.roster.length, 4);
    });
  });
}
