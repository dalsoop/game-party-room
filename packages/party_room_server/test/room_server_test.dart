import 'dart:convert';
import 'dart:io';

import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

import 'support/memory_assets.dart';
import 'support/participant.dart';

/// 서버 수명주기 회귀 테스트.
///
/// 참가자 재접속은 이 앱의 핵심 계약이다(참가자 SPA 는 onclose 후 1.5초 뒤 자동 재연결,
/// 세션은 localStorage 에 남아 같은 세션으로 다시 붙는다). 그 경로가 깨지면 참가자는
/// 화면상 멀쩡한데 서버는 "끊김"으로 보고 비밀 정보 전송이 조용히 사라진다.
void main() {
  late RoomServer server;
  late Room room;
  late int port;

  setUp(() async {
    // 포트 0 은 못 쓰므로(설계상 고정 포트) 빈 포트를 찾아 넘긴다.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = probe.port;
    await probe.close();
    server = RoomServer(assets: MemoryAssets(), port: port);
    room = server.createRoom(token: 'TESTRM');
    await server.start();
  });

  tearDown(() async {
    await server.stop();
  });

  Future<String> join(String nickname) async {
    final client = HttpClient();
    final req = await client.post('127.0.0.1', port, '/api/join');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'room': 'TESTRM', 'nickname': nickname}));
    final res = await req.close();
    final body =
        jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    client.close();
    return body['session'] as String;
  }

  /// 붙고 나서 첫 프레임으로 누구인지 밝힌다 — 실제 참가자와 같은 길.
  IOWebSocketChannel connect(String session) {
    final ws = IOWebSocketChannel.connect(Uri.parse(wsUrl(port, 'TESTRM')));
    ws.ready.then((_) => authAs(ws, session));
    return ws;
  }

  test('늦게 닫힌 이전 소켓이 새 연결을 끊어놓지 않는다', () async {
    final session = await join('지훈');

    // 1) 첫 연결
    final ws1 = connect(session);
    await ws1.ready;
    final seen1 = <String>[];
    ws1.stream.listen((m) => seen1.add(m as String));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // 2) 이전 소켓이 아직 살아 있는 채로 재접속(탭 두 개·네트워크 전환·half-open TCP).
    final ws2 = connect(session);
    await ws2.ready;
    final seen2 = <String>[];
    ws2.stream.listen((m) => seen2.add(m as String));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // 3) 뒤늦게 이전 소켓이 닫힌다.
    await ws1.sink.close();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // 서버는 여전히 이 참가자를 "연결됨" 으로 봐야 한다.
    expect(
      room.players.single.connected,
      isTrue,
      reason: '이전 소켓의 onDone 이 새 채널을 null 로 만들면 안 된다',
    );

    // 그리고 새 소켓으로 실제 통신이 되어야 한다.
    seen2.clear();
    ws2.sink.add(jsonEncode({'type': 'ping'}));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(
      seen2.any((m) => m.contains('pong')),
      isTrue,
      reason: '새 소켓이 서버로부터 응답을 받아야 한다',
    );

    await ws2.sink.close();
  });

  test('잘못된 JSON 본문으로 입장해도 서버가 죽지 않는다', () async {
    final client = HttpClient();
    final req = await client.post('127.0.0.1', port, '/api/join');
    req.headers.contentType = ContentType.json;
    req.write('{not json');
    final res = await req.close();
    await res.drain<void>();
    client.close();

    expect(res.statusCode, 400);

    // 서버가 계속 살아 있어야 한다 — 정상 입장이 이어서 동작한다.
    final session = await join('민서');
    expect(session, isNotEmpty);
  });
}
