import 'dart:convert';
import 'dart:io';

import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

import 'support/memory_assets.dart';

/// 방 서버의 방어선 — 인증 프레임·메시지 상한·업로드 몫.
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
  tearDown(() => server.stop());

  Future<String> join(String nick) async {
    final c = HttpClient();
    final req = await c.post('127.0.0.1', port, '/api/join');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'room': 'TESTRM', 'nickname': nick}));
    final res = await req.close();
    final body =
        jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    c.close();
    return body['session'] as String;
  }

  Future<(IOWebSocketChannel, List<Map<String, dynamic>>)> open({
    String? legacySession,
  }) async {
    final q = legacySession == null
        ? 'room=TESTRM'
        : 'room=TESTRM&session=$legacySession';
    final ws = IOWebSocketChannel(
      await WebSocket.connect('ws://127.0.0.1:$port/ws?$q'),
    );
    final inbox = <Map<String, dynamic>>[];
    ws.stream.listen(
      (m) => inbox.add(jsonDecode(m as String) as Map<String, dynamic>),
      onError: (_) {},
    );
    return (ws, inbox);
  }

  group('세션은 주소가 아니라 첫 프레임으로', () {
    test('auth 프레임으로 붙으면 자리에 앉는다', () async {
      final session = await join('가');
      final (ws, inbox) = await open();
      await Future.delayed(const Duration(milliseconds: 150));
      // 아직 아무도 아니다 — 서버는 인증을 기다린다.
      expect(inbox.any((m) => m['type'] == 'auth_required'), isTrue);
      expect(room.players.single.connected, isFalse);

      ws.sink.add(jsonEncode({'type': 'auth', 'session': session}));
      await Future.delayed(const Duration(milliseconds: 200));
      expect(room.players.single.connected, isTrue);
      expect(inbox.any((m) => m['type'] == 'room_status'), isTrue);
      await ws.sink.close();
    });

    test('모르는 세션이면 알려 주고 끊는다', () async {
      await join('가');
      final (ws, inbox) = await open();
      ws.sink.add(jsonEncode({'type': 'auth', 'session': 'NOSUCHSESSION'}));
      await Future.delayed(const Duration(milliseconds: 200));
      // 영원히 재접속만 하지 않게 이유를 준다.
      expect(inbox.any((m) => m['type'] == 'auth_failed'), isTrue);
      expect(room.players.single.connected, isFalse);
      await ws.sink.close();
    });

    test('인증 전에는 게임 메시지를 받지 않는다', () async {
      final session = await join('가');
      final (ws, _) = await open();
      ws.sink.add(jsonEncode({'type': 'chat', 'text': '누구게'}));
      await Future.delayed(const Duration(milliseconds: 150));
      expect(room.chatHistory, isEmpty, reason: '이름 없는 소켓이 방에 말을 걸었다');

      ws.sink.add(jsonEncode({'type': 'auth', 'session': session}));
      await Future.delayed(const Duration(milliseconds: 150));
      ws.sink.add(jsonEncode({'type': 'chat', 'text': '이제는'}));
      await Future.delayed(const Duration(milliseconds: 150));
      expect(room.chatHistory, hasLength(1));
      await ws.sink.close();
    });

    test('주소에 세션을 담아도 그것만으로는 안 붙는다', () async {
      // 한동안은 `?session=` 도 받아 줬다 — 그 변경 이전에 열려 있던 탭을
      // 위해서였다. 자격증명이 브라우저 방문기록·중간 프록시 로그·인터넷
      // 개방 시 Cloudflare 접속 로그에 남는 길이라 이제 막는다.
      final session = await join('가');
      final (ws, inbox) = await open(legacySession: session);
      await Future.delayed(const Duration(milliseconds: 250));
      expect(
        room.players.single.connected,
        isFalse,
        reason: '주소만으로 자리에 앉으면 토큰이 로그마다 남는다',
      );
      expect(
        inbox.any((m) => m['type'] == 'auth_required'),
        isTrue,
        reason: '그래도 붙을 길은 알려 줘야 한다',
      );
      await ws.sink.close();
    });
  });

  group('메시지 상한', () {
    test('거대한 프레임은 파싱하지 않고 끊는다', () async {
      final session = await join('가');
      final (ws, _) = await open();
      ws.sink.add(jsonEncode({'type': 'auth', 'session': session}));
      await Future.delayed(const Duration(milliseconds: 150));
      expect(room.players.single.connected, isTrue);

      ws.sink.add(
        jsonEncode({
          'type': 'chat',
          'text': 'ㅋ' * const RoomLimits().messageBytes,
        }),
      );
      await Future.delayed(const Duration(milliseconds: 300));
      expect(
        room.players.single.connected,
        isFalse,
        reason: '끊지 않으면 계속 밀어 넣는다',
      );
      expect(room.chatHistory, isEmpty);
    });

    test('평범한 채팅은 멀쩡히 간다', () async {
      final session = await join('가');
      final (ws, _) = await open();
      ws.sink.add(jsonEncode({'type': 'auth', 'session': session}));
      await Future.delayed(const Duration(milliseconds: 150));
      ws.sink.add(jsonEncode({'type': 'chat', 'text': '안녕하세요'}));
      await Future.delayed(const Duration(milliseconds: 150));
      expect(room.chatHistory.single['text'], '안녕하세요');
      await ws.sink.close();
    });
  });

  group('업로드 몫', () {
    Future<int> upload(String session, String name, int bytes) async {
      final c = HttpClient();
      final req = await c.post(
        '127.0.0.1',
        port,
        '/api/upload?room=TESTRM&name=$name',
      );
      req.headers.set('x-party-session', session);
      req.add(List.filled(bytes, 65));
      final res = await req.close();
      await res.drain<void>();
      c.close();
      return res.statusCode;
    }

    test('한 사람이 방 전체를 채우지 못한다', () async {
      final me = await join('욕심');
      const limits = RoomLimits();
      for (var i = 0; i < limits.filesPerOwner; i++) {
        expect(await upload(me, 'p$i.jpg', 1024), 200, reason: '$i번째');
      }
      expect(
        await upload(me, 'over.jpg', 1024),
        429,
        reason: '몫을 넘겼는데도 받으면 다른 손님이 한 장도 못 올린다',
      );
      // 다른 사람 자리는 그대로 남아 있어야 한다.
      final other = await join('다른');
      expect(await upload(other, 'ok.jpg', 1024), 200);
    });

    test('세션 없이는 못 올린다', () async {
      final c = HttpClient();
      final req = await c.post(
        '127.0.0.1',
        port,
        '/api/upload?room=TESTRM&name=x.jpg',
      );
      req.add(List.filled(16, 65));
      final res = await req.close();
      await res.drain<void>();
      c.close();
      expect(res.statusCode, 403);
    });
  });
  _pinTests();
}

