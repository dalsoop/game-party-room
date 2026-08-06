import 'player.dart';

/// 게임 모듈 인터페이스.
///
/// 각 게임(마피아·익명투표·룰렛…)은 이 인터페이스를 구현한 상태머신 하나.
/// 코어(RoomServer)는 방/세션/연결만 관리하고, 게임 진행은 모듈에 위임한다.
abstract class GameModule {
  /// 게임 식별자 (참가자 SPA 화면 라우팅 키).
  String get id;

  /// 사람이 읽는 이름.
  String get name;

  /// 최소/최대 인원.
  int get minPlayers;
  int get maxPlayers;

  /// 이 종목이 시작될 때 **자기 칸**(대화·자료 섹션)을 여는가.
  ///
  /// 방 서버가 "게임이 시작되면 무조건 칸을 연다" 고 정해 버리면, 칸을 쓸
  /// 일이 없는 종목까지 빈 칸을 남긴다. 칸이 필요한지는 종목이 안다 —
  /// 마피아는 그 판의 대화가 곧 게임이지만, 즉석 투표 한 번은 아니다.
  /// [minPlayers] 처럼 모듈이 스스로 밝히는 값이다.
  bool get ownsSection;

  /// 호스트가 설정한 규칙을 받는다. 게임 시작 **전에** 한 번 불린다.
  ///
  /// 값은 종목이 `GameRuleSpec` 으로 선언한 키들이다. 모르는 키는 무시하면 된다.
  /// 규칙은 `toJson`/`restore` 에도 실어야 앱 재시작 후 같은 규칙으로 이어진다.
  void applyRules(Map<String, dynamic> rules) {}

  /// 게임 시작. [ctx] 로 브로드캐스트/개인전송/플레이어 목록 접근.
  void start(GameContext ctx);

  /// 참가자 메시지 수신 (예: 투표 선택, 마피아 지목).
  void onMessage(GameContext ctx, Player from, Map<String, dynamic> msg);

  /// 참가자 재접속 시 — 해당 참가자에게 현재 상태를 다시 보내준다.
  void onReconnect(GameContext ctx, Player player);

  /// 게임 강제 종료/정리.
  void end(GameContext ctx);

  /// 호스트 상태 저장용 스냅샷 (앱 재시작 복구).
  Map<String, dynamic> toJson();

  /// 스냅샷 복원.
  void restore(GameContext ctx, Map<String, dynamic> json);
}

/// 모듈이 코어 기능에 접근하는 통로.
class GameContext {
  GameContext({
    required this.players,
    required this.broadcast,
    required this.sendTo,
    required this.onGameEvent,
  });

  /// 현재 방 참가자 (연결 여부 포함).
  final List<Player> Function() players;

  /// 전원 브로드캐스트.
  final void Function(Map<String, dynamic> msg) broadcast;

  /// 특정 참가자에게만 전송 (세션 토큰 기준) — 마피아 정체 등 비밀 정보용.
  final void Function(String sessionToken, Map<String, dynamic> msg) sendTo;

  /// 게임 → 호스트 UI 이벤트 (화면 갱신·상태 저장 트리거).
  final void Function(String event, Map<String, dynamic> data) onGameEvent;
}
