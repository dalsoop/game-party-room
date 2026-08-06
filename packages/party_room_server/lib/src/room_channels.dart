/// 방의 대화·자료 섹션.
///
/// 예전에는 단톡이 방 전체에 하나였다. 그러면 파티가 끝난 뒤 "마피아 3판 때
/// 찍은 사진" 을 찾으려면 200개 기록을 거슬러 올라가야 하고, 판이 여러 번
/// 돌면 어느 결과가 어느 판 것인지 섞인다.
///
/// 이제 섹션이 둘로 나뉜다 —
/// - **전체**: 방이 열려 있는 내내 사는 칸. 로비 잡담·공지가 여기 남는다.
/// - **판 칸**: 게임을 시작할 때마다 열린다(그 종목이 [GameModule.ownsSection]
///   으로 원한 경우). **말이 오갔으면** 판이 끝나도 남아, 나중에 그 판만
///   펼쳐 볼 수 있다. 아무 말도 자료도 없던 판의 칸은 안 남는다 — 담을
///   것이 없는 칸이 탭만 채우기 때문이다([closeLiveGame]).
///
/// **표시 이름은 여기서 짓지 않는다.** 이 패키지는 Flutter 를 모르는 순수
/// Dart 라, '전체' 나 '마피아 3판' 같은 문구를 만들면 화면 언어가 서버에
/// 갇힌다. 칸은 `kind`·`gameId`·`round` 같은 **사실**만 싣고, 그걸 사람이
/// 읽는 말로 옮기는 일은 화면(호스트 앱·참가자 SPA)이 한다.
library;

import 'room_limits.dart';

/// 칸 하나.
class ChatSection {
  ChatSection({
    required this.id,
    required this.kind,
    this.gameId,
    this.gameName,
    this.round,
  });

  /// 'room' 또는 'g1', 'g2'… — 발행 순서대로 붙는 안정적인 식별자.
  final String id;

  /// [SectionKind.room] | [SectionKind.game]
  final String kind;

  /// 판 칸이면 어느 종목인지.
  final String? gameId;

  /// 그 종목이 스스로 밝힌 이름([GameModule.name]). 문구 조립이 아니라
  /// 모듈이 declared 한 값을 그대로 나른다 — 화면이 "n판" 을 붙인다.
  final String? gameName;

  /// 그 종목의 몇 번째 판인지(1부터).
  final int? round;

  /// 판이 아직 진행 중인가. 끝난 판도 읽기는 계속 된다.
  bool live = false;

  final List<Map<String, dynamic>> messages = [];

  Map<String, dynamic> toWire() => {
    'id': id,
    'kind': kind,
    if (gameId != null) 'gameId': gameId,
    if (gameName != null) 'gameName': gameName,
    if (round != null) 'round': round,
    'live': live,
  };

  Map<String, dynamic> toJson() => {...toWire(), 'messages': messages};

  static ChatSection fromJson(Map<String, dynamic> j) {
    final s = ChatSection(
      id: j['id'] as String,
      kind: j['kind'] as String? ?? SectionKind.game,
      gameId: j['gameId'] as String?,
      gameName: j['gameName'] as String?,
      round: (j['round'] as num?)?.toInt(),
    )..live = false; // 복구된 판은 진행 중이 아니다 — 호스트가 다시 연다.
    for (final m in (j['messages'] as List<dynamic>? ?? const [])) {
      s.messages.add((m as Map).cast<String, dynamic>());
    }
    return s;
  }
}

/// 칸의 종류. 화면이 이 값을 보고 이름을 붙인다.
abstract final class SectionKind {
  static const room = 'room';
  static const game = 'game';
}

/// 말한 사람의 자격. 닉네임이 아니라 **역할**이다.
///
/// 예전에는 서버가 '호스트'·'사회자' 라는 문구를 직접 닉네임 칸에 넣었다.
/// 그러면 화면 언어를 바꿀 수도, 호스트와 사회자를 다르게 그릴 수도 없다.
abstract final class Speaker {
  static const player = 'player';
  static const host = 'host';
  static const mc = 'mc';
}

/// 방이 가진 칸 전체.
class RoomChannels {
  RoomChannels({this.limits = const RoomLimits()});

  final RoomLimits limits;

  /// 방이 열려 있는 내내 사는 칸의 id.
  static const roomId = 'room';

  final List<ChatSection> _sections = [
    ChatSection(id: roomId, kind: SectionKind.room)..live = true,
  ];

  /// 판 칸 id 를 붙일 때 쓰는 일련번호.
  int _serial = 0;

  /// 종목별로 "n판" 을 세기 위한 카운터.
  final Map<String, int> _roundOf = {};

  List<ChatSection> get sections => List.unmodifiable(_sections);

  ChatSection get room => _sections.first;

  /// 지금 진행 중인 판 칸. 없으면 null.
  ChatSection? get liveGame {
    for (final s in _sections) {
      if (s.kind == SectionKind.game && s.live) return s;
    }
    return null;
  }

  /// 참가자·호스트가 기본으로 볼 칸 — 판이 돌고 있으면 그 판.
  String get defaultId => liveGame?.id ?? roomId;

