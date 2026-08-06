/// 파티룸 방 서버 — Flutter 없이 도는 순수 Dart.
///
/// 호스트 앱(앱 번들 자산 + 앱 저장소)과 헤드리스 서버(파일시스템)가
/// **같은 코드**를 쓴다. 차이는 [AssetSource]·[StateStore] 주입뿐이다.
library;

export 'src/asset_source.dart';
export 'src/control/control_endpoint.dart';
export 'src/control/control_errors.dart';
export 'src/control/game_control_commands.dart';
export 'src/control/game_control_port.dart';
export 'src/control/room_control.dart';
export 'src/game_module.dart';
export 'src/game_clock.dart';
export 'src/game_registry.dart';
export 'src/games/ladder/ladder_game.dart';
export 'src/games/liar_game.dart';
export 'src/games/mafia/mafia_game.dart';
export 'src/games/marble/marble_course.dart';
export 'src/games/marble/marble_game.dart';
export 'src/games/marble/marble_world.dart';
export 'src/games/palette.dart';
export 'src/games/poll_game.dart';
export 'src/participant_gate.dart';
export 'src/participant_link.dart';
export 'src/player.dart';
export 'src/relay_client.dart';
export 'src/room_channels.dart';
export 'src/room.dart';
export 'src/room_game_control.dart';
export 'src/room_files.dart';
export 'src/room_limits.dart';
export 'src/room_persistence.dart';
export 'src/room_server.dart';
export 'src/roster.dart';
export 'src/state_store.dart';
export 'src/voting.dart';
export 'src/web_assets.dart';
