import 'package:party_room_server/party_room_server.dart';

import '../host_controller.dart';

/// 앱 제어 API의 게임 갈래.
///
/// 명령 검증과 응답 계약은 순수 Dart의 [GameControlCommands]가 소유한다.
/// 이 어댑터는 기존 `ControlService`의 작은 메서드 표면만 유지한다.
class ControlGameCommands {
  ControlGameCommands(HostController ctrl)
    : _commands = GameControlCommands(ctrl.games);

  final GameControlCommands _commands;

  Map<String, dynamic> start(Map<String, dynamic> args) =>
      _commands.run('start', args);

  Map<String, dynamic> end() => _commands.run('end');

  Map<String, dynamic> marble(String action) =>
      _commands.run('marble', {'action': action});

  Map<String, dynamic> ladder(String action) =>
      _commands.run('ladder', {'action': action});

  Map<String, dynamic> mafia(String action) =>
      _commands.run('mafia', {'action': action});

  Map<String, dynamic> liar(String action) =>
      _commands.run('liar', {'action': action});

  Map<String, dynamic> restart() => _commands.run('restart');
}
