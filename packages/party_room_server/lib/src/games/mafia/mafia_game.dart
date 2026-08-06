import 'dart:math';

import '../../game_module.dart';
import '../../player.dart';
import '../../voting.dart';
import 'mafia_member.dart';
import 'mafia_role.dart';

export 'mafia_member.dart';
export 'mafia_role.dart';

/// 게임 2호: 마피아 (확장 역할 포함).
///
/// 상태머신: 역할배정 → (밤 → 낮발표 → 토론/투표 → 처형)* → 승리판정.
/// 밤 행동은 각자 폰에서 비밀리에. 확장 역할은 인원수에 따라 자동 편성.
///
/// 역할표는 [MafiaRole]·[MafiaComposition], 참가자 상태는 [MafiaMember],
/// 투표 집계는 [VoteBox] 로 분리했다 — 이 파일은 진행 순서만 다룬다.
class MafiaGame implements GameModule {
  static const gameId = 'mafia';

  @override
  String get id => gameId;
  @override
  String get name => '마피아';
  @override
  int get minPlayers => 4;
  @override
  int get maxPlayers => 20;

  /// 그 판의 대화가 곧 게임이다 — 밤낮 발언·의심이 전부 여기 남는다.
  @override
  bool get ownsSection => true;

  final List<MafiaMember> _members = [];
  MafiaPhase phase = MafiaPhase.night;
  int round = 1;

  // 밤 행동 수집
  String? _mafiaTarget;
  String? _doctorSave;
  String? _sniperTarget;
  final Set<String> _nightDone = {};

  /// 이번 밤에 행동해야 하는 사람들 — [beginNight] 에서 한 번 확정한다.
  /// 진행률을 매번 다시 계산하면 1회성 역할(저격수·기자)이 행동 직후 소진 처리되어
  /// 분모에서 빠지는데, 분자([_nightDone])에는 남아 "3/2" 같은 표시가 나온다.
  final Set<String> _nightActors = {};

  /// 낮 투표.
  final VoteBox _votes = VoteBox();

  // ---- 호스트 규칙 ----
  /// 확장 역할(군인·영매·스파이·저격수·기자·정치인·연인) 편성 여부.
  bool extendedRoles = true;

  /// 동표일 때 처형할지. 기본은 무처형(표준 룰).
  bool executeOnTie = false;

  String lastAnnouncement = '';
  String? _pendingReport; // 기자 취재 결과 (다음 낮 발표)

  /// 살아 있는 사람 수 — 진행 상황을 기계가 읽을 때 쓴다.
  int get aliveCount => _members.where((m) => m.alive).length;

  /// 이 판의 명단 — 누가 살아 있고 무슨 역할인지.
  ///
  /// 사회자 화면이 이것을 읽는다. 예전에는 시작 이벤트로 받은 이름→역할
  /// 사본만 들고 있어서 **누가 죽었는지 화면에서 알 수 없었다** — 정작
  /// "남은 사람은…" 을 말해야 하는 사람이 그걸 못 봤다. 사본은 늘 늦으니
  /// 판정의 정본인 여기서 바로 읽는다.
  List<MafiaMember> get members => List.unmodifiable(_members);

  /// 편성표 회귀 테스트용 — 규칙 검사는 [MafiaComposition] 를 직접 봐도 된다.
  static List<MafiaRole> compositionForTest(int n) =>
      MafiaComposition.forPlayerCount(n);

  @override
  void applyRules(Map<String, dynamic> rules) {
    extendedRoles = rules['extendedRoles'] as bool? ?? true;
    executeOnTie = rules['executeOnTie'] as bool? ?? false;
  }

  // ---- 시작: 역할 배정 ----

