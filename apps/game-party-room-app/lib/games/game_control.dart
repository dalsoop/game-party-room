// 공개 생성자 인자는 밑줄 없는 이름이어야 한다. 초기화 형식으로 바꾸면
// 호출부가 `_settings:` 같은 private 이름을 써야 하므로 이 린트만 예외다.
// ignore_for_file: prefer_initializing_formals

import 'package:party_room_server/party_room_server.dart';

import '../settings/host_settings.dart';

/// 앱 화면이 쓰는 게임 제어 파사드.
///
/// 실제 진행은 순수 Dart 패키지의 [RoomGameControl]이 맡는다. 여기는 앱 설정을
/// 규칙 맵으로 바꾸고, 화면에만 필요한 상태 문구·역할표를 보관한다. 방마다
/// 엔진을 따로 두므로 다른 방으로 이동해도 구슬·사다리의 시계가 끊기거나
/// 새로 선택한 방을 잘못 움직이지 않는다.
class GameControl implements GameControlPort {
  GameControl({
    required Room? Function() room,
    required HostSettings Function() settings,
    required void Function() changed,
    required void Function() onEnded,
  }) : _roomOf = room,
       _settings = settings,
       _changed = changed,
       _onEnded = onEnded;

  final Room? Function() _roomOf;
  final HostSettings Function() _settings;
  final void Function() _changed;
  final void Function() _onEnded;
  final Map<Room, RoomGameControl> _engines = {};

  RoomGameControl? get _engine {
    final room = _roomOf();
    if (room == null) return null;
    return _engines.putIfAbsent(
      room,
      () => RoomGameControl(room: room, onChanged: _changed),
    );
  }

  @override
  GameModule? get activeGame => _roomOf()?.activeGame;

  void changed() => _changed();

  bool get timedProgressRunning => _engine?.clock.running ?? false;

  String gameStatus = '';
  String mafiaPhase = '';
  Map<String, String> mafiaRoles = {};

  @override
  MafiaGame? get mafia => _engine?.mafia;
  @override
  LiarGame? get liar => _engine?.liar;
  PollGame? get poll => _engine?.poll;
  @override
  MarbleGame? get marble => _engine?.marble;
  @override
  LadderGame? get ladder => _engine?.ladder;

  @override
  int get connectedCount => _engine?.connectedCount ?? 0;

  @override
  int? get ladderTracing => _engine?.ladderTracing;
  double get ladderProgress => _engine?.ladderProgress ?? 0;
  bool get ladderAutoAll => _engine?.ladderAutoAll ?? false;

  @override
  bool startMafia({Map<String, dynamic>? rules}) =>
      _engine?.startMafia(
        rules: rules ?? _settings().rulesFor(MafiaGame.gameId),
      ) ??
      false;

  @override
  bool startLiar({Map<String, dynamic>? rules}) =>
      _engine?.startLiar(
        rules: rules ?? _settings().rulesFor(LiarGame.gameId),
      ) ??
      false;

  bool startLiarCustom(String category, String word, List<int>? imageBytes) =>
      _engine?.startLiarCustom(
        category,
        word,
        imageBytes,
        rules: _settings().rulesFor(LiarGame.gameId),
      ) ??
      false;

  @override
  bool startMarble({Map<String, dynamic>? rules}) {
    final started =
        _engine?.startMarble(
          rules: rules ?? _settings().rulesFor(MarbleGame.gameId),
        ) ??
        false;
    if (started) gameStatus = '구슬 배정 완료 — 출발 대기';
    return started;
  }

  @override
  bool restartMarble() => startMarble();

  @override
  void launchMarble() => _engine?.launchMarble();

  @override
  void skipMarble() => _engine?.skipMarble();

  @override
  bool startLadder(List<String> outcomes, {Map<String, dynamic>? rules}) {
    final started =
        _engine?.startLadder(
          outcomes,
          rules: rules ?? _settings().rulesFor(LadderGame.gameId),
        ) ??
        false;
    if (started) gameStatus = '사다리 준비 완료';
    return started;
  }

  @override
  bool restartLadder() {
    final previous = ladder?.rawOutcomes ?? const <String>[];
    return startLadder(List<String>.of(previous));
  }

  @override
  void traceNextLadder() => _engine?.traceNextLadder();

  @override
  void traceAllLadder() => _engine?.traceAllLadder();

  void revealLadder(int column) => _engine?.revealLadder(column);

  @override
  bool startPoll(
    String question,
    List<String> options, {
    Map<String, dynamic>? rules,
  }) {
    final started =
        _engine?.startPoll(
          question,
          options,
          rules: rules ?? _settings().rulesFor(PollGame.gameId),
        ) ??
        false;
    if (started) gameStatus = '투표 진행 중';
    return started;
  }

  @override
  void mafiaNight() => _engine?.mafiaNight();
  @override
  void mafiaDay() => _engine?.mafiaDay();
  @override
  void mafiaVote() => _engine?.mafiaVote();
  @override
  void mafiaCloseVote() => _engine?.mafiaCloseVote();
  @override
  void liarVote() => _engine?.liarVote();
  @override
  void liarCloseVote() => _engine?.liarCloseVote();

  @override
  void endGame() {
    _onEnded();
    _engine?.endGame();
    resetState();
    _changed();
  }

  void stopTracing() => _engine?.stopTracing();

  /// 지운 방의 타이머와 참조를 즉시 놓아 준다.
  void forget(Room room) => _engines.remove(room)?.dispose();

  void resetState() {
    gameStatus = '';
    mafiaPhase = '';
    mafiaRoles = {};
  }

  void dispose() {
    for (final engine in _engines.values) {
      engine.dispose();
    }
  }
}
