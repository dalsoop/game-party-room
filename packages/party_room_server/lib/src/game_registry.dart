import 'game_module.dart';
import 'games/ladder/ladder_game.dart';
import 'games/liar_game.dart';
import 'games/mafia/mafia_game.dart';
import 'games/marble/marble_game.dart';
import 'games/poll_game.dart';

/// id → 게임 모듈 팩토리. **서버 전용 정본**이다.
///
/// 저장된 방을 복원할 때 id 문자열만 남아 있으므로 이 표가 필요하다.
/// UI(배너·문구·호스트 화면)는 여기 두지 않는다 — 서버 계층이 위젯을 알면
/// 헤드리스로 서버만 돌릴 수 없다. UI 는 `games/game_catalog.dart` 가 붙인다.
class GameRegistry {
  /// 새 게임을 추가하면 여기 한 줄.
  static final Map<String, GameModule Function()> factories = {
    MafiaGame.gameId: MafiaGame.new,
    LiarGame.gameId: LiarGame.new,
    PollGame.gameId: PollGame.new,
    MarbleGame.gameId: MarbleGame.new,
    LadderGame.gameId: LadderGame.new,
  };

  static GameModule? create(String id) => factories[id]?.call();

  static List<String> get ids => factories.keys.toList();
}
