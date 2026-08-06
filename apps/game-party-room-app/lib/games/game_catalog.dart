import 'package:party_room_server/party_room_server.dart';
import 'package:flutter/widgets.dart';

import '../host_controller.dart';
import '../pages/liar_page.dart';
import '../pages/mafia_page.dart';
import '../pages/ladder_page.dart';
import '../pages/marble_page.dart';
import '../pages/poll_page.dart';
import '../settings/game_rule_spec.dart';

/// 로비에 걸리는 게임 한 종목의 소개와 진입 방법.
///
/// 예전에는 배너 문구·최소 인원·시작 방법이 `lobby_page.dart` 에 손으로 나열돼 있고,
/// 상태 문구는 `host_controller` 의 case 10개에 흩어져 있었다. 게임을 하나 늘릴 때마다
/// 서로 떨어진 네 곳을 같이 고쳐야 했고, `GameModule` 이 이미 들고 있는
/// `name`·`minPlayers` 는 아무도 쓰지 않았다.
class GameEntry {
  const GameEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.bannerAsset,
    required this.open,
    required this.livePage,
    this.status,
    this.restoredStatus,
    this.rules = const [],
  });

  final String id;
  final String title;
  final String subtitle;
  final String bannerAsset;

  /// 로비에서 이 게임을 눌렀을 때. 설정이 필요한 게임은 자체 플로우를 연다.
  final void Function(BuildContext context, HostController ctrl) open;

  /// **진행 중인 판**의 화면. 새 판을 시작하지 않고 보던 곳으로 돌아간다.
  ///
  /// 이게 없으면 로비가 종목을 하나씩 알아야 한다 — 예전에는 마피아·라이어·
  /// 투표만 손으로 나열돼 있어서, 구슬·사다리는 판이 돌고 있어도 돌아갈
  /// 길이 없었다(앱을 다시 켜면 로비에 떨어진 채 참가자만 기다렸다).
  final Widget Function(HostController ctrl) livePage;

  /// 이 종목이 지금 돌고 있는가 — 판정 근거는 서버의 활성 모듈 하나뿐이다.
  bool isLive(HostController ctrl) => ctrl.room?.activeGame?.id == id;

  /// 게임 이벤트를 호스트 상태 문구로 옮긴다. 모르는 이벤트면 null.
  final String? Function(String event, Map<String, dynamic> data)? status;

  /// **저장분에서 되살린 판**의 상태 문구 — 모듈의 상태에서 바로 만든다.
  ///
  /// 위 [status] 는 이벤트가 지날 때만 갱신된다. 그래서 앱을 껐다 켜면
  /// 아무 이벤트도 안 지나가 상태 줄이 빈 칸으로 남았다 — 판은 돌고 있는데
  /// 호스트 화면에는 지금 뭐 하는 중인지가 안 적혀 있었다(마피아만 예외로
  /// 손으로 채워 넣고 있었고, 구슬·사다리·라이어·투표는 그냥 비었다).
  final String? Function(GameModule game)? restoredStatus;

  /// 이 종목이 제공하는 규칙 — 설정 화면이 이걸 보고 그린다.
  final List<GameRuleSpec> rules;

  /// 이 종목의 서버 모듈(인원 제한 등 메타를 읽을 때).
  GameModuleMeta get meta {
    final m = GameRegistry.create(id)!;
    return GameModuleMeta(
      name: m.name,
      minPlayers: m.minPlayers,
      maxPlayers: m.maxPlayers,
    );
  }
}

/// 모듈이 선언한 메타의 얇은 사본 — UI 가 모듈 인스턴스를 붙들지 않게 한다.
class GameModuleMeta {
  const GameModuleMeta({
    required this.name,
    required this.minPlayers,
    required this.maxPlayers,
  });

  final String name;
  final int minPlayers;
  final int maxPlayers;
}

