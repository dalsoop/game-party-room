import 'mafia_role.dart';

/// 마피아 게임에 앉은 참가자 한 명 — 역할과 1회성 능력 소진 여부.
class MafiaMember {
  MafiaMember(this.sessionToken, this.tag, this.nickname, this.role);

  final String sessionToken;

  /// 방이 발급한 공개 식별자 — 닉네임이 겹쳐도 이걸로 사람을 특정한다.
  final String tag;
  final String nickname;
  final MafiaRole role;

  bool alive = true;
  bool shieldUsed = false; // 군인: 방탄 소진
  bool sniperUsed = false; // 저격수: 필살 소진
  bool reportUsed = false; // 기자: 취재 소진

  /// 이번 밤에 행동할 수 있는가. [anyDead] 는 영매 판정용(죽은 사람이 있어야 지목 가능).
  bool canActAtNight({required bool anyDead}) => switch (role) {
    MafiaRole.mafia => true,
    MafiaRole.doctor => true,
    MafiaRole.police => true,
    MafiaRole.spy => true,
    MafiaRole.sniper => !sniperUsed,
    MafiaRole.medium => anyDead,
    MafiaRole.reporter => !reportUsed,
    _ => false,
  };

  Map<String, dynamic> toJson() => {
    'session': sessionToken,
    'tag': tag,
    'nickname': nickname,
    'role': role.name,
    'alive': alive,
    'shieldUsed': shieldUsed,
    'sniperUsed': sniperUsed,
    'reportUsed': reportUsed,
  };

  static MafiaMember fromJson(Map<String, dynamic> j) =>
      MafiaMember(
          j['session'] as String,
          j['tag'] as String? ?? '',
          j['nickname'] as String,
          MafiaRole.values.byName(j['role'] as String),
        )
        ..alive = j['alive'] as bool? ?? true
        ..shieldUsed = j['shieldUsed'] as bool? ?? false
        ..sniperUsed = j['sniperUsed'] as bool? ?? false
        ..reportUsed = j['reportUsed'] as bool? ?? false;
}
