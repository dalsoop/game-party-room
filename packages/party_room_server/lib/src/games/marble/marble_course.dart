import 'dart:math';

import 'marble_world.dart';

/// 코스 한 벌의 **선언**.
///
/// 예전에는 `MarbleTrack.standard()` 안에서 좌표를 절차적으로 쌓았다 —
/// 벽을 잇고, 반복문으로 핀밭을 깔고, 범퍼를 더하는 90줄. 코스가 하나뿐일
/// 때는 견딜 만했지만 두 번째 코스를 만들려면 그 90줄을 통째로 복사해야 했고,
/// "이 코스가 어떻게 생겼나" 를 읽으려면 코드를 실행해 봐야 했다.
///
/// 이제 코스는 좌표와 개수뿐인 값이다. 만드는 절차는 [build] 한 곳에만 있고,
/// 새 코스는 숫자만 적으면 된다.
///
/// **이름은 여기 없다.** 이 패키지는 화면 언어를 모른다 — `id` 만 싣고,
/// 사람이 읽는 이름은 앱의 규칙 선언(`ChoiceRule`)이 붙인다.
class MarbleCourseSpec {
  const MarbleCourseSpec({
    required this.id,
    required this.width,
    required this.top,
    required this.goalY,
    required this.zoomY,
    required this.leftWall,
    required this.rightWall,
    required this.spawn,
    this.ramps = const [],
    this.pegs = const [],
    this.pegGrids = const [],
    this.spinners = const [],
    this.bumpers = const [],
  });

  final String id;

  /// 코스 폭·꼭대기·결승선·클로즈업 시작선.
  final double width;
  final double top;
  final double goalY;
  final double zoomY;

  /// 외벽 꼭짓점(위→아래). 이으면 선분이 되고, 미니맵의 윤곽도 이것이다.
  final List<(double, double)> leftWall;
  final List<(double, double)> rightWall;

  /// 출발 대기열 배치.
  final SpawnSpec spawn;

  /// 지그재그 경사판 등 자유 선분.
  final List<(double, double, double, double)> ramps;

  /// 낱개 핀 — (x, y, 반지름).
  final List<(double, double, double)> pegs;

  /// 규칙적인 핀밭. 35개 좌표를 나열하는 것보다 "5줄 7칸" 이 읽힌다.
  final List<PegGrid> pegGrids;

  final List<SpinnerSpec> spinners;

  /// 튀는 벽 — (x1, y1, x2, y2, 반발).
  final List<(double, double, double, double, double)> bumpers;

  /// 선언을 굴릴 수 있는 코스로 만든다. 만드는 절차는 여기 한 곳뿐이다.
  MarbleTrack build() {
    final segments = <Segment>[];

    void wall(List<(double, double)> pts) {
      for (var i = 0; i < pts.length - 1; i++) {
        segments.add(
          Segment(pts[i].$1, pts[i].$2, pts[i + 1].$1, pts[i + 1].$2),
        );
      }
    }

    wall(leftWall);
    wall(rightWall);
    for (final r in ramps) {
      segments.add(Segment(r.$1, r.$2, r.$3, r.$4));
    }
    for (final b in bumpers) {
      segments.add(Segment(b.$1, b.$2, b.$3, b.$4, bounce: b.$5));
    }

    final allPegs = <Peg>[
      for (final p in pegs) Peg(p.$1, p.$2, p.$3),
      for (final g in pegGrids) ...g.build(),
    ];

    return MarbleTrack(
      width: width,
      goalY: goalY,
      zoomY: zoomY,
      top: top,
      segments: segments,
      pegs: allPegs,
      spinners: [
        for (final s in spinners)
          Spinner(
            cx: s.cx,
            cy: s.cy,
            length: s.length,
            omega: s.omega,
            phase: s.phase,
          ),
      ],
      leftWall: leftWall,
      rightWall: rightWall,
      spawn: spawn,
    );
  }
}

