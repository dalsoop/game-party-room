import 'dart:math';

import '../game_module.dart';
import '../player.dart';
import '../roster.dart';
import '../voting.dart';

/// 게임 3호: 라이어 게임.
///
/// 전원에게 같은 제시어를 주되 라이어 1명만 다른(또는 빈) 제시어.
/// 토론 후 라이어 지목 투표 → 라이어가 걸리면 제시어 맞히기 기회.
class LiarGame implements GameModule {
  static const gameId = 'liar';

  @override
  String get id => gameId;
  @override
  String get name => '라이어 게임';
  @override
  int get minPlayers => 3;
  @override
  int get maxPlayers => 20;

  /// 설명·추궁이 그 판의 기록이다.
  @override
  bool get ownsSection => true;

  /// 카테고리별 제시어 풀 (오프라인 내장).
  static const Map<String, List<String>> wordPools = {
    '음식': ['치킨', '피자', '떡볶이', '초밥', '삼겹살', '냉면', '햄버거', '파스타', '김밥', '곱창'],
    '장소': [
      '놀이공원',
      '도서관',
      '찜질방',
      '해수욕장',
      '영화관',
      '편의점',
      'PC방',
      '노래방',
      '캠핑장',
      '공항',
    ],
    '직업': ['의사', '소방관', '유튜버', '개발자', '선생님', '요리사', '경찰', '아이돌', '농부', '변호사'],
    '동물': ['고양이', '강아지', '펭귄', '기린', '햄스터', '독수리', '문어', '판다', '악어', '고래'],
    '물건': ['우산', '충전기', '에어팟', '텀블러', '지갑', '리모컨', '가위', '베개', '드라이기', '마우스'],
  };

  String category = '';
  String word = '';
  bool hasImage = false; // 커스텀 이미지 제시어 여부 (서버 /liar-image 로 서빙)
  String? liarSession;
  final GameRoster _roster = GameRoster();
  final VoteBox _votes = VoteBox();
  bool voteOpen = false;

  /// 사회자 커스텀 제시어. [word] 는 필수, 이미지는 RoomServer.liarImage 에 실어 hasImage 로 표시.
  void setupCustom({
    required String category,
    required String word,
    bool hasImage = false,
  }) {
    _custom = true;
    this.category = category;
    this.word = word;
    this.hasImage = hasImage;
  }

  bool _custom = false;

  /// 사용할 카테고리 — 호스트가 고른 것만 뽑는다. 비어 있으면 전부.
  List<String> enabledCategories = [];

  @override
  void applyRules(Map<String, dynamic> rules) {
    final v = rules['categories'];
    enabledCategories = v is List
        ? v.cast<String>().where(wordPools.containsKey).toList()
        : [];
  }

  @override
  void start(GameContext ctx) {
    _roster.seatConnected(ctx);
    _votes.clear();
    voteOpen = false;

    final rng = Random.secure();
    if (!_custom) {
      final cats = enabledCategories.isNotEmpty
          ? enabledCategories
          : wordPools.keys.toList();
      category = cats[rng.nextInt(cats.length)];
      final pool = wordPools[category]!;
      word = pool[rng.nextInt(pool.length)];
      hasImage = false;
    }
    // 아무도 안 붙어 있으면 뽑을 사람이 없다. 예전에는 여기서 nextInt(0) 가
    // RangeError 로 터져 방 전체가 예외를 맞았다 — 판 하나 못 여는 것과
    // 방이 고장 나는 것은 다르다.
    if (_roster.length == 0) {
      liarSession = null;
      return;
    }
    liarSession = _roster.seats[rng.nextInt(_roster.length)].session;

    for (final s in _roster.seats) {
      _sendWord(ctx, s.session);
    }
    ctx.onGameEvent('liar_started', {
      'category': category,
      'word': word,
      'liar': _roster.nicknameOf(liarSession!),
      'players': _roster.length,
    });
  }

  /// 제시어 장면 — 라이어에게는 제시어를 감춘다.
  void _sendWord(GameContext ctx, String session) {
    final isLiar = session == liarSession;
    ctx.sendTo(session, {
      'type': 'scene',
      'scene': 'liar_word',
      'category': category,
      'isLiar': isLiar,
      'word': isLiar ? null : word,
      'hasImage': isLiar ? false : hasImage,
    });
  }

  /// 지목 투표 장면 — 자기 자신은 대상에서 빠진다.
  void _sendVote(GameContext ctx, String session) {
    ctx.sendTo(session, {
      'type': 'scene',
      'scene': 'liar_vote',
      'targets': _roster.othersOf(session),
    });
  }

  /// 결과를 공개했는지. 공개하면 라이어와 제시어가 전원에게 방송되므로
  /// 그 뒤의 투표는 뜻이 없다 — 예전에는 다시 열 수 있어서, 답을 다 본
  /// 사람들이 한 번 더 지목하는 이상한 판이 됐다.
  bool revealed = false;

