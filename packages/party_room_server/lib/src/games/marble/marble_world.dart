/// 구슬 룰렛의 물리 세계.
///
/// 외부 물리 엔진을 쓰지 않는다. 필요한 충돌은 **원 대 선분**과 **원 대 원** 둘뿐이고,
/// 그 둘은 200줄이면 끝난다. Box2D 계열을 끌어오면 이 패키지가 네이티브 바이너리에
/// 묶여 헤드리스 서버·테스트에서 못 돈다.
///
/// 좌표계는 원작(lazygyu/roulette)의 스케일을 따른다 — 구슬 반지름 0.25,
/// 코스 폭 ~24, 깊이 ~110, 중력 10. 이 스케일이어야 화면 한 프레임에 장애물이
/// 빽빽하게 들어와 "핀볼 판" 으로 보인다. 단위를 키우면 같은 코스도 휑해진다.
/// y 는 아래로 증가한다(화면과 같은 방향).
library;

import 'dart:math';

import 'marble_course.dart';

/// 굴러 내려가는 구슬 하나.
class Marble {
  Marble({
    required this.index,
    required this.nickname,
    required this.tag,
    required this.x,
    required this.y,
    this.radius = 0.25,
  });

  /// 출발 순서(색·번호의 기준). 섞기는 배정 단계에서 끝내고 여기선 고정이다.
  final int index;
  final String nickname;
  final String tag;

  double x;
  double y;
  double vx = 0;
  double vy = 0;
  final double radius;

  /// 결승선을 통과한 순서(1부터). 아직이면 null.
  int? rank;
  bool get finished => rank != null;

  // 끼임 감지 — 원작도 일정 시간 못 움직인 구슬을 흔들어 준다.
  double stuckFor = 0;
  double lastX = 0;
  double lastY = 0;
}

/// 고정 벽 한 조각. 코스의 몸통은 전부 이것이다 — 원작처럼 외벽 자체가
/// 좁아졌다 벌어지는 지그재그 코스가 된다.
class Segment {
  const Segment(this.x1, this.y1, this.x2, this.y2, {this.bounce});
  final double x1, y1, x2, y2;

  /// null 이면 세계 기본 반발을 쓴다. 범퍼 벽만 따로 튀게 만들 때 준다.
  final double? bounce;
}

/// 튕겨내는 핀. 원작의 45° 다이아몬드 박스에 해당한다.
class Peg {
  const Peg(this.x, this.y, [this.radius = 0.3]);
  final double x, y, radius;
}

/// 축을 중심으로 도는 막대. 표면 속도가 있어 구슬을 후려친다.
class Spinner {
  const Spinner({
    required this.cx,
    required this.cy,
    required this.length,
    required this.omega,
    this.phase = 0,
  });

  final double cx, cy;
  final double length;

  /// 각속도(rad/s). 부호가 회전 방향.
  final double omega;
  final double phase;

  double angleAt(double t) => phase + omega * t;

  Segment segmentAt(double t) {
    final a = angleAt(t);
    final hx = cos(a) * length / 2;
    final hy = sin(a) * length / 2;
    return Segment(cx - hx, cy - hy, cx + hx, cy + hy);
  }
}

/// 코스 하나.
///
/// [goalY] 를 지나면 도착이고, [zoomY] 부터는 "골 직전" — 호스트 카메라가
/// 클로즈업을 시작하는 선이다(원작의 zoomY 와 같은 역할).
class MarbleTrack {
  const MarbleTrack({
    required this.width,
    required this.goalY,
    required this.zoomY,
    required this.top,
    required this.segments,
    required this.pegs,
    required this.spinners,
    required this.leftWall,
    required this.rightWall,
    required this.spawn,
  });

  final double width;
  final double goalY;
  final double zoomY;

  /// 코스 제일 위(출발 대기열 꼭대기). 미니맵이 전체 높이를 잡을 때 쓴다.
  final double top;

  final List<Segment> segments;
  final List<Peg> pegs;
  final List<Spinner> spinners;

