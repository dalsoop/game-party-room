import 'control/game_control_port.dart';
import 'game_clock.dart';
import 'game_module.dart';
import 'games/ladder/ladder_game.dart';
import 'games/liar_game.dart';
import 'games/mafia/mafia_game.dart';
import 'games/marble/marble_game.dart';
import 'games/poll_game.dart';
import 'room.dart';

/// 방 하나의 판을 시작하고, 진행하고, 끝내는 화면 독립 제어기.
///
/// 게임 판정은 각 [GameModule]이 갖고, 이 클래스는 여러 모듈에 공통인 호스트
/// 진행(페이즈 전환, 구슬 시간, 사다리 순차 공개)을 맡는다. Flutter·화면 문구·
/// 앱 설정을 모르므로 macOS 앱과 헤드리스 서버가 같은 실행 경로를 쓸 수 있다.
class RoomGameControl implements GameControlPort {
  RoomGameControl({required this.room, this.onChanged, GameClock? clock})
    : clock = clock ?? GameClock();

  final Room room;
  final void Function()? onChanged;
  final GameClock clock;

  @override
  GameModule? get activeGame => room.activeGame;

  @override
  MafiaGame? get mafia =>
      room.activeGame is MafiaGame ? room.activeGame as MafiaGame : null;
  @override
  LiarGame? get liar =>
      room.activeGame is LiarGame ? room.activeGame as LiarGame : null;
  PollGame? get poll =>
      room.activeGame is PollGame ? room.activeGame as PollGame : null;
  @override
  MarbleGame? get marble =>
      room.activeGame is MarbleGame ? room.activeGame as MarbleGame : null;
  @override
  LadderGame? get ladder =>
      room.activeGame is LadderGame ? room.activeGame as LadderGame : null;

  @override
  int get connectedCount => room.players.where((p) => p.connected).length;

  void _changed() => onChanged?.call();

  bool _launch(GameModule game, Map<String, dynamic>? rules) {
    if (connectedCount < game.minPlayers) return false;
    game.applyRules(rules ?? const {});
    room.startGame(game);
    _changed();
    return true;
  }

  @override
  bool startMafia({Map<String, dynamic>? rules}) => _launch(MafiaGame(), rules);

  @override
  bool startLiar({Map<String, dynamic>? rules}) {
    final game = LiarGame();
    if (connectedCount < game.minPlayers) return false;
    room.liarImage = null;
    return _launch(game, rules);
  }

  bool startLiarCustom(
    String category,
    String word,
    List<int>? imageBytes, {
    Map<String, dynamic>? rules,
  }) {
    final game = LiarGame()
      ..setupCustom(
        category: category,
        word: word,
        hasImage: imageBytes != null,
      );
    if (connectedCount < game.minPlayers) return false;
    room.liarImage = imageBytes;
    return _launch(game, rules);
  }

  @override
  bool startMarble({Map<String, dynamic>? rules}) =>
      _launch(MarbleGame(), rules);

  @override
  bool restartMarble() {
    final previous = marble;
    final rules = previous == null
        ? null
        : <String, dynamic>{
            'winnerRank': previous.winnerRank,
            'speed': previous.speed,
            'course': previous.courseId,
          };
    return startMarble(rules: rules);
  }

  @override
  void launchMarble() {
    final game = marble;
    if (game == null) return;
    game.launch(room.gameCtx);
    clock.start(_tickMarble);
    _changed();
  }

  void _tickMarble(double dt) {
    final game = marble;
    if (game == null || !game.running) {
      clock.stop();
      return;
    }
    game.tick(room.gameCtx, dt * _pacing(game));
    _changed();
  }

  double _pacing(MarbleGame game) {
    final world = game.world;
    if (world == null) return 1;
    if (game.decided && !game.finished) return 6;
    final target = game.winnerRank == 'last' && world.remaining <= 2
        ? world.straggler
        : world.leader;
    final nearGoal = target != null && (world.track.zoomY - target.y) < 6;
    return nearGoal && world.remaining > 1 ? 0.45 : 1.0;
  }

  @override
  void skipMarble() {
    final game = marble;
    if (game == null) return;
    game.skipToEnd(room.gameCtx);
    clock.stop();
    _changed();
  }

  @override
  int? ladderTracing;
  double ladderProgress = 0;
  bool ladderAutoAll = false;

  double get _traceSeconds => ladderAutoAll ? 0.6 : 1.6;

  @override
  bool startLadder(List<String> outcomes, {Map<String, dynamic>? rules}) {
    return _launch(LadderGame()..setup(outcomes: outcomes), rules);
  }

  @override
  bool restartLadder() {
    final previous = ladder?.rawOutcomes ?? const <String>[];
    return startLadder(List<String>.of(previous));
  }

  @override
  void traceNextLadder() {
    final game = ladder;
    if (game == null || ladderTracing != null) return;
    final next = game.nextUnrevealed;
    if (next == null) {
      ladderAutoAll = false;
      clock.stop();
      _changed();
      return;
    }
    ladderTracing = next;
    ladderProgress = 0;
    clock.start(_tickLadder);
    _changed();
  }

  @override
  void traceAllLadder() {
    ladderAutoAll = true;
    if (ladderTracing == null) {
      traceNextLadder();
    } else {
      _changed();
    }
  }

  void _tickLadder(double dt) {
    final column = ladderTracing;
    if (column == null) {
      clock.stop();
      return;
    }
    ladderProgress += dt / _traceSeconds;
    if (ladderProgress < 1) {
      _changed();
      return;
    }
    ladderTracing = null;
    ladderProgress = 0;
    revealLadder(column);
    if (ladderAutoAll) {
      traceNextLadder();
    } else {
      clock.stop();
      _changed();
    }
  }

  void revealLadder(int column) {
    final game = ladder;
    if (game == null) return;
    game.reveal(room.gameCtx, column);
    _changed();
  }

  @override
  bool startPoll(
    String question,
    List<String> options, {
    Map<String, dynamic>? rules,
  }) {
    return _launch(
      PollGame()..setup(question: question, options: options),
      rules,
    );
  }

  @override
  void mafiaNight() {
    mafia?.beginNight(room.gameCtx);
    _changed();
  }

  @override
  void mafiaDay() {
    mafia?.beginDay(room.gameCtx);
    _changed();
  }

  @override
  void mafiaVote() {
    mafia?.beginVote(room.gameCtx);
    _changed();
  }

  @override
  void mafiaCloseVote() {
    mafia?.closeVote(room.gameCtx);
    _changed();
  }

  @override
  void liarVote() {
    liar?.beginVote(room.gameCtx);
    _changed();
  }

  @override
  void liarCloseVote() {
    liar?.closeVote(room.gameCtx);
    _changed();
  }

  @override
  void endGame() {
    stopTracing();
    room.endGame();
    _changed();
  }

  void stopTracing() {
    clock.stop();
    ladderTracing = null;
    ladderProgress = 0;
    ladderAutoAll = false;
  }

  void dispose() => clock.dispose();
}
