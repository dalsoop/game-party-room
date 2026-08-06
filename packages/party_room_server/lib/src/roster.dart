import 'game_module.dart';

/// 게임에 참여 중인 자리 하나 — 세션·공개 식별자·표시 이름.
typedef Seat = ({String session, String tag, String nickname});

/// 게임이 시작 시점에 고정하는 참가자 명단.
///
/// 방(RoomServer)의 참가자 목록은 게임 도중에도 늘어나지만, 게임의 명단은
/// 시작한 순간으로 고정된다. "연결된 사람만 앉히기", "나를 뺀 대상 목록",
/// "세션→닉네임" 은 모든 게임이 똑같이 필요해서 각자 구현하고 있었다.
class GameRoster {
  final List<Seat> _seats = [];

  List<Seat> get seats => List.unmodifiable(_seats);
  int get length => _seats.length;
  bool get isEmpty => _seats.isEmpty;

  /// 지금 연결돼 있는 참가자로 명단을 채운다(게임 시작 시).
  void seatConnected(GameContext ctx) {
    _seats
      ..clear()
      ..addAll(
        ctx
            .players()
            .where((p) => p.connected)
            .map(
              (p) =>
                  (session: p.sessionToken, tag: p.tag, nickname: p.nickname),
            ),
      );
  }

  bool contains(String session) => _seats.any((s) => s.session == session);

  String? nicknameOf(String session) {
    for (final s in _seats) {
      if (s.session == session) return s.nickname;
    }
    return null;
  }

  /// 공개 태그로 자리를 찾는다 — 참가자가 보낸 지목을 서버에서만 푼다.
  String? sessionOfTag(String tag) {
    for (final s in _seats) {
      if (s.tag == tag) return s.session;
    }
    return null;
  }

  /// 전송용 스냅샷.
  ///
  /// **세션 토큰은 절대 싣지 않는다.** 세션 토큰은 인증 자격증명이라
  /// (`/ws?session=`·`/api/join`), 대상 목록에 실어 보내면 참가자가 남의
  /// 것을 읽어 그 사람 역할을 훔쳐보고 대신 투표할 수 있다 — 비밀 역할이
  /// 이 앱의 존재 이유이므로 여기서 끊는다. 지목은 공개 태그로 한다.
  List<Map<String, dynamic>> snapshot() => _seats.map(_wire).toList();

  /// 자기 자신을 뺀 스냅샷 — 지목/투표 대상 목록.
  List<Map<String, dynamic>> othersOf(String session) =>
      _seats.where((s) => s.session != session).map(_wire).toList();

  static Map<String, dynamic> _wire(Seat s) => {
    'tag': s.tag,
    'nickname': s.nickname,
  };

  /// 저장용 — 이쪽은 호스트 디스크에만 남으므로 세션을 담는다.
  List<Map<String, dynamic>> toJson() => _seats
      .map((s) => {'session': s.session, 'tag': s.tag, 'nickname': s.nickname})
      .toList();

  void restore(List<dynamic>? json) {
    _seats.clear();
    for (final j in (json ?? const [])) {
      final m = j as Map<String, dynamic>;
      _seats.add((
        session: m['session'] as String,
        tag: m['tag'] as String? ?? '',
        nickname: m['nickname'] as String,
      ));
    }
  }
}
