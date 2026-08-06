import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:party_room_relay/party_room_relay.dart';
import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'support/memory_assets.dart';
import 'support/participant.dart';

/// 랑데부를 통째로 세우고 **참가자가 실제로 한 판 도는지** 본다.
///
/// 여기서 확인하려는 것은 하나다: 다른 망에서 들어온 사람도 같은 망에서
/// 들어온 사람과 **구분되지 않게** 논다. 방과 게임은 길을 몰라야 한다
/// (닌텐도 Pia 가 로컬 통신과 인터넷 통신에 공통 API 를 씌운 이유).
///
/// 릴레이는 방 안을 안 들여다본다 — 프레임을 통째로 옮길 뿐이다. 그래서
/// 이 테스트가 통과한다는 것은 릴레이가 게임을 하나도 몰라도 된다는 뜻이다.
void main() {
  late RelayServer relay;
  late RoomServer server;
  late RelayClient client;
  late Room room;

  Future<void> waitForStatus(RelayStatus s) => waitUntil(
    () => client.status == s,
    reason: '랑데부 상태가 $s 가 되지 않았다 (지금 ${client.status})',
  );

  setUp(() async {
    relay = RelayServer(port: 0);
    await relay.start();

    // 포트 0 — 이 테스트를 다른 것과 나란히 돌려도 8765 를 놓고 안 다툰다.
    server = RoomServer(assets: MemoryAssets(), port: 0);
    room = server.createRoom(name: '금요 모임');

    client = RelayClient(
      server: server,
      relayBase: 'http://127.0.0.1:${relay.actualPort}',
      secret: RelayClient.newSecret(),
    );
    await client.start();
    await waitForStatus(RelayStatus.ready);
  });

  tearDown(() async {
    await client.stop();
    await server.stop();
    await relay.stop();
  });

  Uri relayUri(String path) =>
      Uri.parse('http://127.0.0.1:${relay.actualPort}$path');

  Future<(int, Map<String, dynamic>)> post(String path, Object body) async {
    final http = HttpClient();
    try {
      final req = await http.postUrl(relayUri(path));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      Map<String, dynamic> parsed;
      try {
        parsed = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        parsed = {'raw': text};
      }
      return (res.statusCode, parsed);
    } finally {
      http.close(force: true);
    }
  }

  Future<int> statusOf(String path) async {
    final http = HttpClient();
    try {
      final res = await (await http.getUrl(relayUri(path))).close();
      await res.drain<void>();
      return res.statusCode;
    } finally {
      http.close(force: true);
    }
  }

  /// 릴레이를 통해 붙은 참가자 하나.
  Future<
    ({WebSocketChannel ws, List<Map<String, dynamic>> inbox, String session})
  >
  joinViaRelay(String nickname) async {
    final (status, body) = await post('/api/join?c=${client.code}', {
      'room': room.roomToken,
      'nickname': nickname,
    });
    expect(status, 200, reason: '릴레이를 지난 입장이 거절됐다: $body');
    final session = body['session'] as String;

    final ws = WebSocketChannel.connect(
      Uri.parse(
        'ws://127.0.0.1:${relay.actualPort}/ws'
        '?c=${client.code}&room=${Uri.encodeComponent(room.roomToken)}',
      ),
    );
    await ws.ready;
    final inbox = <Map<String, dynamic>>[];
    ws.stream.listen((raw) {
      final m = jsonDecode(raw as String) as Map<String, dynamic>;
      inbox.add(m);
    });
    await waitForFrame(inbox, 'auth_required');
    authAs(ws, session);
    await waitForFrame(inbox, 'limits');
    return (ws: ws, inbox: inbox, session: session);
  }

  test('코드를 받는다', () {
    expect(client.code, isNotNull);
    expect(client.code, hasLength(relayCodeLength));
    for (final ch in client.code!.split('')) {
      expect(relayCodeAlphabet, contains(ch));
    }
    expect(relay.has(client.code!), isTrue);
  });

  test('코드에 불러 줄 때 헷갈리는 글자를 안 쓴다', () {
    // 이 방 코드는 **사람이 불러 주고 받아 적는다**. 파티에서 "영이야 오야?"
    // 로 한 번 막히면 QR 을 두고도 못 들어온다.
    //
    // 처음에는 `relayCodeAlphabet` 에 들었는지만 봤는데, 그러면 상수를 바꿀 때
    // 테스트가 **따라 움직인다** — 알파벳을 통째로 헷갈리는 글자로 바꿔도
    // 통과했다. 막고 싶은 글자를 여기 직접 적어 두어야 잣대가 된다.
    for (final ch in ['0', 'O', '1', 'I', 'L', '2', 'Z', '5', 'S', '8', 'B']) {
      expect(
        relayCodeAlphabet,
        isNot(contains(ch)),
        reason: '"$ch" 는 불러 줄 때 헷갈린다',
      );
    }
  });

  test('다른 망에서 들어와 방에 앉는다', () async {
    final p = await joinViaRelay('민서');
    addTearDown(p.ws.sink.close);

    await waitUntil(() => room.players.any((x) => x.connected));
    final seated = room.players.single;
    expect(seated.nickname, '민서');
    expect(seated.connected, isTrue);
    expect(
      seated.link!.path,
      LinkPath.relay,
      reason: '길은 통로가 알고 있어야 한다 — 자료 정책이 이걸 본다',
    );
  });

  test('말이 양쪽으로 오간다', () async {
    final p = await joinViaRelay('민서');
    addTearDown(p.ws.sink.close);
    await waitUntil(() => room.players.any((x) => x.connected));

    // 올라간다.
    p.ws.sink.add(jsonEncode({'type': 'chat', 'text': '다들 들어왔어?'}));
    await waitUntil(
      () => room
          .chatHistoryOf(room.channels.defaultId)
          .any((m) => m['text'] == '다들 들어왔어?'),
      reason: '릴레이를 지난 채팅이 방에 안 닿았다',
    );

    // 내려온다.
    room.broadcast({'type': 'scene', 'scene': 'night'});
    await waitForFrame(p.inbox, 'scene');
    expect(p.inbox.last['scene'], 'night');
  });

  test('로컬과 릴레이가 한 방에서 섞여도 서로 다 받는다', () async {
    // 파티 중 한 명만 밖에 있는 경우 — 실제로 제일 흔한 모습이다.
    await server.start();
    final viaRelay = await joinViaRelay('밖에있는사람');
    addTearDown(viaRelay.ws.sink.close);

    final localSession = room.seat('여기있는사람')!.sessionToken;
    final local = WebSocketChannel.connect(
      Uri.parse(wsUrl(server.boundPort, room.roomToken)),
    );
    await local.ready;
    addTearDown(local.sink.close);
    final localInbox = <Map<String, dynamic>>[];
    local.stream.listen(
      (raw) =>
          localInbox.add(jsonDecode(raw as String) as Map<String, dynamic>),
    );
    await waitForFrame(localInbox, 'auth_required');
    authAs(local, localSession);
    await waitForFrame(localInbox, 'limits');

    room.broadcast({'type': 'scene', 'scene': 'day'});
    await waitForFrame(viaRelay.inbox, 'scene');
    await waitForFrame(localInbox, 'scene');

    final paths = room.players.map((p) => p.link?.path).toSet();
    expect(paths, containsAll([LinkPath.relay, LinkPath.direct]));
  });

  group('릴레이가 안 나르는 것', () {
    test('자료 올리기는 거절한다', () async {
      // 한 사람 30MB, 방 하나 1GB. 실시간 프레임(참가자당 2KB)과 네 자릿수
      // 차이라, 이걸 나르는 순간 "가벼운 서버" 가 아니게 된다.
      final (status, body) = await post('/api/upload?c=${client.code}', {});
      expect(status, 413);
      expect(body['error'], 'relay_refused');
    });

    test('자료 내려받기도 거절한다', () async {
      expect(await statusOf('/file/abc?c=${client.code}'), 413);
    });
  });

  group('코드', () {
    test('없는 코드로는 입장이 안 된다', () async {
      final (status, _) = await post('/api/join?c=ZZZZ', {
        'room': room.roomToken,
        'nickname': '남의파티',
      });
      expect(status, 404);
    });

    test('없는 코드로는 소켓도 안 열린다', () async {
      expect(await statusOf('/ws?c=ZZZZ&room=${room.roomToken}'), 404);
    });

    test('없는 방 토큰으로 오면 통로를 곧바로 접는다', () async {
      final ws = WebSocketChannel.connect(
        Uri.parse(
          'ws://127.0.0.1:${relay.actualPort}/ws?c=${client.code}&room=없음',
        ),
      );
      await ws.ready;
      var closed = false;
      ws.stream.listen((_) {}, onDone: () => closed = true);
      await waitUntil(() => closed, reason: '유령 연결이 릴레이에 남는다');
    });
  });

  group('호스트 재접속', () {
    test('같은 비밀이면 코드를 되찾는다', () async {
      // 파티 도중에 코드가 바뀌면 이미 나눠 준 QR 이 전부 죽는다.
      final secret = RelayClient.newSecret();
      final a = RelayClient(
        server: server,
        relayBase: 'http://127.0.0.1:${relay.actualPort}',
        secret: secret,
      );
      await a.start();
      await waitUntil(() => a.status == RelayStatus.ready);
      final code = a.code!;
      await a.stop();

      final b = RelayClient(
        server: server,
        relayBase: 'http://127.0.0.1:${relay.actualPort}',
        secret: secret,
        code: code,
      );
      await b.start();
      await waitUntil(() => b.status == RelayStatus.ready);
      expect(b.code, code);
      await b.stop();
    });

    test('남의 비밀로는 코드를 뺏지 못한다', () async {
      // 이게 없으면 아무나 남의 코드를 달라고 해서 그 파티를 가로챌 수 있다.
      final thief = RelayClient(
        server: server,
        relayBase: 'http://127.0.0.1:${relay.actualPort}',
        secret: RelayClient.newSecret(),
        code: client.code,
      );
      await thief.start();
      await waitUntil(() => thief.status == RelayStatus.ready);

      expect(thief.code, isNot(client.code), reason: '남의 방 코드를 그대로 내줬다');
      // 원래 주인은 그대로다.
      expect(relay.has(client.code!), isTrue);
      await thief.stop();
    });
  });

  test('판이 다르면 붙자마자 거절한다', () async {
    // 어긋난 채로 반쯤 도는 것이 제일 나쁘다 — 참가자는 들어와지는데
    // 화면이 안 바뀌고, 호스트는 원인을 모른다.
    final ws = WebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:${relay.actualPort}/host'),
    );
    await ws.ready;
    final seen = <Map<String, dynamic>>[];
    ws.stream.listen(
      (raw) => seen.add(jsonDecode(raw as String) as Map<String, dynamic>),
    );
    ws.sink.add(
      jsonEncode({
        't': RelayFrame.hello,
        'v': relayProtocolVersion + 99,
        'secret': RelayClient.newSecret(),
      }),
    );
    await waitUntil(() => seen.isNotEmpty);
    expect(seen.first['t'], RelayFrame.denied);
    expect(seen.first['reason'], 'version');
    await ws.sink.close();
  });

  test('짧은 비밀은 받지 않는다', () async {
    final ws = WebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:${relay.actualPort}/host'),
    );
    await ws.ready;
    final seen = <Map<String, dynamic>>[];
    ws.stream.listen(
      (raw) => seen.add(jsonDecode(raw as String) as Map<String, dynamic>),
    );
    ws.sink.add(
      jsonEncode({
        't': RelayFrame.hello,
        'v': relayProtocolVersion,
        'secret': 'short',
      }),
    );
    await waitUntil(() => seen.isNotEmpty);
    expect(seen.first['reason'], 'secret');
    await ws.sink.close();
  });

  test('입장 판정은 로컬과 같은 판정기를 쓴다 — 비밀번호도 통한다', () async {
    // 릴레이 쪽에만 검사가 빠지면, 인터넷에 열린 문만 잠금이 없다.
    room.setPin('1234');
    final (bad, _) = await post('/api/join?c=${client.code}', {
      'room': room.roomToken,
      'nickname': '몰래',
    });
    expect(bad, 401, reason: '릴레이를 지나면 비밀번호가 안 걸렸다');

    final (ok, body) = await post('/api/join?c=${client.code}', {
      'room': room.roomToken,
      'nickname': '민서',
      'pin': '1234',
    });
    expect(ok, 200);
    expect(body['session'], isNotEmpty);
  });
}
