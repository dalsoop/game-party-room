import 'dart:math';

import '../../game_module.dart';
import '../../player.dart';
import '../../roster.dart';
import '../palette.dart';
import 'marble_course.dart';
import 'marble_world.dart';

/// 구슬 룰렛 — 참가자 한 명이 구슬 하나가 되어 코스를 굴러 내려간다.
///
/// **이 종목은 참가자 입력이 없다.** 마피아·라이어·투표는 폰이 고르고 서버가
/// 집계하지만, 여기서는 호스트 화면이 본체고 폰은 "내 구슬은 몇 번" 과 결과만
/// 본다. 그래서 [onMessage] 가 비어 있다 — 실수가 아니라 이 게임의 성격이다.
///
/// 뽑기 도구로 쓰라고 만든 종목이다: 벌칙자·발표 순서·다음 게임 순서를
/// 정할 때 "그냥 정하자" 보다 판이 하나 서는 편이 훨씬 낫다.
class MarbleGame implements GameModule {
  static const gameId = 'marble';

  /// 구슬 번호 = 색 번호. 정본은 공용 팔레트([partyPalette]) — 사다리타기와
  /// 같은 표를 쓴다.
  static const List<String> palette = partyPalette;

  @override
  String get id => gameId;
  @override
  String get name => '구슬 룰렛';
  @override
  int get minPlayers => 2;
  @override
  int get maxPlayers => 20;

  /// 뽑기 결과와 그때의 반응(스크린샷·환호)이 판별로 남을 값어치가 있다.
  @override
  bool get ownsSection => true;

  /// 1등을 뽑을지 꼴찌를 뽑을지. 벌칙자는 꼴찌, 순서 정하기는 1등이 편하다.
  String winnerRank = 'first';

  /// 진행 속도 배수. 20명이면 판이 길어져서 호스트가 줄일 수 있어야 한다.
  double speed = 1.0;

  /// 어느 코스로 굴릴지. 좌표는 [MarbleCourses] 에 선언으로 있다.
  String courseId = MarbleCourses.defaultId;

  final GameRoster roster = GameRoster();

  MarbleWorld? _world;
  MarbleWorld? get world => _world;

  int _seed = 0;
  int get seed => _seed;

  bool _started = false;
  bool _announced = false;

  /// 시뮬레이션이 끝나 순위가 확정됐는가.
  bool get finished => _announced;

  @override
  void applyRules(Map<String, dynamic> rules) {
    final w = rules['winnerRank'];
    if (w == 'first' || w == 'last') winnerRank = w as String;
    // 설정 화면은 ChoiceRule 로 문자열을 넘기고, 테스트·복원은 숫자를 넘긴다.
    final s = rules['speed'];
    final parsed = s is num ? s.toDouble() : double.tryParse('$s');
    if (parsed != null && parsed > 0) speed = parsed;
    // 모르는 코스 id 면 기본으로 떨어진다 — 옛 저장분·오타에 판이 안 열리면
    // 안 된다.
    final c = rules['course'];
    if (c is String && MarbleCourses.ids.contains(c)) courseId = c;
  }

  @override
  void start(GameContext ctx) {
    roster.seatConnected(ctx);
    _seed = DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF;
    _build();
    _started = false;
    _announced = false;

    // 각자에게 자기 구슬만 알려준다. 남의 번호까지 폰에 뿌리면 큰 화면을
    // 안 보고 폰만 들여다보게 된다 — 이 게임은 같이 보는 맛이 전부다.
    for (final m in _world!.marbles) {
      ctx.sendTo(_sessionOf(m), {
        'type': 'scene',
        'scene': 'marble_ready',
        'index': m.index,
        'color': colorOf(m.index),
        'nickname': m.nickname,
        'total': _world!.marbles.length,
        'goal': winnerRank,
      });
    }
    ctx.onGameEvent('marble_ready', {
      'count': _world!.marbles.length,
      'seed': _seed,
      'course': courseId,
    });
  }

