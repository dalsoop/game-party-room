import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';

/// 사다리의 공정성과 섞임.
///
/// 뽑기 도구라 두 가지가 지켜져야 한다 —
/// 1. **당첨 확률이 모두 같다.** 이건 절대 조건이고, 결과 칸 셔플이 만든다.
/// 2. **선이 실제로 건너간다.** 확률이 맞아도 선이 직선으로 내려가면
///    참가자가 조작을 의심한다. 예전에는 행 수가 14로 고정이라 인원이
///    늘수록 나빠졌다.
void main() {
  final ctx = GameContext(
    players: () => const [],
    broadcast: (_) {},
    sendTo: (_, _) {},
    onGameEvent: (_, _) {},
  );

  /// 명단 n명·시드 seed 로 한 판 세운다. 소켓 없이 복구 경로를 쓴다.
  LadderGame game(int n, int seed, {List<String> outcomes = const ['당첨']}) =>
      LadderGame()..restore(ctx, {
        'rawOutcomes': outcomes,
        'seed': seed,
        'roster': [
          for (var i = 0; i < n; i++)
            {'session': 'S$i', 'tag': 'T$i', 'nickname': 'p$i'},
        ],
        'revealed': [],
        'ended': false,
      });

  group('당첨 확률은 모두 같다', () {
    for (final n in [4, 8, 20]) {
      test('$n명 — 어느 줄이든 1/n', () {
        const trials = 4000;
        final win = List<int>.filled(n, 0);
        for (var s = 0; s < trials; s++) {
          final g = game(n, s);
          for (var c = 0; c < n; c++) {
            if (g.outcomeOf(c) == '당첨') win[c]++;
          }
        }
        final ideal = trials / n;
        for (var c = 0; c < n; c++) {
          // 4000판이면 표준편차가 이상값의 ~4% 라, 20% 여유면 충분히 빡빡하다.
          expect(
            win[c] / ideal,
            closeTo(1.0, 0.2),
            reason: '$n명: $c번 줄의 당첨 확률이 ${(win[c] / ideal * 100).round()}%',
          );
        }
      });
    }
  });

  group('선이 실제로 건너간다', () {
    test('행 수가 인원에 따라 늘어난다', () {
      expect(Ladder.rowsFor(2), 14, reason: '적은 인원은 최소 행 수를 지킨다');
      expect(Ladder.rowsFor(8), 16);
      expect(Ladder.rowsFor(20), 40);
      expect(Ladder.rowsFor(100), 40, reason: '화면이 감당할 상한이 있어야 한다');
    });

    for (final (n, maxRatio) in [(8, 2.0), (12, 2.2), (20, 2.6)]) {
      test('$n명 — 제자리 확률이 이상값의 $maxRatio배 이내', () {
        const trials = 2000;
        var stay = 0;
        for (var s = 0; s < trials; s++) {
          final g = game(n, s);
          for (var c = 0; c < n; c++) {
            if (g.ladder!.endOf(c) == c) stay++;
          }
        }
        final ratio = (stay / trials / n) * n;
        expect(
          ratio,
          lessThan(maxRatio),
          reason:
              '$n명: 제자리가 이상값의 ${ratio.toStringAsFixed(1)}배 — '
              '선이 거의 직선으로 내려간다',
        );
      });
    }
  });

  group('사다리로서 성립한다', () {
    test('도착 칸이 겹치지 않는다', () {
      // 겹치면 누군가는 결과를 못 받는다 — 사다리가 아니라 고장이다.
      for (final n in [2, 3, 7, 13, 20]) {
        for (var s = 0; s < 300; s++) {
          final l = Ladder.generate(columns: n, seed: s);
          final ends = {for (var c = 0; c < n; c++) l.endOf(c)};
          expect(ends, hasLength(n), reason: '$n명 시드 $s 에서 도착이 겹쳤다');
        }
      }
    });

    test('추적 경로가 행마다 한 칸씩만 움직인다', () {
      final l = Ladder.generate(columns: 12, seed: 7);
      for (var c = 0; c < 12; c++) {
        final path = l.trace(c);
        expect(path, hasLength(l.rows + 1));
        for (var i = 1; i < path.length; i++) {
          expect((path[i] - path[i - 1]).abs(), lessThanOrEqualTo(1));
        }
        expect(path.last, l.endOf(c));
      }
    });
  });

  group('저장·복구', () {
    test('행 수 공식이 바뀌어도 이미 시작된 판은 그대로 되살아난다', () {
      // 참가자가 이미 본 결과가 앱 업데이트로 달라지면 안 된다.
      final saved = {
        'rawOutcomes': ['당첨'],
        'seed': 42,
        'rows': 14, // 옛 고정값으로 시작된 판
        'roster': [
          for (var i = 0; i < 20; i++)
            {'session': 'S$i', 'tag': 'T$i', 'nickname': 'p$i'},
        ],
        'revealed': <int>[],
        'ended': false,
      };
      final g = LadderGame()..restore(ctx, saved);
      expect(g.ladder!.rows, 14, reason: '저장된 행 수를 무시하고 새로 만들었다');

      // 같은 저장분을 두 번 되살려도 같아야 한다.
      final h = LadderGame()..restore(ctx, saved);
      expect(
        [for (var c = 0; c < 20; c++) g.outcomeOf(c)],
        [for (var c = 0; c < 20; c++) h.outcomeOf(c)],
      );
    });

    test('행 수가 없는 옛 저장분은 지금 공식으로 세운다', () {
      final g = LadderGame()
        ..restore(ctx, {
          'rawOutcomes': ['당첨'],
          'seed': 1,
          'roster': [
            for (var i = 0; i < 20; i++)
              {'session': 'S$i', 'tag': 'T$i', 'nickname': 'p$i'},
          ],
          'revealed': <int>[],
          'ended': false,
        });
      expect(g.ladder!.rows, Ladder.rowsFor(20));
    });
  });
}
