import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:party_room_server/party_room_server.dart';

import 'board_palette.dart';
import 'host_hud.dart';

import '../host_controller.dart';

/// 사다리타기 — 호스트 화면.
///
/// 구슬 룰렛과 같은 관전형이라 화면 문법도 같은 다크 네온 HUD 를 쓴다.
/// 위에 참가자(색·이름), 아래에 결과 칸, 사이에 사다리. [다음 공개] 를 누르면
/// 그 줄의 경로가 빛으로 그려져 내려가고, **연출이 끝난 뒤에야** 그 참가자
/// 폰으로 결과가 나간다 — 폰이 큰 화면보다 먼저 스포일러를 띄우면 안 된다.
class LadderPage extends StatefulWidget {
  const LadderPage({super.key, required this.ctrl});

  final HostController ctrl;

  /// 로비에서 호출: 결과 칸 입력 → 시작.
  static Future<void> startFlow(
    BuildContext context,
    HostController ctrl,
  ) async {
    final outcomes = await showDialog<List<String>>(
      context: context,
      builder: (_) => const _LadderSetupDialog(),
    );
    if (outcomes == null) return;
    if (!context.mounted) return;
    if (!ctrl.games.startLadder(outcomes)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('2명 이상 접속해야 시작할 수 있습니다')));
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LadderPage(ctrl: ctrl)),
    );
  }

  @override
  State<LadderPage> createState() => _LadderPageState();
}