  @override
  void start(GameContext ctx) {
    _members.clear();
    final players = ctx.players().where((p) => p.connected).toList();
    final n = players.length;
    final roles = MafiaComposition.forPlayerCount(n, extended: extendedRoles)
      ..shuffle(Random.secure());

    for (var i = 0; i < n; i++) {
      _members.add(
        MafiaMember(
          players[i].sessionToken,
          players[i].tag,
          players[i].nickname,
          roles[i],
        ),
      );
    }

    final mafiaTeamNames = _members
        .where((m) => m.role.isMafiaTeam)
        .map((m) => '${m.nickname}(${m.role.label})')
        .toList();
    final loverNames = _members
        .where((m) => m.role == MafiaRole.lover)
        .map((m) => m.nickname)
        .toList();

    for (final m in _members) {
      ctx.sendTo(m.sessionToken, {
        'type': 'scene',
        'scene': 'mafia_role',
        'role': m.role.name,
        'roleLabel': m.role.label,
        'roleDesc': m.role.description,
        // 마피아 팀(마피아+스파이)에게 동료 공개
        if (m.role.isMafiaTeam) 'mates': mafiaTeamNames,
        // 연인끼리 서로 공개
        if (m.role == MafiaRole.lover) 'lovers': loverNames,
      });
    }
    ctx.onGameEvent('mafia_started', {
      'players': n,
      'roles': {for (final m in _members) m.nickname: m.role.label},
    });
    phase = MafiaPhase.night;
  }

  // ---- 페이즈 전환 (호스트 UI에서 호출) ----

  /// 판이 끝났으면 더 못 움직인다.
  ///
  /// 예전에는 `ended` 인 판에도 밤·낮·투표가 그대로 먹혀서, 승패가 갈린 뒤에
  /// 호스트가 버튼을 한 번 더 누르면 **사람이 또 죽고** 승리 화면이 덮여
  /// 씌워졌다. 실제로 굴려 보니 남은 2명이 1명이 될 때까지 계속 죽었다.
  bool get isOver => phase == MafiaPhase.ended;

  void beginNight(GameContext ctx) {
    if (isOver) return;
    phase = MafiaPhase.night;
    _mafiaTarget = null;
    _doctorSave = null;
    _sniperTarget = null;
    _nightDone.clear();
    _nightActors.clear();
    final aliveList = _aliveSnapshot();
    final deadList = _deadSnapshot();
    final anyDead = deadList.isNotEmpty;

    for (final m in _members) {
      if (!m.alive) continue;
      final canAct = m.canActAtNight(anyDead: anyDead);
      if (canAct) _nightActors.add(m.sessionToken);
      final targets = m.role == MafiaRole.medium
          ? deadList // 영매는 죽은 자 대상
          : aliveList.where((t) => t['tag'] != m.tag).toList();
      ctx.sendTo(m.sessionToken, {
        'type': 'scene',
        'scene': 'mafia_night',
        'round': round,
        'role': m.role.name,
        'roleLabel': m.role.label,
        'canAct': canAct,
        'targets': canAct ? targets : <Map<String, dynamic>>[],
      });
    }
    _pushDead(ctx);
    ctx.onGameEvent('mafia_phase', {'phase': 'night', 'round': round});
  }

  bool _canActAtNight(MafiaMember m) =>
      m.canActAtNight(anyDead: _members.any((o) => !o.alive));

  void beginDay(GameContext ctx) {
    if (isOver) return;
    // ---- 밤 결과 판정 ----
    final events = <String>[];

    // 1) 저격수 필살 (의사 보호 무시 — "무조건")
    if (_sniperTarget != null) {
      final victim = _byToken(_sniperTarget!);
      if (victim != null && victim.alive) {
        victim.alive = false;
        events.add('${victim.nickname} 님이 저격당했습니다!');
        _cascadeLover(victim, events);
      }
    }

    // 2) 마피아 공격 (의사 보호 / 군인 방탄 판정)
    final target = _mafiaTarget;
    if (target != null) {
      final victim = _byToken(target);
      if (victim != null && victim.alive) {
        if (target == _doctorSave) {
          events.add('의사의 활약으로 누군가 목숨을 건졌습니다!');
        } else if (victim.role == MafiaRole.soldier && !victim.shieldUsed) {
          victim.shieldUsed = true;
          events.add('${victim.nickname} 님이 공격을 버텨냈습니다! (군인의 방탄)');
        } else {
          victim.alive = false;
          events.add('${victim.nickname} 님이 밤사이 희생되었습니다.');
          _cascadeLover(victim, events);
        }
      }
    }

    if (events.isEmpty) events.add('조용한 밤이었습니다.');

    // 3) 기자 취재 발표
    if (_pendingReport != null) {
      events.add(_pendingReport!);
      _pendingReport = null;
    }

    final announcement = events.join('\n');
    lastAnnouncement = announcement;
    phase = MafiaPhase.day;

    final winner = _checkWin();
    if (winner != null) {
      _endGame(ctx, winner, extra: announcement);
      return;
    }

    _broadcastDay(ctx, announcement);
    ctx.onGameEvent('mafia_phase', {
      'phase': 'day',
      'round': round,
      'announcement': announcement,
    });
  }