  ChatSection? byId(String? id) {
    for (final s in _sections) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 쓸 수 있는 칸으로 정규화한다.
  ///
  /// 모르는 id·끝난 판을 그냥 거절하면 참가자 화면이 조용히 먹통이 된다.
  /// 끝난 판에 말을 걸면 지금 열린 곳으로 흘려보내는 편이 낫다.
  String writableId(String? requested) {
    final s = byId(requested);
    if (s == null) return defaultId;
    if (s.kind == SectionKind.room || s.live) return s.id;
    return defaultId;
  }

  /// 게임이 시작될 때 판 칸을 연다.
  ChatSection openGame(String gameId, String gameName) {
    closeLiveGame();
    final round = (_roundOf[gameId] ?? 0) + 1;
    _roundOf[gameId] = round;
    _serial++;
    final section = ChatSection(
      id: 'g$_serial',
      kind: SectionKind.game,
      gameId: gameId,
      gameName: gameName,
      round: round,
    )..live = true;
    _sections.add(section);
    _trim();
    return section;
  }

  /// 이 칸에 자료가 있는지 — 방이 알려 준다(칸은 파일을 직접 모르므로).
  bool Function(String sectionId)? hasFiles;

  /// 판이 끝났다 — 칸은 남고 쓰기만 닫힌다.
  ///
  /// 단, **아무 말도 자료도 없는 칸은 남기지 않는다.** 칸이 있는 이유는 그
  /// 판의 대화를 담기 위해서인데, 아무도 말하지 않은 판에는 담을 것이 없다.
  /// 실측: 구슬 룰렛 아홉 판을 돌리자 빈 칸이 열한 개 생겨 단톡 탭을 채웠고,
  /// 그 안에는 아무것도 없었다. 파티 한 번에 상한(24)까지 차오른다.
  ///
  /// 지운 칸의 회차 번호는 되돌린다 — 안 그러면 남은 칸이 "구슬 5라운드"
  /// 하나뿐인데 1~4가 어디에도 없는 목록이 된다.
  void closeLiveGame() {
    final live = liveGame;
    for (final s in _sections) {
      if (s.kind == SectionKind.game) s.live = false;
    }
    if (live == null) return;
    if (live.messages.isNotEmpty) return;
    if (hasFiles?.call(live.id) ?? false) return;
    _sections.remove(live);
    final gid = live.gameId;
    if (gid != null && (_roundOf[gid] ?? 0) > 0) {
      _roundOf[gid] = _roundOf[gid]! - 1;
    }
  }

  /// 이 칸 하나만 진행 중으로. 저장분에서 판을 되살릴 때 쓴다 —
  /// 칸 복구는 전부 `live=false` 로 떨어지므로 다시 켜 줘야 판과 칸이 맞는다.
  void makeLive(String sectionId) {
    final target = byId(sectionId);
    if (target == null || target.kind != SectionKind.game) return;
    closeLiveGame();
    target.live = true;
  }

  void append(String sectionId, Map<String, dynamic> msg) {
    final s = byId(sectionId) ?? room;
    s.messages.add(msg);
    while (s.messages.length > limits.messagesPerSection) {
      s.messages.removeAt(0);
    }
  }

  /// 밀려난 칸을 알려 준다. 방이 그 칸의 자료를 함께 치우려고 듣는다 —
  /// 안 치우면 화면에서 못 여는 파일이 방 용량을 계속 먹어서, 나중에
  /// 올리는 사람이 이유 없이 거절당한다.
  void Function(String sectionId)? onSectionDropped;

  /// 오래된 판 칸부터 버린다. 전체 칸은 절대 안 버린다.
  void _trim() {
    while (_sections.length > limits.sections) {
      final i = _sections.indexWhere(
        (s) => s.kind == SectionKind.game && !s.live,
      );
      if (i < 0) return;
      final dropped = _sections.removeAt(i);
      onSectionDropped?.call(dropped.id);
    }
  }

  List<Map<String, dynamic>> toWire() =>
      _sections.map((s) => s.toWire()).toList();

  Map<String, dynamic> toJson() => {
    'serial': _serial,
    'rounds': _roundOf,
    'sections': _sections.map((s) => s.toJson()).toList(),
  };

  void restore(Map<String, dynamic>? j) {
    if (j == null) return;
    final list = j['sections'] as List<dynamic>?;
    if (list == null || list.isEmpty) return;
    _sections
      ..clear()
      ..addAll(
        list.map(
          (e) => ChatSection.fromJson((e as Map).cast<String, dynamic>()),
        ),
      );
    // 전체 칸은 항상 있어야 하고 항상 첫 자리다.
    if (_sections.isEmpty || _sections.first.id != roomId) {
      _sections.insert(
        0,
        ChatSection(id: roomId, kind: SectionKind.room)..live = true,
      );
    }
    _sections.first.live = true;
    _serial = (j['serial'] as num?)?.toInt() ?? _sections.length;
    _roundOf
      ..clear()
      ..addAll(
        ((j['rounds'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k as String, (v as num).toInt()),
        ),
      );
  }
}