/// 입장 비밀번호.
///
/// 방 토큰이 여전히 주 관문이고 이건 두 번째 자물쇠다 — 링크가 엉뚱한
/// 단톡방으로 넘어갔을 때를 막는 용도. 4자리는 1만 가지뿐이라 **연타를
/// 막지 않으면 장식**이 된다.
void _pinTests() {
  group('입장 비밀번호', () {
    late RoomServer server;
    late Room room;
    late int port;

    setUp(() async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      port = probe.port;
      await probe.close();
      server = RoomServer(assets: MemoryAssets(), port: port);
      room = server.createRoom(token: 'PINRM1');
      await server.start();
    });
    tearDown(() => server.stop());

    Future<Map<String, dynamic>> join(Map<String, dynamic> body) async {
      final c = HttpClient();
      final req = await c.post('127.0.0.1', port, '/api/join');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'room': 'PINRM1', ...body}));
      final res = await req.close();
      final out =
          jsonDecode(await res.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      c.close();
      return out;
    }

    test('4자리 숫자만 받는다', () {
      expect(room.setPin('12'), isFalse);
      expect(room.setPin('abcd'), isFalse);
      expect(room.setPin('12345'), isFalse);
      expect(room.hasPin, isFalse);
      expect(room.setPin('4821'), isTrue);
      expect(room.hasPin, isTrue);
      expect(room.setPin(null), isTrue);
      expect(room.hasPin, isFalse);
    });

    test('안 걸면 그냥 들어온다', () async {
      expect((await join({'nickname': '민서'}))['session'], isNotNull);
    });

    test('걸면 맞아야 들어온다', () async {
      room.setPin('4821');
      expect((await join({'nickname': '민서'}))['error'], 'pin_required');
      expect(
        (await join({'nickname': '민서', 'pin': '0000'}))['error'],
        'pin_required',
      );
      expect(
        (await join({'nickname': '민서', 'pin': '4821'}))['session'],
        isNotNull,
      );
    });

    test('이미 들어온 사람은 다시 안 묻는다', () async {
      room.setPin('4821');
      final me = await join({'nickname': '민서', 'pin': '4821'});
      // 새로고침 — 세션만 들고 온다.
      final again = await join({'session': me['session']});
      expect(again['restored'], isTrue);
      expect(again['tag'], me['tag']);
    });

    test('연타하면 잠긴다', () async {
      room.setPin('4821');
      for (var i = 0; i < 5; i++) {
        expect(
          (await join({'nickname': 'x', 'pin': '0000'}))['error'],
          'pin_required',
        );
      }
      // 1만 가지를 초당 수백 번으로 훑는 것을 막는 지점.
      final locked = await join({'nickname': 'x', 'pin': '0000'});
      expect(locked['error'], 'pin_locked');
      expect(locked['retryAfter'], greaterThan(0));
      // 잠긴 동안에는 맞는 비밀번호도 안 통한다.
      expect(
        (await join({'nickname': 'x', 'pin': '4821'}))['error'],
        'pin_locked',
      );
    });

    test('비밀번호 원문은 어디에도 안 실린다', () async {
      room.setPin('4821');
      final c = HttpClient();
      final req = await c.post('127.0.0.1', port, '/api/join');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'room': 'PINRM1', 'nickname': '민서'}));
      final res = await req.close();
      final raw = await res.transform(utf8.decoder).join();
      c.close();
      expect(raw.contains('4821'), isFalse, reason: '응답에 새어 나왔다');
      // 저장분에는 있어야 한다(이 맥에만 남는다) — 그건 전송이 아니다.
      expect(jsonEncode(room.toJson()).contains('4821'), isTrue);
    });

    test('닫힌 방은 비밀번호가 맞아도 안 들어온다', () async {
      room.setPin('4821');
      room.open = false;
      expect(
        (await join({'nickname': '민서', 'pin': '4821'}))['error'],
        'room_closed',
      );
    });
  });
}
