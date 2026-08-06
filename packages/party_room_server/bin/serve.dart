import 'dart:async';
import 'dart:io';

import 'package:party_room_server/party_room_server.dart';

/// 헤드리스 파티룸 서버.
///
/// 호스트 앱 없이 방을 연다 — 상시 서버(예: `party.example.com`)로 돌리거나,
/// 개발 중 참가자 화면만 확인할 때 쓴다. 앱과 완전히 같은 서버 코드다.
///
///   dart run bin/serve.dart --assets ../../apps/game-party-room-app [--port 8765]
///
/// 컨테이너로도 돈다 — `--assets`·`--port`·`--state` 를 환경변수로도 받는다.
Future<void> main(List<String> args) async {
  final opts = _parse(args);

  final assets = FileAssetSource(opts['assets']!);
  // 자산이 실제로 있는지 먼저 본다 — 없으면 참가자가 빈 화면을 본다.
  if (await assets.loadString('assets/web/index.html') == null) {
    stderr.writeln('참가자 화면을 찾지 못했습니다: ${opts['assets']}/assets/web/index.html');
    stderr.writeln('--assets 로 앱 디렉터리를 지정하세요.');
    exit(2);
  }

  final port = int.parse(
    opts['port'] ?? Platform.environment['PORT'] ?? '${RoomServer.defaultPort}',
  );
  final store = opts['state'] == null
      ? MemoryStateStore()
      : FileStateStore(opts['state']!);

  final persistence = RoomPersistence(store, assets);
  final server = RoomServer(assets: assets, port: port);

  // 화면 없이 방을 굴리는 문. 토큰이 없으면 아예 안 연다 — 토큰 없는
  // 제어 API 를 인터넷에 붙이는 것이 제일 나쁘다.
  //
  // 토큰은 `--control-token` 또는 `PARTY_CONTROL_TOKEN` 으로 준다. 안 주면
  // 하나 만들어 로그에 한 번 찍는다(컨테이너 로그로 꺼내 쓰라는 뜻) —
  // 그래야 "제어를 켜려면 뭘 해야 하지" 에서 막히지 않는다.
  final controlToken =
      opts['control-token'] ??
      Platform.environment['PARTY_CONTROL_TOKEN'] ??
      (opts['no-control'] == 'true' ? '' : ControlEndpoint.newToken());
  final control = RoomControl(
    server,
    onChanged: () => persistence.save(server),
  );
  final endpoint = ControlEndpoint(control: control, token: controlToken);
  server.extraRoutes = endpoint.route;
  final outcome = await persistence.restoreInto(server);
  if (server.rooms.isEmpty) {
    server.createRoom(name: opts['name'] ?? '헤드리스 방');
  }
  final room = server.rooms.first;
  server.onStateChanged = () => persistence.save(server);

  await server.start();

  stdout.writeln('파티룸 서버 시작');
  stdout.writeln('  방 코드 : ${room.roomToken}');
  stdout.writeln('  포트    : $port');
  stdout.writeln('  자산    : ${opts['assets']}');
  stdout.writeln(
    controlToken.isEmpty
        ? '  제어    : 꺼짐 (--no-control)'
        : '  제어    : POST /api/control · 토큰 $controlToken',
  );
  stdout.writeln(
    '  상태    : ${outcome.rooms > 0 ? '방 ${outcome.rooms}개 복구됨'
              '${outcome.prunedPlayers > 0 ? " (유령 ${outcome.prunedPlayers}명 정리)" : ""}' : '새 방'}',
  );
  for (final ni in await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  )) {
    for (final a in ni.addresses) {
      if (a.isLoopback) continue;
      stdout.writeln(
        '  참가    : http://${a.address}:$port/?room=${room.roomToken}',
      );
    }
  }

  // --demo <게임id> : 인원이 차면 자동으로 시작한다. 호스트 앱 없이 참가자 화면을
  // 확인할 때 쓴다. 운영용이 아니라 개발 편의 기능이다.
  final demo = opts['demo'];
  if (demo != null) {
    final module = GameRegistry.create(demo);
    if (module == null) {
      stderr.writeln('모르는 게임: $demo (가능: ${GameRegistry.ids.join(", ")})');
      exit(2);
    }
    final need = module.minPlayers;
    stdout.writeln('  데모    : $demo — $need명 모이면 자동 시작');
    room.lobbyStream.listen((players) {
      final on = players.where((p) => p.connected).length;
      if (on >= need && room.activeGame == null) {
        stdout.writeln('[데모] $on명 — $demo 시작');
        room.startGame(GameRegistry.create(demo)!);
      }
    });
  }

  server.gameEvents.listen((e) => stdout.writeln('[게임] ${e.$1} ${e.$2}'));
  room.lobbyStream.listen((players) {
    final on = players.where((p) => p.connected).length;
    stdout.writeln('[로비] 참가자 ${players.length}명 (연결 $on)');
  });

  // 깔끔히 내린다 — 소켓을 닫지 않으면 참가자 브라우저가 계속 재시도한다.
  //
  // **SIGTERM 을 반드시 받는다.** 쿠버네티스가 파드를 내릴 때 보내는 것이
  // 그것이고, 안 받으면 30초 뒤 SIGKILL 로 죽는다 — 그 사이 참가자들은
  // 멈춘 화면을 보고, 마지막 상태 저장도 못 한다. 터미널의 Ctrl+C(SIGINT)만
  // 받고 있었다.
  var closing = false;
  Future<void> shutdown(String why) async {
    if (closing) return;
    closing = true;
    stdout.writeln('종료합니다 ($why)…');
    unawaited(persistence.save(server));
    control.dispose();
    await server.stop();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown('SIGINT'));
  ProcessSignal.sigterm.watch().listen((_) => shutdown('SIGTERM'));
}

Map<String, String> _parse(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    if (!args[i].startsWith('--')) continue;
    final key = args[i].substring(2);
    if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      out[key] = args[++i];
    } else {
      out[key] = 'true';
    }
  }
  // 컨테이너에서는 인자 대신 환경변수로 준다.
  for (final e in const {
    'assets': 'PARTY_ASSETS',
    'state': 'PARTY_STATE',
    'name': 'PARTY_ROOM_NAME',
  }.entries) {
    final v = Platform.environment[e.value];
    if (out[e.key] == null && v != null && v.isNotEmpty) out[e.key] = v;
  }
  if (out['assets'] == null) {
    stderr.writeln(
      '사용법: dart run bin/serve.dart --assets <앱 디렉터리> '
      '[--port 8765] [--state room.json] [--demo mafia] '
      '[--control-token <값>] [--no-control]',
    );
    exit(2);
  }
  return out;
}
