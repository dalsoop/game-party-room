import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'board_palette.dart';
import 'package:flutter/scheduler.dart';
import 'package:party_room_server/party_room_server.dart';

import '../host_controller.dart';
import '../server/sound_service.dart';
import 'host_hud.dart';
import 'marble/marble_track_view.dart';

/// 구슬 룰렛 — 호스트 화면.
///
/// 이 종목은 큰 화면이 본체다. 참가자 폰에는 "내 구슬 몇 번" 밖에 없고,
/// 사람들이 실제로 보는 것은 여기다.
///
/// 화면 문법은 원작(lazygyu/roulette)을 따른다 —
/// 검은 바탕에 네온으로 그린 코스, 당첨 후보를 따라가는 카메라,
/// 골 직전 클로즈업과 슬로모션, 전체 코스 미니맵, 구슬 위 이름 라벨.
/// 원작이 이 조합을 쓰는 이유는 하나다: 뽑기의 재미는 "누가 이기나" 를
/// 끝까지 눈으로 쫓게 만드는 데서 나온다.
class MarblePage extends StatefulWidget {
  const MarblePage({super.key, required this.ctrl});

  final HostController ctrl;

  /// 로비에서 호출.
  static Future<void> startFlow(
    BuildContext context,
    HostController ctrl,
  ) async {
    if (!ctrl.games.startMarble()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('2명 이상 접속해야 시작할 수 있습니다')));
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MarblePage(ctrl: ctrl)),
    );
  }

  @override
  State<MarblePage> createState() => _MarblePageState();
}

