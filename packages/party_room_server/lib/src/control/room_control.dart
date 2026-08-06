import 'dart:async';

import '../room_game_control.dart';
import '../room_server.dart';
import 'control_errors.dart';
import 'game_control_commands.dart';

/// 화면 없이 방을 굴리는 제어 표면.
///
/// 상시로 도는 헤드리스 서버(`bin/serve.dart`)가 이것을 얹는다. 여태 제어는
/// 앱에만 있어서, k3s 에 올린 방 서버는 **사람은 모이는데 판을 못 여는**
/// 상태였다.
///
/// 앱의 `ControlService` 와 **명령 이름·응답 모양을 맞춘다** — 같은 CLI 가
/// 두 서버를 다 조종할 수 있어야 하고, 이름이 갈리면 손에 익은 명령이 한쪽
/// 에서만 통한다.
///
/// 세부 진행도 [RoomGameControl]을 통해 앱과 같은 코어를 지난다. 헤드리스가
/// 별도 판정이나 타이머를 가지면 같은 명령이 배포 위치에 따라 달라진다.
class RoomControl {
  RoomControl(this.server, {this.onChanged});

  final RoomServer server;

  /// 상태가 바뀌었을 때 — 헤드리스는 저장 트리거로 쓴다.
  final void Function()? onChanged;

  /// 방마다 시계가 따로 돈다. A방 구슬이 굴러가는 동안 B방을 골라도 A방의
  /// 판이 B방을 잘못 움직이거나 멈추지 않는다.
  final Map<Room, RoomGameControl> _gameControls = {};

  /// 지금 조종 대상. `room use` 로 옮긴다.
  ///
  /// 방이 여럿일 수 있고 명령마다 토큰을 적게 하면 손이 아프다. 앱도 같은
  /// 방식이라(보고 있는 방) 계약이 갈리지 않는다.
  String? _selected;

  Room get _room {
    final r = server.byToken(_selected) ?? server.rooms.firstOrNull;
    if (r == null) throw ControlFailure('방이 없습니다 — room new 로 여세요');
    return r;
  }

  /// 이 표면이 아는 명령과 action. `capabilities` 가 이 표를 그대로 낸다.
  static const actions = <String, List<String>>{
    'status': [],
    'rooms': [],
    'players': [],
    'games': [],
    'room': [
      'new',
      'use',
      'open',
      'close',
      'rename',
      'pin',
      'clear',
      'delete',
      'prune',
    ],
    'kick': [],
    'start': [],
    'end': [],
    'restart': [],
    ...GameControlCommands.actions,
    'chat': [],
  };

  Future<Map<String, dynamic>> run(
    String command,
    Map<String, dynamic> args,
  ) async {
    switch (command) {
      case 'capabilities':
        return {
          'surface': 'headless',
          'actions': actions,
          'missing': const ['tunnel · mc · relay · sound (앱 기능)'],
        };
      case 'status':
        return _status();
      case 'rooms':
        return {
          'rooms': [for (final r in server.rooms) _roomSummary(r)],
        };
      case 'players':
        return {'players': _room.lobbySnapshot()};
      case 'games':
        return _gameCommands.games();
      case 'room':
        return _roomCommand(args);
      case 'kick':
        final tag = (args['tag'] as String? ?? '').trim();
        if (tag.isEmpty) throw ControlUsageError('kick <태그>');
        final p = _byTag(tag);
        _room.kick(p.sessionToken);
        _changed();
        return {'tag': tag, 'nickname': p.nickname};
      case 'start':
      case 'end':
      case 'restart':
      case 'marble':
      case 'ladder':
      case 'mafia':
      case 'liar':
        return _gameCommands.run(command, args);
      case 'chat':
        final text = (args['text'] as String? ?? '').trim();
        if (text.isEmpty) throw ControlUsageError('chat <할 말>');
        _room.hostChat(text);
        _changed();
        return {'text': text};
      default:
        throw ControlUsageError(
          '모르는 명령: $command (가능: ${actions.keys.join(", ")})',
        );
    }
  }

  RoomGameControl get _game => _gameControls.putIfAbsent(
    _room,
    () => RoomGameControl(room: _room, onChanged: _changed),
  );

  GameControlCommands get _gameCommands => GameControlCommands(_game);

