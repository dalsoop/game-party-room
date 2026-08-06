import '../game_registry.dart';
import '../games/ladder/ladder_game.dart';
import '../games/liar_game.dart';
import '../games/mafia/mafia_game.dart';
import '../games/marble/marble_game.dart';
import '../games/poll_game.dart';
import 'control_errors.dart';
import 'game_control_port.dart';

/// 앱과 헤드리스가 함께 쓰는 게임 명령 실행기.
///
/// JSON 경계의 검증·오류·응답까지 여기서 한 번만 정의한다. 실제 판 진행은
/// [GameControlPort]가 위임받은 `RoomGameControl`/앱 래퍼가 수행한다.
class GameControlCommands {
  GameControlCommands(this.control);

  final GameControlPort control;

  static const actions = <String, List<String>>{
    'marble': ['launch', 'skip'],
    'ladder': ['next', 'all'],
    'mafia': ['night', 'day', 'vote', 'close'],
    'liar': ['vote', 'close'],
  };

  Map<String, dynamic> games() => {
    'games': [for (final id in GameRegistry.ids) _gameSummary(id)],
  };

  Map<String, dynamic> _gameSummary(String id) {
    final module = GameRegistry.create(id)!;
    return {
      'id': id,
      'name': module.name,
      'minPlayers': module.minPlayers,
      'maxPlayers': module.maxPlayers,
      'ready': control.connectedCount >= module.minPlayers,
      'live': control.activeGame?.id == id,
      'actions': actions[id] ?? const <String>[],
    };
  }

  Map<String, dynamic> run(
    String command, [
    Map<String, dynamic> args = const {},
  ]) => switch (command) {
    'start' => _start(args),
    'end' => _end(),
    'restart' => _restart(),
    'marble' => _marble(_action(args)),
    'ladder' => _ladder(_action(args)),
    'mafia' => _mafia(_action(args)),
    'liar' => _liar(_action(args)),
    _ => throw ControlUsageError('모르는 게임 명령: $command'),
  };

  String _action(Map<String, dynamic> args) =>
      (args['action'] as String? ?? '').trim();

  Map<String, dynamic>? _rules(Map<String, dynamic> args) {
    final raw = args['rules'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  Map<String, dynamic> _start(Map<String, dynamic> args) {
    final id = (args['game'] as String? ?? '').trim();
    final module = GameRegistry.create(id);
    if (module == null) {
      throw ControlUsageError(
        '모르는 게임: $id (가능: ${GameRegistry.ids.join(", ")})',
      );
    }
    if (control.activeGame != null) {
      throw ControlFailure('이미 판이 돌고 있습니다. 먼저 end 로 끝내세요');
    }
    if (control.connectedCount < module.minPlayers) {
      throw ControlFailure(
        '${module.name}은 ${module.minPlayers}명부터입니다 '
        '(지금 ${control.connectedCount}명 접속)',
      );
    }

    final rules = _rules(args);
    final started = switch (id) {
      MafiaGame.gameId => control.startMafia(rules: rules),
      LiarGame.gameId => control.startLiar(rules: rules),
      MarbleGame.gameId => control.startMarble(rules: rules),
      LadderGame.gameId => control.startLadder(
        _strings(args['outcomes'], fallback: const ['당첨']),
        rules: rules,
      ),
      PollGame.gameId => _startPoll(args, rules),
      _ => false,
    };
    if (!started) throw ControlFailure('$id 를 시작하지 못했습니다');
    return {
      'started': id,
      'game': id,
      'name': module.name,
      'players': control.connectedCount,
    };
  }

  bool _startPoll(Map<String, dynamic> args, Map<String, dynamic>? rules) {
    final question = (args['question'] as String? ?? '').trim();
    final options = _strings(args['options']);
    if (question.isEmpty || options.length < 2) {
      throw ControlUsageError('poll 은 question 과 options 2개 이상이 필요합니다');
    }
    return control.startPoll(question, options, rules: rules);
  }

  List<String> _strings(Object? raw, {List<String> fallback = const []}) =>
      raw is List ? [for (final value in raw) '$value'] : fallback;

  Map<String, dynamic> _end() {
    final game = control.activeGame;
    if (game == null) throw ControlFailure('진행 중인 판이 없습니다');
    control.endGame();
    return {'ended': game.id};
  }

  Map<String, dynamic> _marble(String action) {
    final game = control.marble;
    if (game == null) throw ControlFailure('구슬 룰렛이 진행 중이 아닙니다');
    switch (action) {
      case 'launch':
        if (game.running) throw ControlFailure('이미 굴러가고 있습니다');
        control.launchMarble();
        return {'launched': true};
      case 'skip':
        control.skipMarble();
        return {'skipped': true, 'finished': game.finished};
      default:
        throw _badAction('marble');
    }
  }

  Map<String, dynamic> _ladder(String action) {
    final game = control.ladder;
    if (game == null) throw ControlFailure('사다리타기가 진행 중이 아닙니다');
    switch (action) {
      case 'next':
        if (game.nextUnrevealed == null) throw ControlFailure('모두 공개됐습니다');
        control.traceNextLadder();
        return {'tracing': control.ladderTracing};
      case 'all':
        control.traceAllLadder();
        return {'revealing': 'all'};
      default:
        throw _badAction('ladder');
    }
  }

  Map<String, dynamic> _mafia(String action) {
    final game = control.mafia;
    if (game == null) throw ControlFailure('마피아가 진행 중이 아닙니다');
    if (game.isOver) {
      throw ControlFailure('판이 이미 끝났습니다 — end 로 정리하고 새로 시작하세요');
    }
    switch (action) {
      case 'night':
        control.mafiaNight();
      case 'day':
        control.mafiaDay();
      case 'vote':
        control.mafiaVote();
      case 'close':
        control.mafiaCloseVote();
      default:
        throw _badAction('mafia');
    }
    return {
      'phase': game.phase.name,
      'round': game.round,
      'alive': game.aliveCount,
    };
  }

  Map<String, dynamic> _liar(String action) {
    final game = control.liar;
    if (game == null) throw ControlFailure('라이어 게임이 진행 중이 아닙니다');
    if (game.isOver) {
      throw ControlFailure('판이 이미 끝났습니다 — end 로 정리하고 새로 시작하세요');
    }
    switch (action) {
      case 'vote':
        control.liarVote();
      case 'close':
        control.liarCloseVote();
      default:
        throw _badAction('liar');
    }
    return {'voteOpen': game.voteOpen};
  }

  Map<String, dynamic> _restart() {
    if (control.marble != null) {
      if (!control.restartMarble()) throw ControlFailure('다시 시작하지 못했습니다');
      return {'restarted': 'marble'};
    }
    if (control.ladder != null) {
      if (!control.restartLadder()) throw ControlFailure('다시 시작하지 못했습니다');
      return {'restarted': 'ladder'};
    }
    throw ControlFailure('한 판 더 할 수 있는 종목이 아닙니다 (구슬·사다리만)');
  }

  ControlUsageError _badAction(String command) =>
      ControlUsageError('$command 의 action 은 ${actions[command]!.join("|")}');
}