  /// 판이 끝났는지 — 호스트 화면·CLI 가 더 시킬 게 없다는 것을 안다.
  bool get isOver => revealed;

  /// 이 판의 명단. 사회자 화면이 "누가 들어와 있나" 를 여기서 읽는다.
  List<Seat> get seats => _roster.seats;

  /// 지목을 마친 사람들(세션). 사회자가 "누가 아직 안 골랐나" 를 본다 —
  /// 그걸 모르면 언제 마감할지 감으로 정하게 된다.
  Set<String> get votedBy => _votes.votes.keys.toSet();

  /// 토론 끝 → 지목 투표 시작 (호스트 버튼).
  void beginVote(GameContext ctx) {
    if (revealed) return;
    voteOpen = true;
    _votes.clear();
    for (final s in _roster.seats) {
      _sendVote(ctx, s.session);
    }
    ctx.onGameEvent('liar_phase', {'phase': 'vote'});
  }

  /// 투표 마감 → 결과 공개 (호스트 버튼).
  void closeVote(GameContext ctx) {
    if (revealed) return;
    voteOpen = false;
    revealed = true;
    final tally = _votes.tally();
    final liarNick = _roster.nicknameOf(liarSession ?? '') ?? '';
    // 최다득표자가 라이어면 검거. 동표여도 최다득표 한 명을 고른다(마피아의 무처형과
    // 다른 규칙 — 라이어는 결과를 반드시 공개해야 게임이 끝난다).
    final caught = tally.top != null && tally.top == liarSession;

    ctx.broadcast({
      'type': 'scene',
      'scene': 'liar_result',
      'caught': caught,
      'liar': liarNick,
      'category': category,
      'word': word,
      'tie': tally.isTie,
      'votes': {
        // 닉네임을 못 찾아도 키(세션 토큰)로 떨어지면 안 된다 — 결과 화면은
        // 전원에게 방송된다.
        for (final e in tally.counts.entries)
          _roster.nicknameOf(e.key) ?? '?': e.value,
      },
    });
    ctx.onGameEvent('liar_ended', {'caught': caught, 'liar': liarNick});
  }

  @override
  void onMessage(GameContext ctx, Player from, Map<String, dynamic> msg) {
    if (msg['type'] == 'liar_vote' && voteOpen) {
      // 참가자는 공개 태그로 지목한다 — 세션 토큰은 폰에 내려가지 않는다.
      final target = _roster.sessionOfTag(msg['target'] as String? ?? '');
      if (target == null) return;
      _votes.cast(from.sessionToken, target);
      ctx.sendTo(from.sessionToken, {'type': 'liar_vote_ack'});
      ctx.onGameEvent('liar_vote_progress', {
        'voted': _votes.length,
        'total': _roster.length,
      });
    }
  }

  @override
  void onReconnect(GameContext ctx, Player player) {
    if (!_roster.contains(player.sessionToken)) return;
    if (voteOpen) {
      _sendVote(ctx, player.sessionToken);
    } else {
      _sendWord(ctx, player.sessionToken);
    }
  }

  @override
  void end(GameContext ctx) {}

  @override
  Map<String, dynamic> toJson() => {
    'category': category,
    'word': word,
    'liar': liarSession,
    'voteOpen': voteOpen,
    // 공개 여부도 남긴다 — 재시작 뒤 끝난 판이 되살아나면 안 된다.
    'revealed': revealed,
    'hasImage': hasImage,
    'categories': enabledCategories,
    'members': _roster.toJson(),
    'votes': _votes.toJson(),
  };

  @override
  void restore(GameContext ctx, Map<String, dynamic> json) {
    category = json['category'] as String? ?? '';
    word = json['word'] as String? ?? '';
    liarSession = json['liar'] as String?;
    voteOpen = json['voteOpen'] as bool? ?? false;
    revealed = json['revealed'] as bool? ?? false;
    // 이미지 제시어의 **바이트는 메모리에만** 산다(사진 한 장을 상태 파일에
    // base64 로 넣을 수는 없다). 그래서 재시작을 넘기지 못한다. 그런데
    // `hasImage` 만 살아 돌아오면, 재접속한 폰이 있지도 않은 그림을
    // 요청하고 404 를 받아 빈 화면을 본다 — 글자 제시어는 멀쩡히 있는데도.
    // 없는 것은 없다고 말한다.
    hasImage = false;
    enabledCategories = (json['categories'] as List<dynamic>? ?? [])
        .cast<String>();
    _roster.restore(json['members'] as List<dynamic>?);
    _votes.restore(json['votes'] as Map<String, dynamic>?);
  }
}