  /// 구슬을 만들어 출발 대기열에 쌓는다.
  ///
  /// 출발 순서는 시드로 섞는다. 명단 순서 그대로 두면 먼저 입장한 사람이
  /// 늘 같은 자리에서 시작해 "자리빨" 이 생긴다. 자리 자체는 코스가 정한다
  /// ([MarbleTrack.spawnPoint]) — 원작처럼 좁은 통로의 격자다.
  void _build() {
    final rng = Random(_seed);
    final seats = roster.seats.toList()..shuffle(rng);
    final track = MarbleCourses.byId(courseId).build();

    final marbles = <Marble>[];
    for (var i = 0; i < seats.length; i++) {
      final (x, y) = track.spawnPoint(i, rng);
      marbles.add(
        Marble(
          index: i,
          nickname: seats[i].nickname,
          tag: seats[i].tag,
          x: x,
          y: y,
        ),
      );
    }
    _world = MarbleWorld(track: track, marbles: marbles, seed: _seed);
  }

  String _sessionOf(Marble m) {
    for (final s in roster.seats) {
      if (s.tag == m.tag) return s.session;
    }
    return '';
  }

  static String colorOf(int index) => palette[index % palette.length];

  /// 호스트가 [출발] 을 누르면 굴러가기 시작한다.
  void launch(GameContext ctx) {
    if (_started || _world == null) return;
    _started = true;
    ctx.broadcast({'type': 'marble_start'});
    ctx.onGameEvent('marble_running', {});
  }

  bool get running => _started && !_announced;

  /// 당첨이 이미 결정됐는가 — 1등 뽑기는 1등이 들어온 순간, 꼴찌 뽑기는
  /// 하나만 남은 순간(그 구슬이 꼴찌)이다.
  ///
  /// 결정됐다고 판을 즉시 마감하면 안 된다 — 그 프레임에 남은 구슬이 전부
  /// 사라지며 발표가 떠서 "부딪히더니 갑자기 1등" 으로 보인다(실기 피드백).
  /// 결정 뒤에는 호스트가 이 플래그를 보고 **빨리감기로 남은 구슬을 자연스럽게
  /// 들여보낸 뒤**, 완주 시점에 발표한다. 클로즈업·슬로모도 결정 전까지만.
  bool get decided =>
      _world != null &&
      (winnerRank == 'last'
          ? _world!.remaining <= 1
          : _world!.ranking.isNotEmpty);

  /// 호스트 화면의 프레임마다 불린다. 전원이 완주하면 발표한다.
  ///
  /// 시뮬레이션을 화면 쪽에서 돌리지만 **결과의 주인은 여전히 서버 모듈**이다.
  /// 호스트는 시간을 흘려보낼 뿐 순위를 만들지 않는다.
  void tick(GameContext ctx, double dt) {
    if (!running) return;
    _world!.advance(dt * speed);
    if (_world!.done) _announce(ctx);
  }

  /// 화면 없이 끝까지 돌린다(헤드리스·테스트·호스트가 건너뛰기를 누른 경우).
  void skipToEnd(GameContext ctx) {
    if (_world == null || _announced) return;
    _started = true;
    _world!.runToCompletion();
    _announce(ctx);
  }

  void _announce(GameContext ctx) {
    if (_announced) return;
    _announced = true;

    final ranking = _world!.ranking;
    final rows = ranking
        .map(
          (m) => {
            'rank': m.rank,
            'index': m.index,
            'color': colorOf(m.index),
            'nickname': m.nickname,
            'tag': m.tag,
          },
        )
        .toList();
    final picked = winnerRank == 'last' ? ranking.last : ranking.first;

    ctx.broadcast({
      'type': 'scene',
      'scene': 'marble_result',
      'goal': winnerRank,
      'winner': {
        'index': picked.index,
        'color': colorOf(picked.index),
        'nickname': picked.nickname,
        'tag': picked.tag,
        'rank': picked.rank,
      },
      'ranking': rows,
      // 시드를 같이 공개한다. 뽑기 도구로 쓰는 이상 "어떻게 나온 결과냐" 에
      // 답할 수 있어야 한다 — 같은 시드는 같은 순위를 만든다.
      'seed': _seed,
    });
    ctx.onGameEvent('marble_done', {
      'winner': picked.nickname,
      'rank': picked.rank,
    });
  }

