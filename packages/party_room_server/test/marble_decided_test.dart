import 'package:party_room_server/party_room_server.dart';
import 'package:party_room_server/testing.dart';
import 'package:test/test.dart';

/// "결정" 과 "발표" 의 계약.
///
/// 결정(1등 골인 / 꼴찌 확정)은 즉시 알 수 있어야 한다 — 호스트가 이 순간부터
/// 빨리감기·클로즈업 해제를 건다. 발표는 전원 완주 뒤다 — 결정 프레임에
/// 남은 구슬을 지워 버리면 "부딪히더니 갑자기 1등" 으로 보인다(실기 피드백).
void main() {
  GameContext ctx(
    List<Player> players, {
    void Function(Map<String, dynamic>)? broadcast,
  }) => GameContext(
    players: () => players,
    broadcast: broadcast ?? (_) {},
    sendTo: (_, _) {},
    onGameEvent: (_, _) {},
  );

  List<Player> makePlayers(int n) => [
    for (var i = 0; i < n; i++)
      Player(sessionToken: 's$i', tag: 'T$i', nickname: 'p$i')
        ..link = RecordingLink(),
  ];

  test('1등 뽑기 — 1등 골인 즉시 결정되고, 발표는 완주 뒤에 온다', () {
    final players = makePlayers(6);
    Map<String, dynamic>? result;
    final c = ctx(
      players,
      broadcast: (m) {
        if (m['scene'] == 'marble_result') result = m;
      },
    );
    final game = MarbleGame()..start(c);
    game.launch(c);
    expect(game.decided, isFalse, reason: '출발 직후에는 미결정');

    // 실시간처럼 조금씩 흘린다.
    var t = 0.0;
    double? decidedAt;
    while (result == null && t < 300) {
      game.tick(c, 1 / 30);
      t += 1 / 30;
      if (decidedAt == null && game.decided) decidedAt = t;
      if (game.decided) {
        expect(game.world!.ranking, isNotEmpty, reason: '결정은 1등 골인과 함께 서야 한다');
      }
      // 결정됐다고 남은 구슬이 증발하면 안 된다 — 발표 전에는 판 위에 남는다.
      if (game.decided && result == null) {
        expect(game.finished, isFalse);
      }
    }

    expect(result, isNotNull, reason: '판이 끝나지 않았다');
    expect(decidedAt, isNotNull);
    expect(game.finished, isTrue);
    expect((result!['ranking'] as List).length, 6);
    expect((result!['winner'] as Map)['rank'], 1);
  });

  test('꼴찌 뽑기 — 하나 남는 순간 결정되고 그 구슬이 꼴찌로 발표된다', () {
    final players = makePlayers(5);
    Map<String, dynamic>? result;
    final c = ctx(
      players,
      broadcast: (m) {
        if (m['scene'] == 'marble_result') result = m;
      },
    );
    final game = MarbleGame()
      ..applyRules({'winnerRank': 'last'})
      ..start(c);
    game.launch(c);

    var t = 0.0;
    var sawDecided = false;
    while (result == null && t < 300) {
      game.tick(c, 1 / 30);
      t += 1 / 30;
      if (!sawDecided && game.decided && result == null) {
        sawDecided = true;
        expect(game.world!.remaining, lessThanOrEqualTo(1));
      }
    }

    expect(result, isNotNull);
    final ranking = result!['ranking'] as List;
    expect(ranking.length, 5);
    expect((result!['winner'] as Map)['rank'], 5, reason: '꼴찌가 당첨이어야 한다');
  });
}