/// 로비에 걸 종목들. **새 게임은 여기 한 항목만 추가하면 로비에 붙는다.**
class GameCatalog {
  static final List<GameEntry> all = [
    GameEntry(
      id: MafiaGame.gameId,
      livePage: (c) => MafiaPage(ctrl: c),
      title: '마피아',
      subtitle: '4명+ · 역할 추리의 명작',
      bannerAsset: 'assets/img/card_mafia.jpg',
      open: MafiaPage.startFlow,
      status: _mafiaStatus,
      restoredStatus: _mafiaRestored,
      rules: const [
        ToggleRule(
          key: 'extendedRoles',
          label: '확장 역할 사용',
          initial: true,
          help:
              '8명 이상일 때 군인·영매·스파이·저격수 등을 편성합니다. '
              '끄면 마피아·의사·경찰·시민만 씁니다.',
        ),
        ToggleRule(
          key: 'executeOnTie',
          label: '동표에도 처형',
          initial: false,
          help: '기본은 동표면 아무도 처형하지 않습니다(표준 룰).',
        ),
      ],
    ),
    GameEntry(
      id: LiarGame.gameId,
      livePage: (c) => LiarPage(ctrl: c),
      title: '라이어 게임',
      subtitle: '3명+ · 제시어를 모르는 한 명 찾기',
      bannerAsset: 'assets/img/card_liar.jpg',
      open: LiarPage.startFlow,
      status: _liarStatus,
      restoredStatus: _liarRestored,
      rules: [
        MultiChoiceRule(
          key: 'categories',
          label: '사용할 카테고리',
          options: {for (final k in LiarGame.wordPools.keys) k: k},
          initial: LiarGame.wordPools.keys.toList(),
          help: '고른 카테고리에서만 제시어를 뽑습니다.',
        ),
      ],
    ),
    GameEntry(
      id: PollGame.gameId,
      livePage: (c) => PollPage(ctrl: c),
      title: '익명 투표',
      subtitle: '2명+ · 뭐든 몰래 정하기',
      bannerAsset: 'assets/img/card_poll.jpg',
      open: PollPage.startFlow,
      status: _pollStatus,
      restoredStatus: _pollRestored,
    ),
    GameEntry(
      id: LadderGame.gameId,
      livePage: (c) => LadderPage(ctrl: c),
      title: '사다리타기',
      subtitle: '2명+ · 한 줄씩 운명 공개',
      bannerAsset: 'assets/img/card_ladder.jpg',
      open: LadderPage.startFlow,
      status: _ladderStatus,
      restoredStatus: _ladderRestored,
    ),
    GameEntry(
      id: MarbleGame.gameId,
      livePage: (c) => MarblePage(ctrl: c),
      title: '구슬 룰렛',
      subtitle: '2명+ · 벌칙자·순서 정하기',
      bannerAsset: 'assets/img/card_marble.jpg',
      open: MarblePage.startFlow,
      status: _marbleStatus,
      restoredStatus: _marbleRestored,
      rules: const [
        // 코스 좌표는 서버 패키지의 선언(MarbleCourses)에 있고, 여기서는
        // 사람이 읽는 이름만 붙인다 — 서버는 화면 언어를 모른다.
        ChoiceRule(
          key: 'course',
          label: '코스',
          options: {'classic': '기본 (약 35초)', 'sprint': '짧게 (약 20초)'},
          initial: 'classic',
          help:
              '기본은 핀밭·바람개비를 다 지나 순위가 여러 번 뒤집힙니다. '
              '벌칙자 하나만 빨리 뽑을 땐 짧은 코스가 낫습니다.',
        ),
        ChoiceRule(
          key: 'winnerRank',
          label: '누구를 뽑을까',
          options: {'first': '1등', 'last': '꼴찌'},
          initial: 'first',
          help: '순서를 정할 땐 1등, 벌칙자를 고를 땐 꼴찌가 편합니다.',
        ),
        ChoiceRule(
          key: 'speed',
          label: '진행 속도',
          options: {'1': '보통', '1.5': '빠르게', '2': '아주 빠르게'},
          initial: '1',
          help: '고른 코스 기준입니다. 인원이 많으면 올려서 씁니다.',
        ),
      ],
    ),
  ];

  /// 지금 돌고 있는 판의 종목. 없으면 null — 로비가 이것만 보고 그린다.
  static GameEntry? liveOf(HostController ctrl) {
    for (final e in all) {
      if (e.isLive(ctrl)) return e;
    }
    return null;
  }

