import '../game_module.dart';
import '../games/ladder/ladder_game.dart';
import '../games/liar_game.dart';
import '../games/mafia/mafia_game.dart';
import '../games/marble/marble_game.dart';

/// 게임 명령 실행기가 필요로 하는 최소 표면.
///
/// 앱의 화면 상태 래퍼와 헤드리스의 방 엔진이 모두 이 계약을 구현한다.
/// 명령 파싱은 이 타입만 보므로 두 배포 표면에 같은 분기가 복제되지 않는다.
abstract interface class GameControlPort {
  GameModule? get activeGame;
  int get connectedCount;

  MafiaGame? get mafia;
  LiarGame? get liar;
  MarbleGame? get marble;
  LadderGame? get ladder;
  int? get ladderTracing;

  bool startMafia({Map<String, dynamic>? rules});
  bool startLiar({Map<String, dynamic>? rules});
  bool startMarble({Map<String, dynamic>? rules});
  bool startLadder(List<String> outcomes, {Map<String, dynamic>? rules});
  bool startPoll(
    String question,
    List<String> options, {
    Map<String, dynamic>? rules,
  });

  bool restartMarble();
  bool restartLadder();
  void launchMarble();
  void skipMarble();
  void traceNextLadder();
  void traceAllLadder();
  void mafiaNight();
  void mafiaDay();
  void mafiaVote();
  void mafiaCloseVote();
  void liarVote();
  void liarCloseVote();
  void endGame();
}