  /// 외벽 꼭짓점(위→아래). 물리는 [segments] 만 쓰고, 이 둘은 그리기 전용 —
  /// 왼벽과 뒤집은 오른벽을 이으면 코스 내부의 닫힌 윤곽이 된다(미니맵 채움).
  final List<(double, double)> leftWall;
  final List<(double, double)> rightWall;

  /// 출발 대기열 배치 — 코스 선언이 정한다.
  final SpawnSpec spawn;

  /// [i]번째 구슬의 출발 위치. 배치 규칙은 코스 선언([SpawnSpec])에 있다.
  (double, double) spawnPoint(int i, Random rng) => spawn.pointFor(i, rng);

  /// 기본 코스.
  ///
  /// 좌표는 [MarbleCourses.classic] 에 선언으로 있다 — 여기서 절차적으로
  /// 쌓지 않는다. 코스를 고르는 경로는 [MarbleCourseSpec.build].
  factory MarbleTrack.standard() => MarbleCourses.classic.build();
}

/// 렌더러가 이펙트를 얹을 수 있게 흘려보내는 충돌 한 건.
///
/// **시뮬레이션 상태가 아니다** — 기록해도 순위는 조금도 안 바뀐다.
/// 호스트가 스파크·흔들림을 그리는 데만 쓰고, 헤드리스에서는 아무도 안 읽는다.
class WorldHit {
  const WorldHit(this.x, this.y, this.power, this.kind);
  final double x, y, power;

  /// 0 벽 · 1 핀 · 2 구슬끼리 · 3 범퍼.
  final int kind;
}

/// 시뮬레이션.
///
/// 고정 시간 간격으로만 전진한다([fixedStep]). 호스트의 프레임 간격이 흔들려도
/// 결과가 흔들리면 안 되기 때문이다 — 같은 시드·같은 배치는 언제나 같은 순위를
/// 만든다. 저장·복원이 이 성질에 기대고 있다.
class MarbleWorld {
  MarbleWorld({
    required this.track,
    required List<Marble> marbles,
    required int seed,
    this.gravity = 10,
    // 초기화 형식(this._marbles)으로 바꾸면 부르는 쪽 이름이 `_marbles:` 가
    // 되어 밖에서 밑줄을 보게 된다. 이름은 밖의 것이라 이대로 둔다.
    // ignore: prefer_initializing_formals
  }) : _marbles = marbles,
       _rng = Random(seed) {
    for (final m in _marbles) {
      m.lastX = m.x;
      m.lastY = m.y;
    }
  }

  static const double fixedStep = 1 / 240;

  static const double _wallBounce = 0.22;
  static const double _pegBounce = 0.72;
  static const double _marbleBounce = 0.45;
  static const double _friction = 0.015;
  static const double _maxSpeed = 32;

  final MarbleTrack track;
  final List<Marble> _marbles;
  final Random _rng;
  final double gravity;

  List<Marble> get marbles => List.unmodifiable(_marbles);

  double _time = 0;
  double _carry = 0;
  int _finishedCount = 0;

  final List<WorldHit> _hits = [];

  /// 마지막으로 가져간 뒤 쌓인 굵직한 충돌들. 가져가면 비운다.
  List<WorldHit> takeHits() {
    final out = List<WorldHit>.of(_hits);
    _hits.clear();
    return out;
  }

  void _hit(double x, double y, double power, int kind) {
    // 렌더 없이 오래 돌 때(헤드리스) 무한정 쌓이지 않게 막는다.
    if (_hits.length < 128) _hits.add(WorldHit(x, y, power, kind));
  }

  /// 회전막대 각도 계산용. 호스트가 그릴 때도 쓴다.
  double get time => _time;
  bool get done => _finishedCount >= _marbles.length;

  /// 결승선을 통과한 순서.
  List<Marble> get ranking =>
      (_marbles.where((m) => m.finished).toList()
        ..sort((a, b) => a.rank!.compareTo(b.rank!)));

  /// 아직 안 들어온 구슬 중 가장 앞선 것.
  Marble? get leader {
    Marble? best;
    for (final m in _marbles) {
      if (m.finished) continue;
      if (best == null || m.y > best.y) best = m;
    }
    return best;
  }