/// 이펙트 입자 하나. 좌표는 물리 세계 단위 — 그릴 때 카메라가 변환한다.
class _MarblePageState extends State<MarblePage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  // 카메라 — 위치·줌 둘 다 지수 보간으로 따라붙는다(원작의 d/10 보간).
  double _camY = 0;
  double _camZoom = 1;
  bool _camReady = false;

  // 연출 상태 — 전부 렌더 전용. 시뮬레이션에는 손대지 않는다.
  final List<MarbleSpark> _sparks = [];
  final math.Random _fx = math.Random();
  double _shake = 0;
  Offset _shakeOffset = Offset.zero;
  int _seenFinished = 0;
  bool _wasRunning = false;
  double _goFlash = 0;
  double _winnerIn = 0;

  void _onFrame(Duration now) {
    final dt = _last == Duration.zero
        ? 0.0
        : (now - _last).inMicroseconds / 1e6;
    _last = now;

    final game = widget.ctrl.games.marble;
    final w = game?.world;
    if (game == null || w == null) return;

    // 시간 배율 — 물리는 고정 스텝이라 몇 배로 흘리든 최종 순위는 같다.
    // 시뮬레이션을 굴리는 것은 컨트롤러의 시계다 — 이 화면은 카메라와
    // 이펙트만 맡는다. 화면을 벗어나도 판이 끝까지 가야 하기 때문이다.
    final target = _cameraTarget(game, w);
    final decided = game.decided && !game.finished;

    // 카메라 목표 — 후보 구슬. 클로즈업은 결정 전, 골 근처에서만
    // (원작 공식: (1-d/5)*4). 결정 뒤에는 빼서 요요를 없앤다.
    final ty = target?.y ?? w.track.zoomY;
    var tz = 1.0;
    if (target != null && !decided) {
      final d = (w.track.zoomY - target.y).abs();
      if (w.track.zoomY - target.y < 5) {
        tz = math.max(1.0, (1 - d / 5) * 2.6);
      }
    }
    if (!_camReady) {
      _camY = ty;
      _camZoom = 1;
      _camReady = true;
    } else if (dt > 0) {
      final k = 1 - math.pow(0.002, dt).toDouble();
      _camY += (ty - _camY) * k;
      _camZoom += (tz - _camZoom) * k;
    }

    if (dt > 0) _updateEffects(game, w, dt);
    setState(() {});
  }

  /// 스파크·폭죽·흔들림·배너 — 물리에서 흘러나온 이벤트를 연출로 바꾼다.
  void _updateEffects(MarbleGame game, MarbleWorld w, double dt) {
    // 굵은 충돌 → 스파크 + 흔들림.
    for (final hit in w.takeHits()) {
      final color = switch (hit.kind) {
        1 => BoardPalette.peg,
        3 => const Color(0xFFFF6B81),
        2 => const Color(0xFFBFE3FF),
        _ => BoardPalette.wall,
      };
      final n = hit.power > 8 ? 6 : 3;
      for (var i = 0; i < n; i++) {
        final a = _fx.nextDouble() * math.pi * 2;
        final sp = 1.5 + _fx.nextDouble() * hit.power * 0.35;
        _sparks.add(
          MarbleSpark(
            hit.x,
            hit.y,
            math.cos(a) * sp,
            math.sin(a) * sp - 1.5,
            0.38,
            0.38,
            color,
            0.055 + _fx.nextDouble() * 0.05,
          ),
        );
      }
      if (hit.power > 9) _shake = math.min(1, _shake + hit.power * 0.03);
    }

    // 골인 → 그 구슬 색 폭죽 + 소리.
    final ranking = w.ranking;
    while (_seenFinished < ranking.length) {
      final m = ranking[_seenFinished++];
      widget.ctrl.sound.play(GameSound.finish);
      final color = BoardPalette.of(m.index);
      for (var i = 0; i < 26; i++) {
        final a = -math.pi / 2 + (_fx.nextDouble() - 0.5) * 2.4;
        final sp = 3 + _fx.nextDouble() * 9;
        _sparks.add(
          MarbleSpark(
            12 + (_fx.nextDouble() - 0.5) * 2.4,
            w.track.goalY,
            math.cos(a) * sp,
            math.sin(a) * sp,
            0.9 + _fx.nextDouble() * 0.5,
            1.4,
            i % 3 == 0 ? Colors.white : color,
            0.07 + _fx.nextDouble() * 0.08,
          ),
        );
      }
      _shake = math.min(1, _shake + 0.35);
    }

    // 입자 갱신 — 자체 중력, 수명이 다하면 제거.
    for (final sp in _sparks) {
      sp.vy += 14 * dt;
      sp.x += sp.vx * dt;
      sp.y += sp.vy * dt;
      sp.life -= dt;
    }
    _sparks.removeWhere((sp) => sp.life <= 0);

    // 흔들림은 지수 감쇠, 오프셋은 매 프레임 새로 뽑는다.
    _shake *= math.pow(0.0001, dt).toDouble();
    _shakeOffset = _shake < 0.02
        ? Offset.zero
        : Offset(
            (_fx.nextDouble() - 0.5) * 14 * _shake,
            (_fx.nextDouble() - 0.5) * 10 * _shake,
          );

    // 출발 플래시와 당첨 배너 진입.
    if (game.running && !_wasRunning) _goFlash = 1;
    _wasRunning = game.running;
    _goFlash = math.max(0, _goFlash - dt * 0.9);
    _winnerIn = game.finished ? math.min(1, _winnerIn + dt * 2.4) : 0;
  }

  /// 카메라가 쫓는 구슬. 1등 뽑기는 선두, 꼴찌 뽑기는 (거의 다 들어왔으면)
  /// 최후미가 주인공이다.
  Marble? _cameraTarget(MarbleGame game, MarbleWorld w) {
    if (game.winnerRank == 'last' && w.remaining <= 2) return w.straggler;
    return w.leader;
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onFrame)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ctrl,
      builder: (context, _) {
        final game = widget.ctrl.games.marble;
        if (game == null || game.world == null) {
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
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                          child: MarbleTrackView(
                            game: game,
                            cameraY: _camY,
                            cameraZoom: _camZoom,
                            sparks: _sparks,
                            shakeOffset: _shakeOffset,
                            goFlash: _goFlash,
                            winnerIn: _winnerIn,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 256,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(6, 12, 14, 12),
                          child: _RankBoard(game: game),
                        ),
                      ),
                    ],
                  ),
                ),
                _Controls(ctrl: widget.ctrl, game: game),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 구슬 룰렛 전용 색 — 공용 HUD 팔레트([HostHud])를 그대로 쓰고,
