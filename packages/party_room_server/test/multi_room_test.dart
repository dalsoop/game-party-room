import 'dart:convert';
import 'dart:io';

import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

import 'support/memory_assets.dart';

/// 여러 방이 같은 포트에서 동시에 산다.
///
/// 호스트 입장에서는 금요 모임방과 회사방이 각자 QR 을 갖고 함께 살아 있는
/// 편이 자연스럽다. **참가자 화면은 한 줄도 안 바뀌었다** — 프로토콜이
/// 처음부터 `?room=<토큰>` 으로 주소를 매기고 있었기 때문이다.
///
/// 여기서 지켜야 할 것은 하나다: **방과 방이 새지 않는다.**
void main() {
  late RoomServer server;
  late Room a;
  late Room b;
  late int port;

  setUp(() async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = probe.port;
    await probe.close();
    server = RoomServer(assets: MemoryAssets(), port: port);
    a = server.createRoom(name: '금요 모임', token: 'AAA111');
    b = server.createRoom(name: '회사 워크숍', token: 'BBB222');
    await server.start();
  });
  tearDown(() => server.stop());

  Future<Map<String, dynamic>> join(String token, String nick) async {
    final c = HttpClient();
    final req = await c.post('127.0.0.1', port, '/api/join');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'room': token, 'nickname': nick}));
    final res = await req.close();
    final body =
        jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    c.close();
    return body;
  }

  Future<(IOWebSocketChannel, List<Map<String, dynamic>>)> connect(
    String token,
    String session,
  ) async {
    final ws = IOWebSocketChannel(
      await WebSocket.connect('ws://127.0.0.1:$port/ws?room=$token'),
    );
    final inbox = <Map<String, dynamic>>[];
    ws.stream.listen(
      (m) => inbox.add(jsonDecode(m as String) as Map<String, dynamic>),
      onError: (_) {},
    );
    ws.sink.add(jsonEncode({'type': 'auth', 'session': session}));
    await Future.delayed(const Duration(milliseconds: 200));
    return (ws, inbox);
  }

  test('참가자는 자기 방에만 앉는다', () async {
    await join('AAA111', '민서');
    await join('BBB222', '태윤');
    expect(a.players.single.nickname, '민서');
    expect(b.players.single.nickname, '태윤');
  });

  test('한 방의 대화가 다른 방으로 새지 않는다', () async {
    final ma = await join('AAA111', '민서');
    final mb = await join('BBB222', '태윤');
    final (wa, ia) = await connect('AAA111', ma['session'] as String);
    final (wb, ib) = await connect('BBB222', mb['session'] as String);

    wa.sink.add(jsonEncode({'type': 'chat', 'text': '금요 모임 비밀'}));
    await Future.delayed(const Duration(milliseconds: 250));

    expect(a.chatHistory.single['text'], '금요 모임 비밀');
    expect(b.chatHistory, isEmpty, reason: '다른 방에 남았다');
    expect(
      jsonEncode(ib).contains('금요 모임 비밀'),
      isFalse,
      reason: '다른 방 참가자에게 방송됐다',
    );
    expect(jsonEncode(ia).contains('금요 모임 비밀'), isTrue);

    await wa.sink.close();
    await wb.sink.close();
  });

  test('판이 두 방에서 동시에 돈다', () async {
    for (var i = 0; i < 4; i++) {
      final m = await join('AAA111', 'a$i');
      await connect('AAA111', m['session'] as String);
    }
    for (var i = 0; i < 4; i++) {
      final m = await join('BBB222', 'b$i');
      await connect('BBB222', m['session'] as String);
    }
    a.startGame(MafiaGame());
    b.startGame(LiarGame());
    await Future.delayed(const Duration(milliseconds: 200));

    expect(a.activeGame!.id, 'mafia');
    expect(b.activeGame!.id, 'liar');
    // 칸도 방마다 따로 열린다.
    expect(a.channels.liveGame!.gameName, '마피아');
    expect(b.channels.liveGame!.gameName, '라이어 게임');
  });

  test('게임 이벤트에 어느 방인지 실려 온다', () async {
    final seen = <String>[];
    server.gameEvents.listen((e) => seen.add('${e.$1.name}:${e.$2}'));
    for (var i = 0; i < 4; i++) {
      final m = await join('AAA111', 'a$i');
      await connect('AAA111', m['session'] as String);
    }
    a.startGame(MafiaGame());
    await Future.delayed(const Duration(milliseconds: 200));
    expect(seen.any((s) => s.startsWith('금요 모임:')), isTrue);
  });

  test('모르는 토큰은 입장도 소켓도 거절한다', () async {
    expect((await join('ZZZ999', '침입자'))['error'], 'bad_room');
    await expectLater(
      WebSocket.connect('ws://127.0.0.1:$port/ws?room=ZZZ999'),
      throwsA(isA<WebSocketException>()),
    );
  });

  test('닫힌 방은 입장을 거절한다', () async {
    b.open = false;
    expect((await join('BBB222', '늦은손님'))['error'], 'room_closed');
    // 열린 방은 그대로.
    expect((await join('AAA111', '민서'))['session'], isNotNull);
  });

  test('방을 지우면 그 방만 사라진다', () async {
    await join('AAA111', '민서');
    expect(await server.removeRoom('BBB222'), isTrue);
    expect(server.rooms.map((r) => r.name), ['금요 모임']);
    expect((await join('BBB222', '태윤'))['error'], 'bad_room');
    expect(a.players.single.nickname, '민서');
  });

  test('자료도 방마다 따로다', () async {
    final tmp = File('${Directory.systemTemp.createTempSync('mr').path}/사진.jpg')
      ..writeAsStringSync('x');
    addTearDown(() => tmp.parent.deleteSync(recursive: true));
    await a.shareFile(tmp.path);
    expect(a.sharedFiles, hasLength(1));
    expect(b.sharedFiles, isEmpty);
  });
}