  /// 아직 안 들어온 구슬 중 가장 뒤처진 것 — 꼴찌 뽑기 카메라가 따라간다.
  Marble? get straggler {
    Marble? worst;
    for (final m in _marbles) {
      if (m.finished) continue;
      if (worst == null || m.y < worst.y) worst = m;
    }
    return worst;
  }

  int get remaining => _marbles.length - _finishedCount;

  /// 실시간 [dt] 만큼 진행. 내부적으로는 고정 간격으로 쪼개 돈다.
  void advance(double dt) {
    // 창을 오래 가렸다 돌아오면 dt 가 몇 초씩 들어온다. 그대로 돌리면
    // 프레임 하나에 수천 스텝이 돌아 화면이 순간이동한 것처럼 보인다.
    _carry += dt.clamp(0.0, 0.25);
    while (_carry >= fixedStep) {
      _carry -= fixedStep;
      _step(fixedStep);
    }
  }

  /// 렌더 없이 끝까지 돌린다(헤드리스·테스트). 안 끝나면 [maxSeconds] 에서 손절.
  void runToCompletion({double maxSeconds = 240}) {
    var elapsed = 0.0;
    while (!done && elapsed < maxSeconds) {
      _step(fixedStep);
      elapsed += fixedStep;
    }
    _rankStragglers();
  }

  /// 남은 구슬을 현재 진행도 순으로 마감한다.
  void _rankStragglers() {
    final rest = _marbles.where((m) => !m.finished).toList()
      ..sort((a, b) => b.y.compareTo(a.y));
    for (final m in rest) {
      m.rank = ++_finishedCount;
    }
  }

  void _step(double dt) {
    _time += dt;

    for (final m in _marbles) {
      if (m.finished) continue;

      m.vy += gravity * dt;
      m.x += m.vx * dt;
      m.y += m.vy * dt;

      _collideSegments(m);
      _collidePegs(m);
      _watchStuck(m, dt);

      if (m.y >= track.goalY) {
        m.rank = ++_finishedCount;
      }
    }

    _collideMarbles();

    // 구슬끼리 밀치는 보정이 벽을 무시하고 위치를 옮긴다 — 밀린 구슬이 벽을
    // 조금씩 파고들다 뚫고 나가면 코스를 건너뛴 채 결승선을 밟는다.
    // 충돌 처리 뒤 한 번 더 벽에 밟아 넣어 그 경로를 차단한다.
    for (final m in _marbles) {
      if (m.finished) continue;
      _collideSegments(m);
    }
  }

  /// 원작의 shakeMarble — 한 구슬이 한동안 못 움직이면 그 구슬만 찬다.
  /// 전원을 흔들면 멀쩡히 구르던 판까지 흐트러진다.
  void _watchStuck(Marble m, double dt) {
    final dx = m.x - m.lastX;
    final dy = m.y - m.lastY;
    if (dx * dx + dy * dy < 0.000004) {
      m.stuckFor += dt;
      if (m.stuckFor > 2.5) {
        m.stuckFor = 0;
        m.vx += (_rng.nextDouble() - 0.5) * 5;
        m.vy -= 2 + _rng.nextDouble() * 2;
      }
    } else {
      m.stuckFor = 0;
    }
    m.lastX = m.x;
    m.lastY = m.y;
  }

  void _collideSegments(Marble m) {
    for (final s in track.segments) {
      _resolveSegment(m, s, 0, 0, s.bounce ?? _wallBounce);
    }
    for (final sp in track.spinners) {
      final seg = sp.segmentAt(_time);
      // 막대 표면의 속도(ω × r) 를 함께 넘겨야 구슬이 밀려난다.
      final rx = m.x - sp.cx;
      final ry = m.y - sp.cy;
      _resolveSegment(m, seg, -sp.omega * ry, sp.omega * rx, _wallBounce);
    }
  }