  /// 연인 동반 사망.
  void _cascadeLover(MafiaMember dead, List<String> events) {
    if (dead.role != MafiaRole.lover) return;
    for (final m in _members) {
      if (m.role == MafiaRole.lover &&
          m.alive &&
          m.sessionToken != dead.sessionToken) {
        m.alive = false;
        events.add('${m.nickname} 님이 연인의 뒤를 따랐습니다…');
      }
    }
  }

  void beginVote(GameContext ctx) {
    if (isOver) return;
    phase = MafiaPhase.vote;
    _votes.clear();
    for (final m in _members) {
      if (!m.alive) continue;
      ctx.sendTo(m.sessionToken, {
        'type': 'scene',
        'scene': 'mafia_vote',
        'round': round,
        'targets': _aliveSnapshot().where((t) => t['tag'] != m.tag).toList(),
      });
    }
    ctx.onGameEvent('mafia_phase', {'phase': 'vote', 'round': round});
  }

  void closeVote(GameContext ctx) {
    if (isOver) return;
    // 집계 (정치인 2표) → 최다득표 처형, 동표면 무처형.
    final tally = _votes.tally(
      weightOf: (voter) => _byToken(voter)?.role.voteWeight ?? 1,
    );
    final events = <String>[];
    if (tally.top == null) {
      events.add('아무도 투표하지 않아 처형이 없습니다.');
    } else if (tally.isTie && !executeOnTie) {
      events.add('동표로 처형이 없습니다.');
    } else {
      final executed = _byToken(tally.top!);
      if (executed != null) {
        executed.alive = false;
        final wasMafiaTeam = executed.role.isMafiaTeam;
        events.add(
          '${executed.nickname} 님이 처형되었습니다. ${wasMafiaTeam ? "${executed.role.label}이었습니다!" : "마피아가 아니었습니다…"}',
        );
        _cascadeLover(executed, events);
      }
    }
    final announcement = events.join('\n');
    lastAnnouncement = announcement;

    final winner = _checkWin();
    if (winner != null) {
      _endGame(ctx, winner, extra: announcement);
      return;
    }

    round++;
    _broadcastDay(ctx, announcement);
    ctx.onGameEvent('mafia_phase', {
      'phase': 'vote_closed',
      'round': round,
      'announcement': announcement,
    });
  }

  /// 낮 장면을 전원에게. 생존 여부만 개인별로 다르다.
  void _broadcastDay(GameContext ctx, String announcement) {
    for (final m in _members) {
      ctx.sendTo(m.sessionToken, {
        'type': 'scene',
        'scene': 'mafia_day',
        'round': round,
        'announcement': announcement,
        'alive': m.alive,
        'players': _aliveSnapshot(),
      });
    }
    _pushDead(ctx);
  }

  // ---- 참가자 메시지 ----

