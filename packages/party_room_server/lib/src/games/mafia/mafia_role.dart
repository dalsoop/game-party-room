import 'package:meta/meta.dart' show visibleForTesting;

/// 마피아 역할. (표준 룰 — 마피아42/나무위키 대조, 기획-qr파티룸/결정사항.md)
enum MafiaRole {
  mafia('마피아', '밤마다 시민 한 명을 제거합니다. 마피아끼리는 서로를 압니다.', team: 'mafia'),
  spy('스파이', '마피아 편입니다. 밤마다 한 명의 직업을 알아냅니다. 마피아를 도와 정체를 숨기세요.', team: 'mafia'),
  doctor('의사', '밤마다 한 명을 지목해 마피아의 공격에서 보호합니다.'),
  police('경찰', '밤마다 한 명을 조사해 마피아인지 확인합니다.'),
  soldier('군인', '마피아의 공격을 한 번 버텨냅니다. 방탄은 자동 발동됩니다.'),
  sniper('저격수', '게임 중 단 한 번, 밤에 지목한 사람을 무조건 제거합니다. 신중하게 쓰세요.'),
  medium('영매', '밤마다 죽은 사람 중 한 명의 정체를 확인합니다.'),
  reporter('기자', '밤에 한 명을 취재하면 다음 날 아침 그 사람의 직업이 전체 공개됩니다. 1회.'),
  politician('정치인', '당신의 투표는 2표로 계산됩니다.'),
  lover('연인', '연인 둘 중 하나가 죽으면 나머지도 함께 죽습니다. 서로가 누군지 압니다.'),
  citizen('시민', '낮 토론과 투표로 마피아를 찾아내세요.');

  const MafiaRole(this.label, this.description, {this.team = 'citizen'});

  final String label;
  final String description;

  /// 'mafia' | 'citizen'
  final String team;

  bool get isMafiaTeam => team == 'mafia';

  /// 투표 무게 — 정치인만 2표.
  int get voteWeight => this == MafiaRole.politician ? 2 : 1;
}

/// 게임 진행 단계.
enum MafiaPhase { night, day, vote, ended }

/// 인원수별 역할 편성표.
///
/// 규칙의 핵심이라 상태머신에서 떼어 따로 둔다 — 밸런스는 여기만 보면 되고,
/// 테스트도 게임을 띄우지 않고 이 표만 검사할 수 있다.
///
/// 4~5인: 마피아1 의사1 (+경찰 5인)
/// 6~7인: 마피아2 의사 경찰
/// 8~9인: + 군인, 영매
/// 10~11인: + 스파이(마피아팀), 저격수
/// 12인~: + 기자 / 13인~ 정치인 / 14인~ 연인×2
class MafiaComposition {
  /// [extended] 를 끄면 기본 4역할(마피아·의사·경찰·시민)만 쓴다 —
  /// 처음 하는 사람들과 할 때 역할이 많으면 진행이 늘어진다.
  static List<MafiaRole> forPlayerCount(int n, {bool extended = true}) {
    final roles = <MafiaRole>[];
    final mafiaCount = n >= 12 ? 3 : (n >= 6 ? 2 : 1);
    roles.addAll(List.filled(mafiaCount, MafiaRole.mafia));
    roles.add(MafiaRole.doctor);
    if (n >= 5) roles.add(MafiaRole.police);
    if (extended) {
      if (n >= 8) roles.add(MafiaRole.soldier);
      if (n >= 9) roles.add(MafiaRole.medium);
      if (n >= 10) roles.add(MafiaRole.spy);
      if (n >= 11) roles.add(MafiaRole.sniper);
      if (n >= 12) roles.add(MafiaRole.reporter);
      if (n >= 13) roles.add(MafiaRole.politician);
      if (n >= 14) {
        roles.add(MafiaRole.lover);
        roles.add(MafiaRole.lover);
      }
    }
    while (roles.length < n) {
      roles.add(MafiaRole.citizen);
    }
    return roles.sublist(0, n);
  }

  /// 편성 밸런스 회귀 테스트용 별칭.
  @visibleForTesting
  static List<MafiaRole> forTest(int n) => forPlayerCount(n);
}