/// 출발 대기열 — 좁은 통로에 격자로 쌓는다.
/// 이 격자가 있어야 출발 연출이 "쏟아진다" 로 보인다.
class SpawnSpec {
  const SpawnSpec({
    required this.x0,
    required this.y0,
    this.perRow = 8,
    this.dx = 0.6,
    this.dy = 0.62,
    this.jitter = 0.18,
  });

  final double x0, y0;
  final int perRow;
  final double dx, dy;

  /// 자리마다 주는 미세한 흔들림. 0 이면 매번 똑같은 자리에서 출발한다.
  final double jitter;

  (double, double) pointFor(int i, Random rng) {
    final row = i ~/ perRow;
    final col = i % perRow;
    return (x0 + col * dx + (rng.nextDouble() - 0.5) * jitter, y0 - row * dy);
  }
}

/// 줄마다 반 칸 어긋난 핀밭.
class PegGrid {
  const PegGrid({
    required this.rows,
    required this.cols,
    required this.x0,
    required this.y0,
    required this.dx,
    required this.dy,
    this.stagger = 0,
    this.maxX = double.infinity,
    this.radius = 0.3,
  });

  final int rows, cols;
  final double x0, y0, dx, dy;

  /// 홀수 줄을 오른쪽으로 밀어 다이아 격자를 만든다.
  final double stagger;

  /// 이 값을 넘는 칸은 빼둔다 — 벽을 파고드는 핀을 막는다.
  final double maxX;
  final double radius;

  List<Peg> build() => [
    for (var row = 0; row < rows; row++)
      for (var col = 0; col < cols; col++)
        if (x0 + (row.isEven ? 0.0 : stagger) + col * dx <= maxX)
          Peg(
            x0 + (row.isEven ? 0.0 : stagger) + col * dx,
            y0 + row * dy,
            radius,
          ),
  ];
}

/// 도는 막대.
class SpinnerSpec {
  const SpinnerSpec({
    required this.cx,
    required this.cy,
    required this.length,
    required this.omega,
    this.phase = 0,
  });
  final double cx, cy, length, omega, phase;
}

