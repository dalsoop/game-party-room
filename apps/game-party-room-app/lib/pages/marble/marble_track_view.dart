import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../board_palette.dart';
import 'package:party_room_server/party_room_server.dart';

import '../host_hud.dart';

/// 구슬 룰렛의 **판 그리기**.
///
/// 진행 화면(`marble_page.dart`)에서 떼어 냈다. 그쪽은 시계를 돌리고 효과를
/// 갱신하고 버튼을 놓는 일을 하고, 여기는 받은 상태를 캔버스에 옮기기만
/// 한다 — 한 파일에 있을 때는 1,100줄이라 "지금 보는 것이 진행인가 그리기인가"
/// 를 매번 헤아려야 했다.

class MarbleSpark {
  MarbleSpark(
    this.x,
    this.y,
    this.vx,
    this.vy,
    this.life,
    this.maxLife,
    this.color,
    this.size,
  );
  double x, y, vx, vy, life;
  final double maxLife;
  final Color color;
  final double size;
}

/// 상단 지휘줄.
class MarbleTrackView extends StatelessWidget {
  const MarbleTrackView({
    super.key,
    required this.game,
    required this.cameraY,
    required this.cameraZoom,
    required this.sparks,
    required this.shakeOffset,
    required this.goFlash,
    required this.winnerIn,
  });

  final MarbleGame game;
  final double cameraY;
  final double cameraZoom;
  final List<MarbleSpark> sparks;
  final Offset shakeOffset;
  final double goFlash;
  final double winnerIn;

