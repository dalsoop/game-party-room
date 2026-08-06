import 'dart:math';

import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';

/// 코스 선언.
///
/// 뽑기 도구라 **결과가 나와야** 하고 **같은 시드면 같아야** 한다. 코스를
/// 데이터로 뺀 이상, 새 코스를 적어 넣은 사람이 그 두 가지를 자기도 모르게
/// 깨뜨릴 수 있다 — 구슬이 끼는 구석 하나면 판이 영영 안 끝난다.
/// 그래서 선언된 코스 **전부**를 실제로 굴려 본다.
void main() {
  /// [n]명을 시드 [seed] 로 굴려 완주 시간(초)을 돌려준다. 안 끝나면 null.
  ({double seconds, List<String> order})? run(
    MarbleCourseSpec spec,
    int n,
    int seed, {
    double limit = 240,
  }) {
    final track = spec.build();
    final rng = Random(seed);
    final marbles = <Marble>[];
    for (var i = 0; i < n; i++) {
      final (x, y) = track.spawnPoint(i, rng);
      marbles.add(Marble(index: i, nickname: 'p$i', tag: 'T$i', x: x, y: y));
    }
    final w = MarbleWorld(track: track, marbles: marbles, seed: seed);
    var t = 0.0;
    while (!w.done && t < limit) {
      w.advance(1 / 60);
      t += 1 / 60;
    }
    if (!w.done) return null;
    return (seconds: t, order: [for (final m in w.ranking) m.tag]);
  }

  group('선언된 코스는 전부 끝까지 굴러간다', () {
    for (final spec in MarbleCourses.all) {
      test('${spec.id} — 인원·시드를 바꿔도 완주한다', () {
        var worst = 0.0;
        for (final n in [2, 8, 20]) {
          for (var seed = 0; seed < 12; seed++) {
            final r = run(spec, n, seed);
            expect(
              r,
              isNotNull,
              reason: '${spec.id}: $n명·시드 $seed 가 240초 안에 안 끝났다',
            );
            if (r!.seconds > worst) worst = r.seconds;
          }
        }
        // 손절선(runToCompletion 의 240초)에 여유가 있어야 복구도 재현된다.
        expect(
          worst,
          lessThan(120),
          reason: '${spec.id}: 최장 ${worst.toStringAsFixed(1)}초 — 너무 길다',
        );
      });
    }
  });

  group('같은 시드는 같은 결과', () {
    for (final spec in MarbleCourses.all) {
      test('${spec.id} — 두 번 굴려도 순위가 같다', () {
        for (var seed = 0; seed < 5; seed++) {
          final a = run(spec, 8, seed)!;
          final b = run(spec, 8, seed)!;
          expect(b.order, a.order, reason: '${spec.id}: 시드 $seed 가 흔들린다');
        }
      });
    }
  });

  test('코스가 다르면 결과도 다르다', () {
    // 같은 시드로 다른 코스를 굴렸는데 순위가 늘 같다면 코스 선택이
    // 실제로는 안 먹고 있다는 뜻이다.
    var different = 0;
    for (var seed = 0; seed < 8; seed++) {
      final a = run(MarbleCourses.classic, 8, seed)!;
      final b = run(MarbleCourses.sprint, 8, seed)!;
      if (a.order.join() != b.order.join()) different++;
    }
    expect(different, greaterThan(0));
  });

  group('코스 고르기', () {
    test('모르는 id 는 기본으로 떨어진다', () {
      expect(MarbleCourses.byId('그런코스없음').id, MarbleCourses.defaultId);
      expect(MarbleCourses.byId(null).id, MarbleCourses.defaultId);
    });

    test('규칙으로 코스를 고르고 저장·복구된다', () {
      final g = MarbleGame()..applyRules({'course': 'sprint'});
      expect(g.courseId, 'sprint');

      final restored = MarbleGame()
        ..restore(
          GameContext(
            players: () => const [],
            broadcast: (_) {},
            sendTo: (_, _) {},
            onGameEvent: (_, _) {},
          ),
          g.toJson(),
        );
      // 코스가 안 실리면 같은 시드라도 다른 순위가 나온다.
      expect(restored.courseId, 'sprint');
    });

    test('모르는 코스 규칙에 판이 안 열리지 않는다', () {
      final g = MarbleGame()..applyRules({'course': '오타'});
      expect(g.courseId, MarbleCourses.defaultId);
    });
  });

  group('선언이 실제 코스를 만든다', () {
    test('핀밭은 선언한 개수만큼 깔린다', () {
      const grid = PegGrid(
        rows: 3,
        cols: 4,
        x0: 2,
        y0: 10,
        dx: 2,
        dy: 3,
        stagger: 1,
      );
      expect(grid.build(), hasLength(12));
      // 벽을 파고들 칸은 빼둔다.
      const clipped = PegGrid(
        rows: 1,
        cols: 4,
        x0: 2,
        y0: 10,
        dx: 2,
        dy: 3,
        maxX: 5,
      );
      expect(clipped.build(), hasLength(2)); // 2, 4 만 남는다
    });

    test('벽 꼭짓점이 선분으로 이어진다', () {
      final t = MarbleCourses.classic.build();
      // 왼벽 13점 + 오른벽 13점 = 24선분, 여기에 경사판 2 + 범퍼 3.
      expect(t.segments.length, 24 + 2 + 3);
      expect(t.pegs.length, 2 + 33); // 낱개 2 + 핀밭(가장자리 2칸 제외)
      expect(t.spinners, hasLength(3));
    });

    test('출발 배치는 선언한 격자를 따른다', () {
      const spawn = SpawnSpec(
        x0: 10,
        y0: 2,
        perRow: 3,
        dx: 1,
        dy: 1,
        jitter: 0,
      );
      final rng = Random(1);
      expect(spawn.pointFor(0, rng), (10.0, 2.0));
      expect(spawn.pointFor(2, rng), (12.0, 2.0));
      expect(spawn.pointFor(3, rng), (10.0, 1.0)); // 다음 줄
    });
  });
}