  @override
  void onMessage(GameContext ctx, Player from, Map<String, dynamic> msg) {
    final me = _byToken(from.sessionToken);
    if (me == null || !me.alive) return;

    switch (msg['type']) {
      case 'mafia_night_act':
        if (phase != MafiaPhase.night) return;
        // 참가자는 공개 태그로 지목한다. 여기서만 세션으로 푼다 —
        // 내부 상태(_mafiaTarget 등)와 저장 포맷은 세션 기준 그대로다.
        final target = _byTag(msg['target'] as String?)?.sessionToken;
        if (target == null) return;
        if (!_canActAtNight(me)) return;
        _applyNightAct(ctx, me, target);

        _nightDone.add(me.sessionToken);
        ctx.sendTo(me.sessionToken, {'type': 'mafia_act_ack'});
        ctx.onGameEvent('mafia_night_progress', {
          'done': _nightDone.intersection(_nightActors).length,
          'total': _nightActors.length,
          'allDone': _nightDone.containsAll(_nightActors),
          // 누구를 재촉할지 알아야 진행이 된다 — 숫자만으로는 부족하다.
          'pending': _nightActors
              .where((t) => !_nightDone.contains(t))
              .map((t) => _byToken(t)?.nickname ?? '?')
              .toList(),
          'doneNames': _nightDone
              .intersection(_nightActors)
              .map((t) => _byToken(t)?.nickname ?? '?')
              .toList(),
        });

      case 'mafia_vote':
        if (phase != MafiaPhase.vote) return;
        final target = _byTag(msg['target'] as String?)?.sessionToken;
        if (target == null) return;
        _votes.cast(me.sessionToken, target);
        ctx.sendTo(me.sessionToken, {'type': 'mafia_vote_ack'});
        final aliveCount = _members.where((m) => m.alive).length;
        ctx.onGameEvent('mafia_vote_progress', {
          'voted': _votes.length,
          'total': aliveCount,
        });
    }
  }

  /// 역할별 밤 행동 적용. 조사 계열은 즉시 결과를 본인에게만 돌려준다.
  void _applyNightAct(GameContext ctx, MafiaMember me, String target) {
    final checked = _byToken(target);
    switch (me.role) {
      case MafiaRole.mafia:
        _mafiaTarget = target;
      case MafiaRole.doctor:
        _doctorSave = target;
      case MafiaRole.police:
        ctx.sendTo(me.sessionToken, {
          'type': 'mafia_police_result',
          'nickname': checked?.nickname,
          'isMafia': checked?.role == MafiaRole.mafia,
        });
      case MafiaRole.spy:
        ctx.sendTo(me.sessionToken, {
          'type': 'mafia_spy_result',
          'nickname': checked?.nickname,
          'roleLabel': checked?.role.label,
        });
      case MafiaRole.sniper:
        _sniperTarget = target;
        me.sniperUsed = true;
      case MafiaRole.medium:
        if (checked != null && !checked.alive) {
          ctx.sendTo(me.sessionToken, {
            'type': 'mafia_medium_result',
            'nickname': checked.nickname,
            'roleLabel': checked.role.label,
          });
        }
      case MafiaRole.reporter:
        me.reportUsed = true;
        if (checked != null) {
          _pendingReport =
              '📰 기자의 특종! ${checked.nickname} 님의 정체는 [${checked.role.label}]입니다!';
        }
      default:
        return;
    }
  }

  // ---- 재접속 ----

  @override
  void onReconnect(GameContext ctx, Player player) {
    final me = _byToken(player.sessionToken);
    if (me == null) return;
    switch (phase) {
      case MafiaPhase.night:
        final canAct = me.alive && _canActAtNight(me);
        final targets = me.role == MafiaRole.medium
            ? _deadSnapshot()
            : _aliveSnapshot().where((t) => t['tag'] != me.tag).toList();
        ctx.sendTo(me.sessionToken, {
          'type': 'scene',
          'scene': 'mafia_night',
          'round': round,
          'role': me.role.name,
          'roleLabel': me.role.label,
          'canAct': canAct,
          'targets': canAct ? targets : <Map<String, dynamic>>[],
        });
      case MafiaPhase.day:
        ctx.sendTo(me.sessionToken, {
          'type': 'scene',
          'scene': 'mafia_day',
          'round': round,
          'announcement': lastAnnouncement,
          'alive': me.alive,
          'players': _aliveSnapshot(),
        });
      case MafiaPhase.vote:
        if (me.alive) {
          ctx.sendTo(me.sessionToken, {
            'type': 'scene',
            'scene': 'mafia_vote',
            'round': round,
            'targets': _aliveSnapshot()
                .where((t) => t['tag'] != me.tag)
                .toList(),
          });
        }
      case MafiaPhase.ended:
        break;
    }
  }