/// 고를 수 있는 코스들.
///
/// 코스는 판마다 바뀌지 않는다 — 무작위는 출발 배치에서만 나온다. 코스까지
/// 매번 달라지면 "이번 판은 코스가 이상했다" 는 말이 나온다. 대신 호스트가
/// 판 전에 고를 수 있게 여러 벌을 둔다.
abstract final class MarbleCourses {
  /// 기본. 좌표는 원작(lazygyu/roulette)의 스케일을 따른다 —
  /// 구슬 반지름 0.25, 폭 ~24, 깊이 ~110, 중력 10.
  ///
  /// 위에서부터: 대기열 → S자 협곡 → 지그재그 경사판 → 핀밭 → 바람개비 →
  /// 톱니 협곡 → 최종 깔때기 → 외길 목 → 결승선.
  static const classic = MarbleCourseSpec(
    id: 'classic',
    width: 24,
    top: -8,
    goalY: 97,
    zoomY: 88,
    spawn: SpawnSpec(x0: 9.9, y0: 1.6),
    leftWall: [
      (9.4, -8.0), (9.4, 3.0), // 대기열
      (2.5, 9.0), (2.5, 13.0), // 첫 벌어짐
      (9.5, 17.0), (9.5, 19.0), // S자 — 오른쪽으로 밀림
      (2.0, 24.0), (2.0, 56.0), // 넓은 몸통(경사판·핀밭·바람개비)
      (7.0, 62.0), (2.0, 68.0), // 톱니 협곡
      (2.0, 76.0),
      (10.6, 86.0), (10.6, 96.0), // 최종 깔때기 → 목
    ],
    rightWall: [
      (14.6, -8.0),
      (14.6, 4.0),
      (21.5, 10.0),
      (21.5, 14.0),
      (14.5, 18.0),
      (14.5, 20.0),
      (22.0, 25.0),
      (22.0, 55.0),
      (17.0, 61.0),
      (22.0, 67.0),
      (22.0, 76.0),
      (13.4, 86.0),
      (13.4, 96.0),
    ],
    // S자 협곡 한복판의 다이아 — 좌우 흐름을 한 번 더 가른다.
    pegs: [(12.0, 15.0, 0.35), (12.0, 21.5, 0.35)],
    // 지그재그 경사판 두 장. 판 끝에 구슬 몇 개 폭의 틈을 남긴다.
    ramps: [
      (2.0, 26.0, 15.0, 30.5), // 왼→오, 틈은 오른쪽
      (22.0, 33.0, 9.0, 37.5), // 오→왼, 틈은 왼쪽
    ],
    pegGrids: [
      PegGrid(
        rows: 5,
        cols: 7,
        x0: 4.0,
        y0: 41.0,
        dx: 2.7,
        dy: 3.0,
        stagger: 1.35,
        maxX: 20.5,
      ),
    ],
    // 서로 반대로 돌려 한 방향 편향을 없앤다.
    spinners: [
      SpinnerSpec(cx: 8.0, cy: 58.5, length: 4.6, omega: 3.2),
      SpinnerSpec(cx: 16.0, cy: 63.0, length: 4.6, omega: -3.2, phase: 1.3),
      SpinnerSpec(cx: 12.0, cy: 68.5, length: 4.6, omega: 2.6, phase: 0.7),
    ],
    // 깔때기 안쪽 범퍼 — 목 직전에 순위가 한 번 더 뒤집히는 곳.
    bumpers: [
      (11.0, 80.0, 13.0, 80.0, 1.1),
      (8.0, 83.5, 9.6, 84.6, 1.1),
      (16.0, 83.5, 14.4, 84.6, 1.1),
    ],
  );

  /// 짧은 코스 — 핀밭과 바람개비를 한 겹씩만 지나 빨리 끝난다.
  ///
  /// 기본 코스는 20명이면 40초가 넘는다. 벌칙자 하나 뽑으려고 그만큼
  /// 들여다보고 있기는 길다는 자리가 있다.
  static const sprint = MarbleCourseSpec(
    id: 'sprint',
    width: 24,
    top: -8,
    goalY: 58,
    zoomY: 49,
    spawn: SpawnSpec(x0: 9.9, y0: 1.6),
    leftWall: [
      (9.4, -8.0),
      (9.4, 3.0),
      (2.5, 9.0),
      (2.5, 13.0),
      (9.5, 17.0),
      (9.5, 19.0),
      (2.0, 24.0),
      (2.0, 40.0),
      (10.6, 47.0),
      (10.6, 57.0),
    ],
    rightWall: [
      (14.6, -8.0),
      (14.6, 4.0),
      (21.5, 10.0),
      (21.5, 14.0),
      (14.5, 18.0),
      (14.5, 20.0),
      (22.0, 25.0),
      (22.0, 39.0),
      (13.4, 47.0),
      (13.4, 57.0),
    ],
    pegs: [(12.0, 15.0, 0.35), (12.0, 21.5, 0.35)],
    ramps: [(2.0, 26.0, 15.0, 30.5)],
    pegGrids: [
      PegGrid(
        rows: 3,
        cols: 7,
        x0: 4.0,
        y0: 33.0,
        dx: 2.7,
        dy: 3.0,
        stagger: 1.35,
        maxX: 20.5,
      ),
    ],
    spinners: [SpinnerSpec(cx: 12.0, cy: 43.5, length: 4.6, omega: 2.8)],
    bumpers: [(11.0, 45.0, 13.0, 45.0, 1.1)],
  );

  static const all = [classic, sprint];

  static const defaultId = 'classic';

  static MarbleCourseSpec byId(String? id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return classic;
  }

  static List<String> get ids => [for (final c in all) c.id];
}