  /// 원 대 선분. [sx],[sy] 는 접촉 지점에서 면이 움직이는 속도.
  void _resolveSegment(Marble m, Segment s, double sx, double sy, double e) {
    final ex = s.x2 - s.x1;
    final ey = s.y2 - s.y1;
    final len2 = ex * ex + ey * ey;
    var t = len2 == 0 ? 0.0 : ((m.x - s.x1) * ex + (m.y - s.y1) * ey) / len2;
    t = t.clamp(0.0, 1.0);
    final px = s.x1 + ex * t;
    final py = s.y1 + ey * t;

    var dx = m.x - px;
    var dy = m.y - py;
    var dist = sqrt(dx * dx + dy * dy);
    if (dist >= m.radius) return;

    if (dist == 0) {
      // 선분 위에 정확히 얹힌 경우 — 법선을 만들 수 없으니 위로 밀어낸다.
      dx = 0;
      dy = -1;
      dist = 0.0001;
    }
    final nx = dx / dist;
    final ny = dy / dist;

    // 파고든 만큼 되민다. 이걸 빼면 구슬이 벽을 통과한다.
    final push = m.radius - dist;
    m.x += nx * push;
    m.y += ny * push;

    // 면 기준 상대 속도로 반사한다.
    final rvx = m.vx - sx;
    final rvy = m.vy - sy;
    final vn = rvx * nx + rvy * ny;
    if (vn >= 0) return; // 이미 멀어지는 중

    if (vn < -3.5) {
      _hit(px, py, -vn, s.bounce != null ? 3 : 0);
    }

    final jn = -(1 + e) * vn;
    var nvx = rvx + nx * jn;
    var nvy = rvy + ny * jn;

    // 접선 마찰 — 없으면 경사판에서 미끄러지기만 하고 안 구른다.
    final tx = -ny;
    final ty = nx;
    final vt = nvx * tx + nvy * ty;
    nvx -= tx * vt * _friction;
    nvy -= ty * vt * _friction;

    m.vx = nvx + sx;
    m.vy = nvy + sy;
    _clampSpeed(m);
  }

  void _collidePegs(Marble m) {
    for (final p in track.pegs) {
      final dx = m.x - p.x;
      final dy = m.y - p.y;
      final minD = m.radius + p.radius;
      final d2 = dx * dx + dy * dy;
      if (d2 >= minD * minD) continue;

      var d = sqrt(d2);
      var nx = 1.0, ny = 0.0;
      if (d > 0) {
        nx = dx / d;
        ny = dy / d;
      } else {
        d = 0.0001;
      }
      m.x += nx * (minD - d);
      m.y += ny * (minD - d);

      final vn = m.vx * nx + m.vy * ny;
      if (vn >= 0) continue;
      if (vn < -3) _hit(p.x, p.y, -vn, 1);
      final jn = -(1 + _pegBounce) * vn;
      m.vx += nx * jn;
      m.vy += ny * jn;
      _clampSpeed(m);
    }
  }

  void _collideMarbles() {
    for (var i = 0; i < _marbles.length; i++) {
      final a = _marbles[i];
      if (a.finished) continue;
      for (var j = i + 1; j < _marbles.length; j++) {
        final b = _marbles[j];
        if (b.finished) continue;

        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final minD = a.radius + b.radius;
        final d2 = dx * dx + dy * dy;
        if (d2 >= minD * minD || d2 == 0) continue;

        final d = sqrt(d2);
        final nx = dx / d;
        final ny = dy / d;
        final push = (minD - d) / 2;
        a.x -= nx * push;
        a.y -= ny * push;
        b.x += nx * push;
        b.y += ny * push;

        final rvn = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
        if (rvn >= 0) continue;
        if (rvn < -4) {
          _hit((a.x + b.x) / 2, (a.y + b.y) / 2, -rvn, 2);
        }
        // 질량이 같으므로 법선 성분을 반씩 주고받는다.
        final jn = -(1 + _marbleBounce) * rvn / 2;
        a.vx -= nx * jn;
        a.vy -= ny * jn;
        b.vx += nx * jn;
        b.vy += ny * jn;
        _clampSpeed(a);
        _clampSpeed(b);
      }
    }
  }

  void _clampSpeed(Marble m) {
    final sp = sqrt(m.vx * m.vx + m.vy * m.vy);
    if (sp <= _maxSpeed) return;
    final k = _maxSpeed / sp;
    m.vx *= k;
    m.vy *= k;
  }
}
