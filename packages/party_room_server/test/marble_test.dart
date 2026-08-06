import 'dart:math';

import 'package:party_room_server/party_room_server.dart';
import 'package:party_room_server/testing.dart';
import 'package:test/test.dart';

/// 구슬 룰렛의 계약.
///
/// 이 종목은 뽑기 도구로 쓰인다 — 벌칙자·순서를 정하는 데 쓰는 이상,
/// (1) 반드시 끝나야 하고 (2) 순위가 전원에게 하나씩 빠짐없이 붙어야 하며
/// (3) 같은 시드면 같은 결과가 나와야 한다. 셋 중 하나라도 깨지면 도구가 아니다.
GameContext _ctx(
  List<Player> players, {
  void Function(Map<String, dynamic>)? broadcast,
  void Function(String, Map<String, dynamic>)? sendTo,
}) => GameContext(
  players: () => players,
  broadcast: broadcast ?? (_) {},
  sendTo: sendTo ?? (_, _) {},
  onGameEvent: (_, _) {},
);

List<Player> _players(int n) => [
  for (var i = 0; i < n; i++)
    Player(
      sessionToken: 's$i',
      tag: 'T${i.toString().padLeft(3, '0')}',
      nickname: '참가자$i',
    )..link = RecordingLink(),
];

void main() {
  group('물리', () {
    test('구슬 20개가 전부 결승선에 들어온다', () {
      final track = MarbleTrack.standard();
      final rng = Random(42);
      final marbles = [
        for (var i = 0; i < 20; i++)
          () {
            final (x, y) = track.spawnPoint(i, rng);
            return Marble(index: i, nickname: 'p$i', tag: 't$i', x: x, y: y);
          }(),
      ];
      final world = MarbleWorld(track: track, marbles: marbles, seed: 42)
        ..runToCompletion();

      expect(world.done, isTrue, reason: '판이 끝나야 한다');
      final ranks = world.ranking.map((m) => m.rank).toList();
      expect(ranks, List.generate(20, (i) => i + 1), reason: '1위부터 빈틈없이');
    });

    test('구슬은 코스 밖으로 새지 않는다', () {
      final track = MarbleTrack.standard();
      final rng = Random(7);
      final marbles = [
        for (var i = 0; i < 12; i++)
          () {
            final (x, y) = track.spawnPoint(i, rng);
            return Marble(index: i, nickname: 'p$i', tag: 't$i', x: x, y: y);
          }(),
      ];
      final world = MarbleWorld(track: track, marbles: marbles, seed: 7);

      // 끝날 때까지 매 프레임 벽 밖으로 나갔는지 본다.
      var t = 0.0;
      while (!world.done && t < 240) {
        world.advance(1 / 60);
        t += 1 / 60;
        for (final m in world.marbles) {
          if (m.finished) continue;
          expect(
            m.x,
            inInclusiveRange(-m.radius, track.width + m.radius),
            reason: '벽을 통과했다',
          );
        }
      }
      expect(world.done, isTrue);
    });
  });

  group('게임 모듈', () {
    test('같은 시드는 같은 순위를 만든다', () {
      // 저장·복원이 "같은 시드로 다시 굴린다" 에 기대고 있다. 이게 깨지면
      // 앱을 껐다 켠 뒤 순위가 바뀐다.
      final players = _players(8);
      final saved = (MarbleGame()..start(_ctx(players))).toJson();

      List<String> replay() {
        final g = MarbleGame()..restore(_ctx(players), saved);
        g.skipToEnd(_ctx(players));
        return g.world!.ranking.map((m) => m.tag).toList();
      }

      final a = replay();
      expect(a.length, 8);
      expect(a.toSet().length, 8, reason: '중복 없이');
      expect(replay(), a, reason: '두 번 돌려도 같아야 한다');
    });

    test('저장·복원해도 순위가 같다', () {
      final players = _players(6);
      final game = MarbleGame()..start(_ctx(players));
      game.skipToEnd(_ctx(players));
      final first = game.world!.ranking.map((m) => m.tag).toList();

      final restored = MarbleGame()..restore(_ctx(players), game.toJson());
      expect(restored.finished, isTrue);
      expect(restored.world!.ranking.map((m) => m.tag).toList(), first);
    });

    test('꼴찌 뽑기로 두면 마지막 구슬이 당첨된다', () {
      final players = _players(5);
      Map<String, dynamic>? result;
      final ctx = _ctx(
        players,
        broadcast: (m) {
          if (m['scene'] == 'marble_result') result = m;
        },
      );
      final game = MarbleGame()
        ..applyRules({'winnerRank': 'last'})
        ..start(ctx);
      game.skipToEnd(ctx);

      expect(result, isNotNull);
      expect(result!['goal'], 'last');
      final ranking = result!['ranking'] as List;
      expect((result!['winner'] as Map)['rank'], (ranking.last as Map)['rank']);
    });

    test('참가자에게 자기 구슬만 알려준다', () {
      // 남의 번호까지 폰에 뿌리면 큰 화면 대신 폰만 본다.
      final players = _players(4);
      final sent = <String, Map<String, dynamic>>{};
      final game = MarbleGame()
        ..start(_ctx(players, sendTo: (s, m) => sent[s] = m));

      expect(sent.length, 4);
      for (final m in sent.values) {
        expect(m['scene'], 'marble_ready');
        expect(m.containsKey('ranking'), isFalse);
        expect(m['index'], isA<int>());
      }
      expect(
        sent.values.map((m) => m['index']).toSet().length,
        4,
        reason: '번호가 겹치면 안 된다',
      );
      expect(game.world!.marbles.length, 4);
    });

    test('연결되지 않은 참가자는 구슬을 받지 않는다', () {
      final players = _players(5);
      players[2].link = null;
      final game = MarbleGame()..start(_ctx(players));
      expect(game.world!.marbles.length, 4);
    });
  });
}