  // ---- 승리 판정 (마피아 팀 = mafia+spy) ----

  String? _checkWin() {
    final aliveMafia = _members
        .where((m) => m.alive && m.role == MafiaRole.mafia)
        .length; // 실제 킬 능력자 기준
    final aliveMafiaTeam = _members
        .where((m) => m.alive && m.role.isMafiaTeam)
        .length;
    final aliveOthers = _members
        .where((m) => m.alive && !m.role.isMafiaTeam)
        .length;
    if (aliveMafia == 0) return 'citizen'; // 마피아 전멸 (스파이만 남으면 시민 승)
    if (aliveMafiaTeam >= aliveOthers) return 'mafia';
    return null;
  }

  void _endGame(GameContext ctx, String winner, {String? extra}) {
    phase = MafiaPhase.ended;
    final reveal = _members
        .map(
          (m) => {
            'tag': m.tag,
            'nickname': m.nickname,
            'role': m.role.label,
            'alive': m.alive,
          },
        )
        .toList();
    ctx.broadcast({
      'type': 'scene',
      'scene': 'mafia_end',
      'winner': winner,
      'extra': extra ?? '',
      'reveal': reveal,
    });
    ctx.onGameEvent('mafia_ended', {'winner': winner});
  }

  // ---- 유틸 ----

  /// 공개 태그로 찾는다 — 참가자가 보낸 지목을 푸는 유일한 통로.
  MafiaMember? _byTag(String? tag) {
    if (tag == null) return null;
    for (final m in _members) {
      if (m.tag == tag) return m;
    }
    return null;
  }

  MafiaMember? _byToken(String token) {
    for (final m in _members) {
      if (m.sessionToken == token) return m;
    }
    return null;
  }

  /// 참가자에게 보내는 명단 — **세션 토큰은 싣지 않는다.**
  /// 지목은 공개 태그로 받고 서버가 [_byTag] 로 푼다(roster.dart 의 같은 이유).
  List<Map<String, dynamic>> _aliveSnapshot() => _members
      .where((m) => m.alive)
      .map((m) => {'tag': m.tag, 'nickname': m.nickname})
      .toList();

  List<Map<String, dynamic>> _deadSnapshot() => _members
      .where((m) => !m.alive)
      .map((m) => {'tag': m.tag, 'nickname': m.nickname})
      .toList();

  void _pushDead(GameContext ctx) {
    for (final m in _members.where((m) => !m.alive)) {
      ctx.sendTo(m.sessionToken, {
        'type': 'scene',
        'scene': 'mafia_dead',
        'players': _aliveSnapshot(),
      });
    }
  }

  @override
  void end(GameContext ctx) {
    phase = MafiaPhase.ended;
  }

  // ---- 저장/복구 ----

  @override
  Map<String, dynamic> toJson() => {
    'phase': phase.name,
    'round': round,
    'lastAnnouncement': lastAnnouncement,
    'pendingReport': _pendingReport,
    // 규칙도 실어야 앱 재시작 후 같은 규칙으로 이어진다.
    'extendedRoles': extendedRoles,
    'executeOnTie': executeOnTie,
    'members': _members.map((m) => m.toJson()).toList(),
  };

  @override
  void restore(GameContext ctx, Map<String, dynamic> json) {
    phase = MafiaPhase.values.byName(json['phase'] as String? ?? 'night');
    round = json['round'] as int? ?? 1;
    lastAnnouncement = json['lastAnnouncement'] as String? ?? '';
    _pendingReport = json['pendingReport'] as String?;
    extendedRoles = json['extendedRoles'] as bool? ?? true;
    executeOnTie = json['executeOnTie'] as bool? ?? false;
    _members
      ..clear()
      ..addAll(
        (json['members'] as List<dynamic>? ?? []).map(
          (j) => MafiaMember.fromJson(j as Map<String, dynamic>),
        ),
      );
  }
}