  @override
  void onMessage(GameContext ctx, Player from, Map<String, dynamic> msg) {
    // 참가자가 보낼 것이 없다 — 이 종목은 관전형이다.
  }

  @override
  void onReconnect(GameContext ctx, Player player) {
    final w = _world;
    if (w == null) return;
    if (_announced) {
      // 결과가 이미 나왔으면 결과를 다시 보낸다.
      _resendResult(ctx, player);
      return;
    }
    for (final m in w.marbles) {
      if (_sessionOf(m) != player.sessionToken) continue;
      ctx.sendTo(player.sessionToken, {
        'type': 'scene',
        'scene': 'marble_ready',
        'index': m.index,
        'color': colorOf(m.index),
        'nickname': m.nickname,
        'total': w.marbles.length,
        'goal': winnerRank,
      });
      return;
    }
  }

  void _resendResult(GameContext ctx, Player player) {
    final ranking = _world!.ranking;
    final picked = winnerRank == 'last' ? ranking.last : ranking.first;
    ctx.sendTo(player.sessionToken, {
      'type': 'scene',
      'scene': 'marble_result',
      'goal': winnerRank,
      'winner': {
        'index': picked.index,
        'color': colorOf(picked.index),
        'nickname': picked.nickname,
        'tag': picked.tag,
        'rank': picked.rank,
      },
      'ranking': ranking
          .map(
            (m) => {
              'rank': m.rank,
              'index': m.index,
              'color': colorOf(m.index),
              'nickname': m.nickname,
              'tag': m.tag,
            },
          )
          .toList(),
      'seed': _seed,
    });
  }

  @override
  void end(GameContext ctx) {
    _world = null;
    _started = false;
    _announced = false;
  }

  /// 저장은 "판이 시작되기 전" 까지만 의미가 있다.
  ///
  /// 굴러가는 중에 앱이 꺼졌다면 그 판은 끝난 판이 아니다. 물리 상태를
  /// 통째로 저장했다가 되살리는 것보다, 같은 명단·같은 시드로 처음부터 다시
  /// 굴리는 편이 정직하다(결과도 같다).
  @override
  Map<String, dynamic> toJson() => {
    'winnerRank': winnerRank,
    'speed': speed,
    'course': courseId,
    'seed': _seed,
    'roster': roster.toJson(),
    'announced': _announced,
    if (_announced)
      'ranking': _world!.ranking
          .map((m) => {'rank': m.rank, 'index': m.index, 'tag': m.tag})
          .toList(),
  };

  @override
  void restore(GameContext ctx, Map<String, dynamic> json) {
    final w = json['winnerRank'];
    if (w == 'first' || w == 'last') winnerRank = w as String;
    final s = json['speed'];
    if (s is num && s > 0) speed = s.toDouble();
    // 코스가 달라지면 같은 시드라도 다른 순위가 나온다 — 반드시 같이 복구한다.
    final c = json['course'];
    if (c is String && MarbleCourses.ids.contains(c)) courseId = c;
    _seed = (json['seed'] as num?)?.toInt() ?? 0;
    roster.restore(json['roster'] as List<dynamic>?);
    if (roster.isEmpty) return;

    _build();
    _announced = false;
    _started = false;
    if (json['announced'] == true) {
      // 같은 시드·같은 명단이므로 다시 돌리면 저장된 순위가 그대로 재현된다.
      _world!.runToCompletion();
      _started = true;
      _announced = true;
    }
  }
}
