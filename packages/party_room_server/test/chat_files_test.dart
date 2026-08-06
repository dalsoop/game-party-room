import 'dart:convert';
import 'dart:io';

import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

import 'support/memory_assets.dart';
import 'support/participant.dart';

/// 단톡·자료 공유의 계약.
///
/// 채팅: 전원 브로드캐스트 + 늦게 들어온 사람에게 백로그 + 도배 억제.
/// 자료: 방 토큰 없인 못 받고, 세션 없인 못 올리고, 내려받은 바이트가
/// 올린 바이트와 같아야 한다 — 파일 채널의 전부다.
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

  /// 붙고 나서 첫 프레임으로 누구인지 밝힌다 — 실제 참가자와 같은 길.
  IOWebSocketChannel connect(Map<String, dynamic> joined) {
    final ws = IOWebSocketChannel.connect(wsUrl(port, 'TESTRM'));
    ws.ready.then((_) => authAs(ws, joined['session'] as String?));
    return ws;
  }

  group('단톡', () {
    test('메시지가 전원에게 가고, 늦게 온 사람은 백로그를 받는다', () async {
      final a = await join('먼저');
      final wsA = connect(a);
      await wsA.ready;
      final seenA = <Map<String, dynamic>>[];
      wsA.stream.listen(
        (raw) => seenA.add(jsonDecode(raw as String) as Map<String, dynamic>),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      wsA.sink.add(jsonEncode({'type': 'chat', 'text': '안녕들 하세요'}));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        seenA.where((m) => m['type'] == 'chat_msg').single['text'],
        '안녕들 하세요',
        reason: '보낸 사람 자신에게도 브로드캐스트로 돌아온다',
      );

      // 늦게 입장한 참가자 — 접속 즉시 백로그를 받는다.
      final b = await join('나중');
      final wsB = connect(b);
      await wsB.ready;
      final seenB = <Map<String, dynamic>>[];
      wsB.stream.listen(
        (raw) => seenB.add(jsonDecode(raw as String) as Map<String, dynamic>),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final history = seenB.where((m) => m['type'] == 'chat_history').single;
      expect(
        (history['items'] as List).map((m) => (m as Map)['text']),
        contains('안녕들 하세요'),
      );

      await wsA.sink.close();
      await wsB.sink.close();
    });

    test('300ms 안에 연타하면 버린다 (도배 억제)', () async {
      final a = await join('도배꾼');
      final ws = connect(a);
      await ws.ready;
      await Future<void>.delayed(const Duration(milliseconds: 150));

      for (var i = 0; i < 5; i++) {
        ws.sink.add(jsonEncode({'type': 'chat', 'text': '도배 $i'}));
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(room.chatHistory.length, 1, reason: '즉시 연타는 첫 건만 남아야 한다');
      await ws.sink.close();
    });

    test('호스트 메시지도 기록·전파된다', () async {
      room.hostChat('공지: 치킨 도착');
      final msg = room.chatHistory.single;
      // 서버는 **역할**만 싣는다 — '호스트' 라는 문구는 화면이 붙인다.
      expect(msg['speaker'], Speaker.host);
      expect(msg['nickname'], isNull, reason: '표시 이름이 서버에서 새어 나왔다');
      expect(msg['text'], '공지: 치킨 도착');
    });

    test('사회자는 호스트와 다른 역할로 남는다', () {
      room.mcChat('밤이 되었습니다');
      expect(room.chatHistory.single['speaker'], Speaker.mc);
    });
  });

  group('자료 공유', () {
    late File source;

    setUp(() async {
      source = File(
        '${Directory.systemTemp.path}/party_test_${DateTime.now().microsecondsSinceEpoch}.txt',
      );
      await source.writeAsString('파티룸 공유 파일 내용물');
    });

    tearDown(() async {
      if (await source.exists()) await source.delete();
    });

    test('호스트 공유 → 목록 → 내려받기 바이트가 같다', () async {
      final shared = await room.shareFile(source.path);
      expect(shared, isNotNull);
      expect(room.sharedFiles.single.name, source.uri.pathSegments.last);

      final client = HttpClient();
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/file/${shared!.id}?room=TESTRM'),
      );
      final res = await req.close();
      expect(res.statusCode, 200);
      expect(res.headers.value('content-disposition'), contains('attachment'));
      final body = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(utf8.decode(body), '파티룸 공유 파일 내용물');
      client.close();
    });

    test('방 토큰이 틀리면 내려받을 수 없다', () async {
      final shared = await room.shareFile(source.path);
      final client = HttpClient();
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/file/${shared!.id}?room=WRONG'),
      );
      final res = await req.close();
      expect(res.statusCode, 403);
      client.close();
    });

    test('참가자 업로드 → 목록에 올린 사람이 붙고, 내려받으면 같은 바이트', () async {
      final a = await join('사진사');
      final client = HttpClient();
      final req = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:$port/api/upload?room=TESTRM'
          '&name=${Uri.encodeComponent("모임사진.jpg")}',
        ),
      );
      // 세션은 헤더로 — 주소에 담으면 로그에 자격증명이 남는다.
      req.headers.set('x-party-session', a['session'] as String);
      req.add(List<int>.generate(1024, (i) => i % 251));
      final res = await req.close();
      final body =
          jsonDecode(await res.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(body['ok'], isTrue);

      final f = room.sharedFiles.single;
      expect(f.name, '모임사진.jpg');
      expect(f.ownerName, '사진사');
      expect(f.mime, 'image/jpeg');

      final dl = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/file/${f.id}?room=TESTRM'),
      );
      final got = await (await dl.close()).fold<List<int>>(
        [],
        (acc, b) => acc..addAll(b),
      );
      expect(got, List<int>.generate(1024, (i) => i % 251));
      client.close();
    });

    test('세션 없는 업로드는 거절한다', () async {
      final client = HttpClient();
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:$port/api/upload?room=TESTRM&name=a.txt'),
      );
      req.add([1, 2, 3]);
      final res = await req.close();
      expect(res.statusCode, 403);
      client.close();
    });
  });
}
