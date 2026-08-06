import 'participant_link.dart';

/// 참가자 한 명.
///
/// `room_server.dart` 에서 떼어냈다 — 게임 모듈은 [Player] 만 필요한데 방 서버 전체를
/// import 하면 `game_module ↔ room_server` 순환이 생긴다.
class Player {
  Player({
    required this.sessionToken,
    required this.nickname,
    required this.tag,
  });

  /// 인증값. 절대 남에게 보이지 않는다.
  final String sessionToken;

  /// 방 안에서 사람을 가리키는 짧은 공개 식별자(4자).
  ///
  /// 닉네임은 겹치고("민서" 둘) 바뀌기도 하지만 이건 방이 끝날 때까지 고정이라,
  /// 화면·기록·문의에서 사람을 특정하는 기준이 된다.
  /// **세션 토큰에서 파생하지 않는다** — 파생하면 공개 화면에 인증값 일부가 새어나간다.
  /// 비어 있는 경우는 태그 도입 이전 상태 파일을 복원할 때뿐이고,
  /// 그때 [RoomServer] 가 새로 채워 준다.
  String tag;

  String nickname;

  /// 지금 이 사람에게 닿는 통로. 끊겨 있으면 null.
  ///
  /// **어느 길로 왔는지는 담지 않는다** — 같은 망에서 곧장 왔든 랑데부가
  /// 물어다 줬든 방과 게임은 똑같이 다룬다. 길을 봐야 하는 쪽은
  /// [ParticipantLink.path] 로 본다.
  ParticipantLink? link;

  bool kicked = false;
  bool get connected => link != null;

  /// 연결이 끊긴 시각. 접속 중이면 null.
  ///
  /// 호스트가 "방금 끊겼으니 재접속을 기다릴지, 한참 전에 나갔으니 정리할지"
  /// 를 판단하는 근거다 — 점 색깔 하나로는 이 구분이 안 된다.
  DateTime? lastSeen;

  Map<String, dynamic> toJson() => {
    'sessionToken': sessionToken,
    'tag': tag,
    'nickname': nickname,
    'kicked': kicked,
    if (lastSeen != null) 'lastSeen': lastSeen!.millisecondsSinceEpoch,
  };

  static Player fromJson(Map<String, dynamic> j) =>
      Player(
          sessionToken: j['sessionToken'] as String,
          nickname: j['nickname'] as String,
          tag: j['tag'] as String? ?? '',
        )
        ..kicked = (j['kicked'] as bool? ?? false)
        ..lastSeen = j['lastSeen'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (j['lastSeen'] as num).toInt(),
              );
}