/// 추적 연출의 **상태는 컨트롤러에 있다**(`ladderTracing`/`ladderProgress`).
///
/// 예전에는 이 화면이 들고 있었다. 그래서 추적 1.6초 안에 뒤로 가면 그 줄이
/// 영영 미공개로 남고 판이 안 끝났다 — 참가자 폰은 대기 화면에 멈춘 채.
/// 연출은 보여주는 일이지만 **끝나는 시점이 곧 결과 확정**이라 진행이다.
class _LadderPageState extends State<LadderPage> {
  int? get _tracing => widget.ctrl.games.ladderTracing;
  double get _progress => widget.ctrl.games.ladderProgress;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ctrl,
      builder: (context, _) {
        final game = widget.ctrl.games.ladder;
        if (game == null || game.ladder == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          });
          return const SizedBox.shrink();
        }
        return Scaffold(
          backgroundColor: HostHud.ground,
          body: SafeArea(
            child: Column(
              children: [
                _CommandBar(game: game),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: HostHud.panel,
                        border: Border.all(color: HostHud.line, width: 1.5),
                      ),
                      child: ClipRect(
                        child: CustomPaint(
                          painter: _LadderPainter(
                            game: game,
                            tracing: _tracing,
                            progress: _progress,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ),
                ),
                _Controls(
                  ctrl: widget.ctrl,
                  game: game,
                  animating: _tracing != null,
                  onNext: widget.ctrl.games.traceNextLadder,
                  onAll: widget.ctrl.games.traceAllLadder,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CommandBar extends StatelessWidget {
  const _CommandBar({required this.game});

  final LadderGame game;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: HostHud.plate,
      padding: const EdgeInsets.fromLTRB(18, 11, 18, 10),
      child: Row(
        children: [
          Transform.rotate(
            angle: math.pi / 4,
            child: Container(width: 9, height: 9, color: HostHud.sky),
          ),
          const SizedBox(width: 10),
          const Text(
            '사다리타기',
            style: TextStyle(
              color: HostHud.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            '${game.revealed.length} / ${game.roster.length} 공개',
            style: const TextStyle(
              color: HostHud.dim,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _LadderPainter extends CustomPainter {
  _LadderPainter({
    required this.game,
    required this.tracing,
    required this.progress,
  });

  final LadderGame game;
  final int? tracing;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final ladder = game.ladder!;
    final n = ladder.columns;
    final rows = ladder.rows;

    canvas.drawRect(Offset.zero & size, Paint()..color = HostHud.ground);

    // 레이아웃 — 위 이름띠 / 사다리 / 아래 결과띠.
    const headH = 74.0;
    const footH = 84.0;
    final left = math.max(30.0, size.width * 0.06);
    final laneW = (size.width - left * 2) / math.max(1, n - 1);
    final topY = headH;
    final botY = size.height - footH;
    final rowH = (botY - topY) / (rows + 1);

    double colX(int c) => left + c * laneW;
    // 경로의 세로 위치: 행 r 경계 = topY + (r+0.5)*rowH (가로대는 행 중앙).
    double rowY(int r) => topY + (r + 0.5) * rowH;

    // 세로줄 — 공개된 줄은 옅게, 미공개는 또렷하게(아직 주인공이 남았다는 뜻).
    for (var c = 0; c < n; c++) {
      final done = game.revealed.contains(c);
      final paint = Paint()
        ..color = done
            ? BoardPalette.wall.withValues(alpha: 0.22)
            : BoardPalette.wall.withValues(alpha: 0.75)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(colX(c), topY), Offset(colX(c), botY), paint);
    }

    // 가로대.
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < n - 1; c++) {
        if (!ladder.rungAt(r, c)) continue;
        final y = rowY(r);
        canvas.drawLine(
          Offset(colX(c), y),
          Offset(colX(c + 1), y),
          Paint()
            ..color = HostHud.sky.withValues(alpha: 0.5)
            ..strokeWidth = 2,
        );
      }
    }

    // 공개된 줄들의 지나간 경로 — 은은하게 남겨 둔다.
    for (final c in game.revealed) {
      _drawPath(canvas, ladder, c, 1.0, colX, rowY, topY, botY, dim: true);
    }
    // 지금 추적 중인 경로 — 진하게, 끝에 빛나는 점.
    if (tracing != null) {
      _drawPath(
        canvas,
        ladder,
        tracing!,
        progress,
        colX,
        rowY,
        topY,
        botY,
        dim: false,
      );
    }

    _heads(canvas, n, colX, topY);
    _feet(canvas, n, colX, botY, size);
  }

  /// [column] 줄의 경로를 [t](0~1)만큼 그린다.
  void _drawPath(
    Canvas canvas,
    Ladder ladder,
    int column,
    double t,
    double Function(int) colX,
    double Function(int) rowY,
    double topY,
    double botY, {
    required bool dim,
  }) {
    final cols = ladder.trace(column);
    final pts = <Offset>[Offset(colX(cols[0]), topY)];
    for (var r = 0; r < ladder.rows; r++) {
      final y = rowY(r);
      if (cols[r + 1] != cols[r]) {
        pts.add(Offset(colX(cols[r]), y));
        pts.add(Offset(colX(cols[r + 1]), y));
      }
    }
    pts.add(Offset(colX(cols.last), botY));

    // 전체 길이 대비 t 지점까지 자른다.
    var total = 0.0;
    for (var i = 1; i < pts.length; i++) {
      total += (pts[i] - pts[i - 1]).distance;
    }
    var remain = total * t.clamp(0.0, 1.0);
    final drawn = <Offset>[pts.first];
    Offset tip = pts.first;
    for (var i = 1; i < pts.length && remain > 0; i++) {
      final seg = pts[i] - pts[i - 1];
      final len = seg.distance;
      if (len <= remain) {
        drawn.add(pts[i]);
        tip = pts[i];
        remain -= len;
      } else {
        tip = pts[i - 1] + seg * (remain / len);
        drawn.add(tip);
        remain = 0;
      }
    }

    final color = _colorOf(column);
    final path = Path()..moveTo(drawn.first.dx, drawn.first.dy);
    for (final p in drawn.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = dim ? 3 : 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: dim ? 0.30 : 0.55),
    );
    if (!dim) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );
      canvas.drawCircle(tip, 10, Paint()..color = color.withValues(alpha: 0.3));
      canvas.drawCircle(tip, 5.5, Paint()..color = color);
      canvas.drawCircle(
        tip.translate(-1.5, -1.5),
        1.8,
        Paint()..color = const Color(0xB3FFFFFF),
      );
    }
  }

  Color _colorOf(int column) {
    final hex = partyColorOf(column);
    return Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
  }

  /// 위 이름띠 — 색점 + 이름. 추적 중인 줄은 밝게.
  void _heads(Canvas canvas, int n, double Function(int) colX, double topY) {
    for (var c = 0; c < n; c++) {
      final seat = game.roster.seats[c];
      final active = tracing == c;
      final color = _colorOf(c);
      final center = Offset(colX(c), topY - 34);

      canvas.drawCircle(center, active ? 15 : 12, Paint()..color = color);
      if (active) {
        canvas.drawCircle(
          center,
          19,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white,
        );
      }
      final no = TextPainter(
        text: TextSpan(
          text: '${c + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      no.paint(canvas, center - Offset(no.width / 2, no.height / 2));

      final name = TextPainter(
        text: TextSpan(
          text: seat.nickname,
          style: TextStyle(
            color: active ? Colors.white : HostHud.ink,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        ellipsis: '…',
      )..layout(maxWidth: 76);
      name.paint(canvas, Offset(colX(c) - name.width / 2, topY - 16));
    }
  }

  /// 아래 결과띠 — 도착 칸. 공개로 밝혀진 칸은 그 참가자 색을 입는다.
  void _feet(
    Canvas canvas,
    int n,
    double Function(int) colX,
    double botY,
    Size size,
  ) {
    // 도착 칸 → 이미 공개된 출발 줄. 색을 입히려면 역방향 매핑이 필요하다.
    final owner = <int, int>{};
    for (final c in game.revealed) {
      owner[game.ladder!.endOf(c)] = c;
    }

    for (var e = 0; e < n; e++) {
      final outcome = game.outcomes[e];
      final hit = outcome != '꽝';
      final from = owner[e];
      final w = math.min(84.0, math.max(46.0, size.width / n - 10));
      final rect = Rect.fromCenter(
        center: Offset(colX(e), botY + 34),
        width: w,
        height: 40,
      );

      final bg = from != null
          ? _colorOf(from)
          : (hit ? HostHud.plate : const Color(0xFF0E1428));
      canvas.drawRect(rect, Paint()..color = bg);
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = hit ? 1.8 : 1
          ..color = hit
              ? BoardPalette.goal.withValues(alpha: from != null ? 0.9 : 0.7)
              : HostHud.line,
      );

      final label = TextPainter(
        text: TextSpan(
          text: outcome,
          style: TextStyle(
            color: from != null
                ? Colors.white
                : (hit ? HostHud.ink : HostHud.dim),
            fontSize: 12.5,
            fontWeight: hit ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        ellipsis: '…',
      )..layout(maxWidth: w - 10);
      label.paint(
        canvas,
        Offset(colX(e) - label.width / 2, botY + 34 - label.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LadderPainter old) => true;
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.ctrl,
    required this.game,
    required this.animating,
    required this.onNext,
    required this.onAll,
  });

  final HostController ctrl;
  final LadderGame game;
  final bool animating;
  final VoidCallback onNext;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final remaining = game.roster.length - game.revealed.length;
    return Container(
      color: HostHud.plate,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(
        children: [
          Text(
            game.finished
                ? '전원 공개 완료'
                : animating
                ? '사다리 타는 중…'
                : '$remaining줄 남음',
            style: const TextStyle(color: HostHud.dim, fontSize: 14),
          ),
          const Spacer(),
          if (game.finished)
            FilledButton(
              onPressed: ctrl.games.restartLadder,
              style: FilledButton.styleFrom(
                backgroundColor: HostHud.sky,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
              ),
              child: const Text(
                '한 판 더',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          if (!game.finished) ...[
            FilledButton(
              onPressed: animating ? null : onNext,
              style: FilledButton.styleFrom(
                backgroundColor: HostHud.sky,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
              child: const Text(
                '다음 공개',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: animating ? null : onAll,
              child: const Text(
                '남은 전부 공개',
                style: TextStyle(color: HostHud.ink),
              ),
            ),
          ],
          const SizedBox(width: 10),
          TextButton(
            onPressed: () {
              ctrl.games.endGame();
              Navigator.pop(context);
            },
            child: const Text('끝내기', style: TextStyle(color: HostHud.dim)),
          ),
        ],
      ),
    );
  }
}

/// 결과 칸 입력 다이얼로그.
class _LadderSetupDialog extends StatefulWidget {
  const _LadderSetupDialog();

  @override
  State<_LadderSetupDialog> createState() => _LadderSetupDialogState();
}

class _LadderSetupDialogState extends State<_LadderSetupDialog> {
  final _outcomes = TextEditingController();

  @override
  void dispose() {
    _outcomes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('사다리타기'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _outcomes,
              decoration: const InputDecoration(
                labelText: '걸 것 (쉼표로 구분)',
                hintText: '예: 벌칙, 아이스크림 사기',
                helperText: '비워 두면 당첨 1개, 나머지는 꽝.\n인원보다 적으면 꽝으로 채웁니다.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            final outcomes = _outcomes.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            Navigator.pop(context, outcomes);
          },
          child: const Text('시작'),
        ),
      ],
    );
  }
}