  Future<Map<String, dynamic>> _roomCommand(Map<String, dynamic> args) async {
    final action = args['action'] as String?;
    switch (action) {
      case 'new':
        // 정원이 차면 왜 안 되는지 말하며 거절한다 — 조용히 안 만들어지면
        // 부르는 쪽은 성공으로 읽는다.
        try {
          final r = server.createRoom(
            name: (args['name'] as String? ?? '').trim(),
          );
          _selected = r.roomToken;
          _changed();
          return _roomSummary(r);
        } on StateError catch (e) {
          throw ControlFailure(e.message);
        }
      case 'use':
        final t = (args['token'] as String? ?? '').trim();
        if (server.byToken(t) == null) throw ControlFailure('그런 방이 없습니다: $t');
        _selected = t;
        return _roomSummary(server.byToken(t)!);
      case 'open':
      case 'close':
        _room.open = action == 'open';
        _changed();
        return _roomSummary(_room);
      case 'rename':
        _room.name = (args['name'] as String? ?? '').trim();
        _changed();
        return _roomSummary(_room);
      case 'pin':
        // 해제는 **off 라고 적어야** 한다. 빈 값을 해제로 읽으면 자물쇠가
        // 조용히 풀린다 — 앱에서 이미 겪은 실사고와 같은 자리다.
        final raw = (args['pin'] as String? ?? '').trim();
        if (raw.isEmpty) throw ControlUsageError('pin <4자리|off>');
        final wanted = raw == 'off' ? null : raw;
        if (!_room.setPin(wanted)) {
          throw ControlUsageError('비밀번호는 숫자 4자리입니다 (해제는 off)');
        }
        _changed();
        // 원문은 돌려주지 않는다 — 걸렸는지만 알린다.
        return {'token': _room.roomToken, 'hasPin': wanted != null};
      case 'clear':
        // 참가자·대화·자료가 사라진다 — 실수로 지나가면 안 된다.
        if (args['confirm'] != true) {
          throw ControlUsageError('되돌릴 수 없습니다 — confirm 이 필요합니다');
        }
        _game.stopTracing();
        await _room.clear();
        _changed();
        return _roomSummary(_room);
      case 'delete':
        if (args['confirm'] != true) {
          throw ControlUsageError('되돌릴 수 없습니다 — confirm 이 필요합니다');
        }
        final t = _room.roomToken;
        final doomed = _room;
        _gameControls.remove(doomed)?.dispose();
        await server.removeRoom(t);
        if (_selected == t) _selected = null;
        _changed();
        return {'deleted': t};
      case 'prune':
        final n = _room.pruneDisconnected();
        _changed();
        return {'pruned': n};
      default:
        throw badControlAction('room', actions['room']!);
    }
  }

  Player _byTag(String tag) {
    for (final p in _room.players) {
      if (p.tag == tag) return p;
    }
    throw ControlFailure('그런 참가자가 없습니다: $tag');
  }

  Map<String, dynamic> _status() {
    final r = server.rooms.isEmpty ? null : _room;
    return {
      'schemaVersion': 2,
      'at': DateTime.now().toIso8601String(),
      'surface': 'headless',
      'rooms': [for (final x in server.rooms) _roomSummary(x)],
      'selected': r?.roomToken,
      'roomPolicy': {
        'max': server.maxRooms,
        'full': server.full,
        'ttlHours': server.roomTtl.inHours,
      },
      if (r != null) ...{
        'players': {
          'connected': r.players.where((p) => p.connected).length,
          'total': r.players.length,
          'max': r.limits.players,
          'list': r.lobbySnapshot(),
        },
        'game': r.activeGame == null
            ? null
            : {'id': r.activeGame!.id, 'name': r.activeGame!.name},
      },
    };
  }

  Map<String, dynamic> _roomSummary(Room r) => {
    'token': r.roomToken,
    'name': r.name,
    'open': r.open,
    'hasPin': r.hasPin,
    'players': r.players.length,
    'connected': r.players.where((p) => p.connected).length,
    'game': r.activeGame?.id,
    'createdAt': r.createdAt.toIso8601String(),
  };

  void _changed() => onChanged?.call();

  void dispose() {
    for (final game in _gameControls.values) {
      game.dispose();
    }
    _gameControls.clear();
  }
}
