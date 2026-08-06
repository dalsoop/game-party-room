import 'dart:convert';
import 'dart:io';

import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

import 'support/memory_assets.dart';
import 'support/participant.dart';

/// 끊긴 참가자 정리(pruneDisconnected)의 계약.
///
/// 끊긴 자리는 재접속을 위해 남겨 두지만, 방치하면 유령이 정원을 다 먹는다 —
/// 복구된 방이 room_full 로 잠기는 실사고를 겪었다. 정리는 (1) 접속 중인
/// 사람은 건드리지 않고 (2) 지워진 세션으로는 복구 입장이 안 되며
/// (3) 로비에 즉시 반영되어야 한다.
void main() {
  late RoomServer server;
  late Room room;
  late int port;

  setUp(() async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = probe.port;
    await probe.close();
    server = RoomServer(assets: MemoryAssets(), port: port);
    room = server.createRoom(token: 'TESTRM');
    await server.start();
  });

  tearDown(() async => server.stop());

  Future<Map<String, dynamic>> join(String nickname) async {
    final client = HttpClient();
    final req = await client.post('127.0.0.1', port, '/api/join');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'room': 'TESTRM', 'nickname': nickname}));
    final res = await req.close();
    final body =
        jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    client.close();
    return body;
  }

  test('접속 중인 참가자는 남기고 유령만 지운다', () async {
    final a = await join('접속유지');
    await join('유령1');
    await join('유령2');

    // 한 명만 실제로 소켓을 붙인다.
    final ws = IOWebSocketChannel.connect(wsUrl(port, 'TESTRM'));
    await ws.ready;
    authAs(ws, a['session'] as String?);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(room.players.length, 3);
    final removed = room.pruneDisconnected();
    expect(removed, 2);

    final left = room.players;
    expect(left.length, 1);
    expect(left.single.nickname, '접속유지');

    // 지워진 세션으로는 복구 입장이 안 된다 — 신규 입장으로 떨어진다.
    final client = HttpClient();
    final req = await client.post('127.0.0.1', port, '/api/join');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'room': 'TESTRM', 'session': 'GHOST_SESSION'}));
    final res = await req.close();
    final body =
        jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    client.close();
    expect(body['restored'], isNot(true));

    await ws.sink.close();
  });

  test('끊긴 시각이 로비 스냅샷에 실린다', () async {
    final a = await join('갔다올게');
    final ws = IOWebSocketChannel.connect(wsUrl(port, 'TESTRM'));
    await ws.ready;
    authAs(ws, a['session'] as String?);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(room.players.single.connected, isTrue);
    expect(room.players.single.lastSeen, isNull);

    await ws.sink.close();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final p = room.players.single;
    expect(p.connected, isFalse);
    expect(p.lastSeen, isNotNull, reason: '끊긴 시각을 남겨야 한다');
    final row = room.lobbySnapshot().single;
    expect(row['lastSeenMs'], isNotNull);
  });

  test('지울 것이 없으면 0을 돌려주고 아무 일도 없다', () {
    expect(room.pruneDisconnected(), 0);
  });
}
