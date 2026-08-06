import 'dart:convert';
import 'dart:io';

import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

import 'support/memory_assets.dart';
import 'support/participant.dart';

/// 한계값은 **한 곳에서만** 정해진다.
///
/// 예전에는 업로드 30MB 가 `RoomFiles` 와 `chat.js` 양쪽에, 기록 200개가
/// `RoomChannels` 와 `chat.js` 양쪽에, 채팅 300자가 서버와 `index.html` 의
/// maxlength 양쪽에 박혀 있었다. 한쪽만 고치면 다른 쪽이 조용히 거짓말을
/// 한다 — 서버는 받는데 폰이 먼저 거절하거나, 그 반대. 이제 값은
/// [RoomLimits] 하나이고 접속할 때 화면으로 내려간다.
void main() {
  /// 기본값과 다른 값을 넣어야 "정말 이 값을 쓰는지" 가 검사된다.
  const tight = RoomLimits(
    players: 4,
    chatTextLength: 10,
    messagesPerSection: 3,
    sections: 3,
    messageBytes: 512,
    uploadBytes: 2048,
    filesPerSection: 2,
    filesPerOwner: 1,
    bytesPerOwner: 4096,
    totalBytes: 8192,
  );

  late RoomServer server;
  late Room room;
  late int port;

  setUp(() async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = probe.port;
    await probe.close();
    server = RoomServer(assets: MemoryAssets(), port: port, limits: tight);
    room = server.createRoom(token: 'TESTRM');
    await server.start();
  });
  tearDown(() => server.stop());

  Future<Map<String, dynamic>> join(String nick) async {
    final c = HttpClient();
    final req = await c.post('127.0.0.1', port, '/api/join');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'room': 'TESTRM', 'nickname': nick}));
    final res = await req.close();
    final body =
        jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    c.close();
    return body;
  }

  Future<(IOWebSocketChannel, List<Map<String, dynamic>>)> connect(
    String session,
  ) async {
    final ws = IOWebSocketChannel(
      await WebSocket.connect('ws://127.0.0.1:$port/ws?room=TESTRM'),
    );
    final inbox = <Map<String, dynamic>>[];
    ws.stream.listen(
      (m) => inbox.add(jsonDecode(m as String) as Map<String, dynamic>),
      onError: (_) {},
    );
    authAs(ws, session);
    // 붙자마자 서버가 한계값을 내려보낸다 — 그게 도착해야 자리에 앉은 것이다.
    // 고정 지연으로 기다리면 기계가 바쁠 때 밀린다.
    await waitForFrame(inbox, 'limits');
    return (ws, inbox);
  }

  test('접속하면 한계값이 화면으로 내려간다', () async {
    final me = await join('가');
    final (ws, inbox) = await connect(me['session'] as String);
    final limits = inbox.firstWhere((m) => m['type'] == 'limits');
    // 화면이 읽는 키가 곧 계약이다 — 이름이 바뀌면 폰이 조용히 옛 기본값을 쓴다.
    expect(limits['uploadBytes'], tight.uploadBytes);
    expect(limits['chatTextLength'], tight.chatTextLength);
    expect(limits['messagesPerSection'], tight.messagesPerSection);
    expect(limits['filesPerOwner'], tight.filesPerOwner);
    await ws.sink.close();
  });

  test('채팅 길이 상한이 실제로 적용된다', () async {
    final me = await join('가');
    final (ws, _) = await connect(me['session'] as String);
    ws.sink.add(jsonEncode({'type': 'chat', 'text': '가' * 50}));
    await Future.delayed(const Duration(milliseconds: 200));
    expect(room.chatHistory.single['text'], '가' * tight.chatTextLength);
    await ws.sink.close();
  });

  test('기록 상한이 실제로 적용된다', () async {
    for (var i = 0; i < tight.messagesPerSection + 3; i++) {
      room.hostChat('$i');
    }
    expect(room.chatHistory, hasLength(tight.messagesPerSection));
  });

  test('정원이 실제로 적용된다', () async {
    for (var i = 0; i < tight.players; i++) {
      expect((await join('손님$i'))['session'], isNotNull, reason: '$i번째');
    }
    expect((await join('한명더'))['error'], 'room_full');
  });

  test('업로드 크기 상한이 실제로 적용된다', () async {
    final me = await join('가');
    final c = HttpClient();
    final req = await c.post(
      '127.0.0.1',
      port,
      '/api/upload?room=TESTRM&name=big.jpg',
    );
    req.headers.set('x-party-session', me['session'] as String);
    req.add(List.filled(tight.uploadBytes + 100, 65));
    final res = await req.close();
    await res.drain<void>();
    c.close();
    expect(res.statusCode, 413);
  });

  test('사람당 몫도 주입한 값을 쓴다', () async {
    final me = await join('가');
    Future<int> up(String name) async {
      final c = HttpClient();
      final req = await c.post(
        '127.0.0.1',
        port,
        '/api/upload?room=TESTRM&name=$name',
      );
      req.headers.set('x-party-session', me['session'] as String);
      req.add(List.filled(64, 65));
      final res = await req.close();
      await res.drain<void>();
      c.close();
      return res.statusCode;
    }

    expect(await up('a.jpg'), 200);
    expect(await up('b.jpg'), 429, reason: 'filesPerOwner=1 인데 둘째가 통과했다');
  });

  test('칸 개수 상한도 주입한 값을 쓴다', () {
    for (var i = 0; i < tight.sections + 4; i++) {
      room.channels.openGame('mafia', '마피아');
    }
    expect(room.channels.sections.length, lessThanOrEqualTo(tight.sections));
  });
}