  static GameEntry? byId(String id) {
    for (final e in all) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// 되살린 판의 상태 문구를 종목을 몰라도 얻는다.
  static String? restoredStatusFor(GameModule game) {
    for (final e in all) {
      if (e.id != game.id) continue;
      return e.restoredStatus?.call(game);
    }
    return null;
  }

  /// 어떤 게임의 이벤트든 상태 문구로 옮긴다. 종목을 몰라도 되게 전부 물어본다.
  static String? statusFor(String event, Map<String, dynamic> data) {
    for (final e in all) {
      final s = e.status?.call(event, data);
      if (s != null) return s;
    }
    return null;
  }

  // ---- 되살린 판의 상태 문구 ----
  //
  // 이벤트가 아니라 **모듈이 들고 있는 상태**에서 만든다. 재시작 직후에는
  // 아무 이벤트도 안 지나가므로 이 길이 유일하다.

  static String? _mafiaRestored(GameModule g) {
    if (g is! MafiaGame) return null;
    final where = switch (g.phase) {
      MafiaPhase.night => '${g.round}일차 밤',
      MafiaPhase.day => '${g.round}일차 낮',
      MafiaPhase.vote => '${g.round}일차 투표 중',
      MafiaPhase.ended => '끝난 판',
    };
    return '복구됨 — $where (${g.aliveCount}명 생존)';
  }

  static String? _liarRestored(GameModule g) {
    if (g is! LiarGame) return null;
    if (g.isOver) return '복구됨 — 결과까지 공개된 판';
    final word = g.word.isEmpty ? '' : ' / [${g.category}] ${g.word}';
    return '복구됨 — ${g.voteOpen ? "지목 투표 중" : "토론 중"}$word';
  }

  static String? _pollRestored(GameModule g) {
    if (g is! PollGame) return null;
    return '복구됨 — ${g.question}';
  }

  static String? _ladderRestored(GameModule g) {
    if (g is! LadderGame) return null;
    final total = g.roster.length;
    final done = g.revealed.length;
    return done >= total && total > 0
        ? '복구됨 — 전원 공개 완료'
        : '복구됨 — 사다리 $total줄 중 $done줄 공개';
  }

  static String? _marbleRestored(GameModule g) {
    if (g is! MarbleGame) return null;
    if (g.finished) return '복구됨 — 결과가 나온 판';
    return g.running ? '복구됨 — 굴러가는 중' : '복구됨 — 출발 대기';
  }

  // ---- 종목별 상태 문구 ----

  static String? _mafiaStatus(
    String event,
    Map<String, dynamic> data,
  ) => switch (event) {
    'mafia_started' => '역할 배정 완료',
    'mafia_phase' => switch (data['phase'] as String?) {
      'night' => '${data['round']}일차 밤',
      'day' => '${data['round']}일차 낮',
      'vote' => '투표 중',
      'vote_closed' => '투표 결과 발표',
      _ => '',
    },
    'mafia_night_progress' =>
      '밤 행동 ${data['done']}/${data['total']}${data['allDone'] == true ? ' — 전원 완료!' : ''}',
    'mafia_vote_progress' => '투표 ${data['voted']}/${data['total']}',
    'mafia_ended' => data['winner'] == 'mafia' ? '마피아 승리!' : '시민 승리!',
    _ => null,
  };

  static String? _liarStatus(String event, Map<String, dynamic> data) =>
      switch (event) {
        'liar_started' =>
          '라이어: ${data['liar']} / [${data['category']}] ${data['word']}',
        'liar_vote_progress' => '지목 ${data['voted']}/${data['total']}',
        'liar_ended' => data['caught'] == true ? '라이어 검거!' : '라이어 승리!',
        _ => null,
      };

  static String? _ladderStatus(
    String event,
    Map<String, dynamic> data,
  ) => switch (event) {
    'ladder_ready' => '사다리 ${data['count']}줄 — 공개 대기',
    'ladder_reveal' =>
      '${data['nickname']} → ${data['outcome']} (${data['done']}/${data['total']})',
    'ladder_end' => '사다리 전원 공개 완료',
    _ => null,
  };

  static String? _marbleStatus(String event, Map<String, dynamic> data) =>
      switch (event) {
        'marble_ready' => '구슬 ${data['count']}개 배정 — 출발 대기',
        'marble_running' => '굴러가는 중',
        'marble_done' => '${data['winner']} 당첨 (${data['rank']}위)',
        _ => null,
      };

  static String? _pollStatus(String event, Map<String, dynamic> data) =>
      switch (event) {
        'poll_progress' => '투표 ${data['voted']}/${data['players']}',
        'poll_closed' => '투표 마감 (${data['total']}표)',
        _ => null,
      };
}