/// 코스 요소(벽·핀·회전체)만 여기서 더한다. 원작 다크 테마의 역할 배분:
/// 벽은 흰빛, 핀은 노랑, 회전체는 시안. 구슬 색은 서버 팔레트가 정본.
class _CommandBar extends StatelessWidget {
  const _CommandBar({required this.game});

  final MarbleGame game;

  @override
  Widget build(BuildContext context) {
    final total = game.world!.marbles.length;
    final done = game.world!.ranking.length;
    final goal = game.winnerRank == 'last' ? '꼴찌 뽑기' : '1등 뽑기';
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
            '구슬 룰렛',
            style: TextStyle(
              color: HostHud.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 14),
          Text(goal, style: const TextStyle(color: HostHud.dim, fontSize: 13)),
          const Spacer(),
          Text(
            '$done / $total 도착',
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

class _RankBoard extends StatelessWidget {
  const _RankBoard({required this.game});

  final MarbleGame game;

  @override
  Widget build(BuildContext context) {
    final ranking = game.world!.ranking;
    final pending = game.world!.marbles.where((m) => !m.finished).toList()
      ..sort((a, b) => b.y.compareTo(a.y));

    return Container(
      decoration: BoxDecoration(
        color: HostHud.panel,
        border: Border.all(color: HostHud.line, width: 1.5),
      ),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '도착 순서',
            style: TextStyle(
              color: HostHud.ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: HostHud.line, height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 10),
              children: [
                for (final m in ranking)
                  _RankRow(
                    marble: m,
                    highlight: game.finished && _isPicked(m, ranking),
                  ),
                if (pending.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
                    child: Text(
                      // 출발 전에도 "달리는 중" 이라고 적혀 있었다 — 바로
                      // 아래에서는 "출발을 누르면 시작합니다" 라고 하는데.
                      game.running ? '달리는 중' : '출발 대기',
                      style: const TextStyle(color: HostHud.dim, fontSize: 12),
                    ),
                  ),
                  for (final m in pending) _RankRow(marble: m),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isPicked(Marble m, List<Marble> ranking) =>
      game.winnerRank == 'last' ? m == ranking.last : m == ranking.first;
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.marble, this.highlight = false});

  final Marble marble;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: highlight ? HostHud.sky : HostHud.plate,
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              marble.rank == null ? '·' : '${marble.rank}',
              style: TextStyle(
                color: highlight ? Colors.white : HostHud.dim,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: BoardPalette.of(marble.index),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              marble.nickname,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: highlight ? Colors.white : HostHud.ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            marble.tag,
            style: TextStyle(
              color: highlight ? Colors.white70 : HostHud.dim,
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 아래 조작줄 — 출발/건너뛰기/끝내기와 당첨 발표.
class _Controls extends StatelessWidget {
  const _Controls({required this.ctrl, required this.game});

  final HostController ctrl;
  final MarbleGame game;

  @override
  Widget build(BuildContext context) {
    final ranking = game.world!.ranking;
    final picked = game.finished
        ? (game.winnerRank == 'last' ? ranking.last : ranking.first)
        : null;

    return Container(
      color: HostHud.plate,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(
        children: [
          if (picked != null) ...[
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: BoardPalette.of(picked.index),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${picked.nickname} 당첨',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '  ${picked.tag}',
              style: const TextStyle(color: HostHud.dim, fontSize: 13),
            ),
          ] else
            Text(
              game.running ? '굴러가는 중…' : '출발을 누르면 시작합니다',
              style: const TextStyle(color: HostHud.dim, fontSize: 14),
            ),
          const Spacer(),
          if (!game.running && !game.finished)
            FilledButton(
              onPressed: ctrl.games.launchMarble,
              style: FilledButton.styleFrom(
                backgroundColor: HostHud.sky,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 16,
                ),
              ),
              child: const Text(
                '출발',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          if (game.running)
            TextButton(
              onPressed: ctrl.games.skipMarble,
              child: const Text(
                '건너뛰고 결과 보기',
                style: TextStyle(color: HostHud.ink),
              ),
            ),
          if (game.finished)
            FilledButton(
              onPressed: ctrl.games.restartMarble,
              style: FilledButton.styleFrom(
                backgroundColor: HostHud.sky,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
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