  @override
  Widget build(BuildContext context) {
    final ranking = game.world!.ranking;
    final picked = game.finished
        ? (game.winnerRank == 'last' ? ranking.last : ranking.first)
        : null;

    return Container(
      decoration: BoxDecoration(
        color: HostHud.panel,
        border: Border.all(color: HostHud.line, width: 1.5),
      ),
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: MarbleTrackPainter(
                world: game.world!,
                cameraY: cameraY,
                cameraZoom: cameraZoom,
                candidateLast: game.winnerRank == 'last',
                sparks: sparks,
                shakeOffset: shakeOffset,
              ),
              size: Size.infinite,
            ),
            // 출발 플래시 — 화면 전체가 한 번 번쩍이고 GO! 가 커지며 사라진다.
            if (goFlash > 0)
              IgnorePointer(
                child: Center(
                  child: Opacity(
                    opacity: (goFlash * 1.4).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 1.0 + (1 - goFlash) * 1.8,
                      child: const Text(
                        'GO!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 84,
                          fontWeight: FontWeight.w900,
                          shadows: [Shadow(color: HostHud.sky, blurRadius: 30)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // 당첨 배너 — 아래에서 올라오며 구슬 색으로 발표한다.
            if (picked != null)
              IgnorePointer(
                child: Align(
                  alignment: Alignment.center,
                  child: Opacity(
                    opacity: winnerIn.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, (1 - winnerIn) * 46),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(34, 20, 34, 22),
                        decoration: BoxDecoration(
                          color: const Color(0xF20A0F1E),
                          border: Border.all(
                            color: BoardPalette.of(picked.index),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: BoardPalette.of(
                                picked.index,
                              ).withValues(alpha: 0.45),
                              blurRadius: 44,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              game.winnerRank == 'last' ? '꼴찌 당첨' : '1등 당첨',
                              style: const TextStyle(
                                color: HostHud.dim,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: BoardPalette.of(picked.index),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  picked.nickname,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 44,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MarbleTrackPainter extends CustomPainter {
  MarbleTrackPainter({
    required this.world,
    required this.cameraY,
    required this.cameraZoom,
    required this.candidateLast,
    required this.sparks,
    required this.shakeOffset,
  });

  final MarbleWorld world;
  final double cameraY;
  final double cameraZoom;
  final bool candidateLast;
  final List<MarbleSpark> sparks;
  final Offset shakeOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final track = world.track;

    canvas.drawRect(Offset.zero & size, Paint()..color = HostHud.ground);

    // 배율 — 기본은 코스 전폭이 화면에 들어오는 크기, 클로즈업이 곱해진다.
    // (원작: 1유닛=30px 고정 캔버스 + zoom. 우리는 패널 크기가 유동이라
    //  전폭 기준으로 잡는다.)
    final ppu = size.width / (track.width + 3) * cameraZoom;
    final camX = track.width / 2;
    Offset p(double x, double y) => Offset(
      size.width / 2 + (x - camX) * ppu + shakeOffset.dx,
      size.height * 0.44 + (y - cameraY) * ppu + shakeOffset.dy,
    );

    _grid(canvas, size, ppu, p);
    _walls(canvas, track, ppu, p);
    _pegs(canvas, track, ppu, p);
    _spinners(canvas, track, ppu, p);
    _finish(canvas, track, ppu, p, size);
    _marbles(canvas, ppu, p);
    _sparkLayer(canvas, ppu, p);
    _minimap(canvas, size);
  }

  /// 이펙트 입자 — 수명에 따라 사그라드는 작은 마름모.
  void _sparkLayer(
    Canvas canvas,
    double ppu,
    Offset Function(double, double) p,
  ) {
    for (final sp in sparks) {
      final k = (sp.life / sp.maxLife).clamp(0.0, 1.0);
      final c = p(sp.x, sp.y);
      final r = sp.size * ppu * (0.6 + k * 0.4);
      final path = Path()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + r, c.dy)
        ..lineTo(c.dx, c.dy + r)
        ..lineTo(c.dx - r, c.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = sp.color.withValues(alpha: k));
    }
  }

  /// 옅은 격자 — 빈 배경이 "움직이고 있다" 를 보여 주는 기준선이 된다.
  void _grid(
    Canvas canvas,
    Size size,
    double ppu,
    Offset Function(double, double) p,
  ) {
    final paint = Paint()
      ..color = const Color(0xFF101830)
      ..strokeWidth = 1;
    final step = 4.0 * ppu;
    final oy = p(0, 0).dy % step;
    for (var y = oy; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final ox = p(0, 0).dx % step;
    for (var x = ox; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  /// 네온 이중 그리기 — 굵은 반투명 획(빛 번짐) 위에 가는 본선.
  /// 원작은 shadowBlur 를 쓰지만 매 프레임 블러는 비싸다. 이중 획이면 충분히
  /// "빛나는 선" 으로 읽히고 값이 싸다.
  void _glowLine(Canvas canvas, Offset a, Offset b, Color color, double w) {
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = color.withValues(alpha: 0.22)
        ..strokeWidth = w * 3.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = color
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round,
    );
  }

  void _walls(
    Canvas canvas,
    MarbleTrack track,
    double ppu,
    Offset Function(double, double) p,
  ) {
    final w = math.max(1.6, ppu * 0.08);
    for (final s in track.segments) {
      final neon = s.bounce != null
          ? const Color(0xFFFF6B81)
          : BoardPalette.wall;
      _glowLine(canvas, p(s.x1, s.y1), p(s.x2, s.y2), neon, w);
    }
  }

  void _pegs(
    Canvas canvas,
    MarbleTrack track,
    double ppu,
    Offset Function(double, double) p,
  ) {
    for (final peg in track.pegs) {
      final c = p(peg.x, peg.y);
      final r = peg.radius * ppu;
      canvas.drawCircle(
        c,
        r * 2.1,
        Paint()..color = BoardPalette.peg.withValues(alpha: 0.16),
      );
      // 원작의 45° 다이아몬드.
      final path = Path()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + r, c.dy)
        ..lineTo(c.dx, c.dy + r)
        ..lineTo(c.dx - r, c.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = BoardPalette.peg);
    }
  }

  void _spinners(
    Canvas canvas,
    MarbleTrack track,
    double ppu,
    Offset Function(double, double) p,
  ) {
    final w = math.max(2.0, ppu * 0.12);
    for (final sp in track.spinners) {
      // 잔상 — 조금 전 각도를 옅게 겹치면 날이 "돌고 있는" 것으로 읽힌다.
      for (var k = 3; k >= 1; k--) {
        final ghost = sp.segmentAt(world.time - k * 0.045);
        canvas.drawLine(
          p(ghost.x1, ghost.y1),
          p(ghost.x2, ghost.y2),
          Paint()
            ..color = BoardPalette.spinner.withValues(alpha: 0.10 * (4 - k))
            ..strokeWidth = w
            ..strokeCap = StrokeCap.round,
        );
      }
      final seg = sp.segmentAt(world.time);
      _glowLine(
        canvas,
        p(seg.x1, seg.y1),
        p(seg.x2, seg.y2),
        BoardPalette.spinner,
        w,
      );
      canvas.drawCircle(
        p(sp.cx, sp.cy),
        math.max(2.5, ppu * 0.12),
        Paint()..color = BoardPalette.wall,
      );
    }
  }

  void _finish(
    Canvas canvas,
    MarbleTrack track,
    double ppu,
    Offset Function(double, double) p,
    Size size,
  ) {
    final y = p(0, track.goalY).dy;
    if (y < -20 || y > size.height + 20) return;
    // 체커 띠 — 어느 줌에서도 "결승선" 으로 읽힌다.
    final left = p(10.6, track.goalY).dx;
    final right = p(13.4, track.goalY).dx;
    final cell = math.max(3.0, ppu * 0.18);
    for (var i = 0; (left + i * cell) < right; i++) {
      for (var j = 0; j < 2; j++) {
        canvas.drawRect(
          Rect.fromLTWH(left + i * cell, y + j * cell, cell, cell),
          Paint()..color = (i + j).isEven ? BoardPalette.goal : HostHud.panel,
        );
      }
    }
  }

  void _marbles(Canvas canvas, double ppu, Offset Function(double, double) p) {
    // 당첨 후보(원작의 흰 테두리): 1등 뽑기는 선두, 꼴찌 뽑기는 최후미.
    final candidate = candidateLast ? world.straggler : world.leader;

    for (final m in world.marbles) {
      if (m.finished) continue; // 원작처럼 도착한 구슬은 판에서 사라진다
      final c = p(m.x, m.y);
      final r = math.max(3.0, m.radius * ppu);
      final color = BoardPalette.of(m.index);

      // 속도 궤적 — 빠를수록 길게 끌린다. 상태 없이 속도에서 바로 그린다.
      final speed = math.sqrt(m.vx * m.vx + m.vy * m.vy);
      if (speed > 5) {
        final len = math.min(speed * 0.09, 2.6);
        final tail = p(m.x - m.vx / speed * len, m.y - m.vy / speed * len);
        canvas.drawLine(
          tail,
          c,
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = r * 1.1
            ..shader = ui.Gradient.linear(tail, c, [
              color.withValues(alpha: 0),
              color.withValues(alpha: 0.45),
            ]),
        );
      }

      canvas.drawCircle(
        c,
        r * 1.9,
        Paint()..color = color.withValues(alpha: 0.18),
      );
      canvas.drawCircle(c, r, Paint()..color = color);
      canvas.drawCircle(
        c.translate(-r * 0.3, -r * 0.3),
        r * 0.3,
        Paint()..color = const Color(0x99FFFFFF),
      );
      if (identical(m, candidate)) {
        canvas.drawCircle(
          c,
          r + math.max(1.5, ppu * 0.06),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.5, ppu * 0.05)
            ..color = Colors.white,
        );
      }

      // 이름 라벨 — 줌과 무관하게 같은 픽셀 크기(원작과 동일).
      final tp = TextPainter(
        text: TextSpan(
          text: m.nickname,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            shadows: const [
              Shadow(color: Colors.black, blurRadius: 3),
              Shadow(color: Colors.black, blurRadius: 3),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c + Offset(-tp.width / 2, r + 3));
    }
  }

  /// 좌상단 미니맵 — 전체 코스와 뷰포트(원작의 minimap).
  ///
  /// 선 몇 개로는 코스가 안 읽힌다. **내부를 면으로 채워** 실루엣을 만들고,
  /// 그 위에 핀·바람개비·결승선·구슬·뷰포트를 얹는다. 판 자체는 앱의
  /// HUD 어법(노치 잘린 판)을 따른다.
  void _minimap(Canvas canvas, Size size) {
    final track = world.track;
    final mh = size.height * 0.74;
    final span = track.goalY - track.top + 8;
    final scale = mh / span;
    final mw = track.width * scale + 14;
    const notch = 10.0;
    final origin = const Offset(12, 14);

    // 판 — 오른위 노치를 잘라 앱의 패널 어법과 맞춘다.
    final frame = Path()
      ..moveTo(origin.dx, origin.dy)
      ..lineTo(origin.dx + mw - notch, origin.dy)
      ..lineTo(origin.dx + mw, origin.dy + notch)
      ..lineTo(origin.dx + mw, origin.dy + mh)
      ..lineTo(origin.dx + notch, origin.dy + mh)
      ..lineTo(origin.dx, origin.dy + mh - notch)
      ..close();
    canvas.drawPath(frame, Paint()..color = const Color(0xE60A0F1E));
    canvas.drawPath(
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = HostHud.line,
    );
    // 브래킷 한 쌍 — 큰 패널과 같은 서명.
    final br = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = HostHud.sky;
    canvas.drawPath(
      Path()
        ..moveTo(origin.dx + 7, origin.dy)
        ..lineTo(origin.dx, origin.dy)
        ..lineTo(origin.dx, origin.dy + 7),
      br,
    );
    canvas.drawPath(
      Path()
        ..moveTo(origin.dx + mw - 7, origin.dy + mh)
        ..lineTo(origin.dx + mw, origin.dy + mh)
        ..lineTo(origin.dx + mw, origin.dy + mh - 7),
      br,
    );

    Offset mp(double x, double y) => Offset(
      origin.dx + 7 + x * scale,
      origin.dy + (y - track.top + 4) * scale,
    );

    // 코스 내부 — 왼벽(위→아래) + 오른벽(아래→위)을 이어 닫힌 실루엣.
    final course = Path()
      ..moveTo(
        mp(track.leftWall.first.$1, track.leftWall.first.$2).dx,
        mp(track.leftWall.first.$1, track.leftWall.first.$2).dy,
      );
    for (final (x, y) in track.leftWall.skip(1)) {
      final o = mp(x, y);
      course.lineTo(o.dx, o.dy);
    }
    for (final (x, y) in track.rightWall.reversed) {
      final o = mp(x, y);
      course.lineTo(o.dx, o.dy);
    }
    course.close();
    canvas.drawPath(course, Paint()..color = const Color(0xFF141D3B));
    canvas.drawPath(
      course,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF9FB4E8),
    );

    // 안쪽 구조물 — 경사판·범퍼(빨강), 핀(노랑), 바람개비(시안, 실제 각도).
    // 외벽 선분들은 segments 앞부분에 몰려 있다(윤곽으로 이미 그렸다).
    final innerWalls = track.segments.skip(
      (track.leftWall.length - 1) + (track.rightWall.length - 1),
    );
    for (final s in innerWalls) {
      canvas.drawLine(
        mp(s.x1, s.y1),
        mp(s.x2, s.y2),
        Paint()
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..color = s.bounce != null
              ? const Color(0xFFFF6B81)
              : const Color(0xFF8FA6DE),
      );
    }
    final pegPaint = Paint()..color = BoardPalette.peg;
    for (final peg in track.pegs) {
      canvas.drawCircle(mp(peg.x, peg.y), 1.4, pegPaint);
    }
    for (final sp in track.spinners) {
      final seg = sp.segmentAt(world.time);
      canvas.drawLine(
        mp(seg.x1, seg.y1),
        mp(seg.x2, seg.y2),
        Paint()
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = BoardPalette.spinner,
      );
    }

    // 결승선 — 체커 세 칸이면 어느 크기에서도 "골" 로 읽힌다.
    final gl = mp(10.6, track.goalY);
    final gr = mp(13.4, track.goalY);
    final cell = (gr.dx - gl.dx) / 3;
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 2; j++) {
        canvas.drawRect(
          Rect.fromLTWH(gl.dx + i * cell, gl.dy + j * 2.2, cell, 2.2),
          Paint()
            ..color = (i + j).isEven
                ? BoardPalette.goal
                : const Color(0xFF0A0F1E),
        );
      }
    }

    // 구슬 — 어두운 태두리를 깔아 작아도 뭉개지지 않는다.
    final candidate = candidateLast ? world.straggler : world.leader;
    for (final m in world.marbles) {
      if (m.finished) continue;
      final c = mp(m.x, m.y);
      canvas.drawCircle(c, 3.2, Paint()..color = const Color(0xFF05070F));
      canvas.drawCircle(c, 2.3, Paint()..color = BoardPalette.of(m.index));
      if (identical(m, candidate)) {
        canvas.drawCircle(
          c,
          4.0,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = Colors.white,
        );
      }
    }

    // 뷰포트 — 큰 화면이 보는 범위. 면을 살짝 밝혀 "카메라 창" 으로 읽힌다.
    final viewH = size.height / (size.width / (track.width + 3) * cameraZoom);
    final vt = mp(
      0,
      cameraY - viewH * 0.44,
    ).dy.clamp(origin.dy + 2, origin.dy + mh - 2);
    final vb = mp(
      0,
      cameraY + viewH * 0.56,
    ).dy.clamp(origin.dy + 2, origin.dy + mh - 2);
    final view = Rect.fromLTRB(origin.dx + 2.5, vt, origin.dx + mw - 2.5, vb);
    canvas.drawRect(view, Paint()..color = HostHud.sky.withValues(alpha: 0.10));
    canvas.drawRect(
      view,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = HostHud.sky.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant MarbleTrackPainter old) => true;
}

/// 오른쪽 순위판.
