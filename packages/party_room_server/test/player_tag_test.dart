import 'dart:convert';
import 'dart:io';

import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';

import 'support/memory_assets.dart';

/// 참가자마다 붙는 짧은 공개 식별자(tag)의 계약.
///
/// 닉네임은 겹치고 바뀌지만 식별자는 방이 끝날 때까지 고정이라, 지목·강퇴처럼
/// 되돌릴 수 없는 조작이 이 값을 근거로 삼는다. 그래서 두 가지가 동시에 성립해야 한다 —
/// 방 안에서 유일할 것, 그리고 **인증값(세션 토큰)을 조금도 흘리지 않을 것**.
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

  tearDown(() async => server.stop());

  Future<Map<String, dynamic>> post(Map<String, dynamic> body) async {
    final client = HttpClient();
    final req = await client.post('127.0.0.1', port, '/api/join');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'room': 'TESTRM', ...body}));
    final res = await req.close();
    final json = jsonDecode(await res.transform(utf8.decoder).join());
    client.close();
    return json as Map<String, dynamic>;
  }

  test('입장하면 4자 식별자를 받고, 세션 토큰과 겹치지 않는다', () async {
    final d = await post({'nickname': '지훈'});
    final tag = d['tag'] as String;
    final session = d['session'] as String;

    expect(tag.length, 4);
    // 토큰을 잘라 만들면 로비 화면에 인증값 앞자리가 그대로 노출된다.
    expect(session.contains(tag), isFalse);
  });

  test('닉네임이 같아도 식별자는 다르다', () async {
    final a = await post({'nickname': '민서'});
    final b = await post({'nickname': '민서'});

    expect(a['nickname'], b['nickname']);
    expect(a['tag'], isNot(b['tag']));
  });

  test('로비 스냅샷은 식별자를 싣고 세션 토큰은 싣지 않는다', () async {
    await post({'nickname': '지훈'});
    final row = room.lobbySnapshot().single;

    expect(row['tag'], isNotEmpty);
    expect(row.containsKey('session'), isFalse);
    expect(row.containsKey('sessionToken'), isFalse);
  });

  test('재접속해도 같은 식별자를 유지한다', () async {
    final first = await post({'nickname': '지훈'});
    final again = await post({'session': first['session']});

    expect(again['restored'], isTrue);
    expect(again['tag'], first['tag']);
  });

  test('식별자 없는 옛 상태 파일을 복원하면 새로 채워 준다', () {
    final fresh = Room()
      ..restorePlayers([
        {'sessionToken': 's1', 'nickname': '지훈'},
        {'sessionToken': 's2', 'nickname': '민서'},
      ]);

    final tags = fresh.players.map((p) => p.tag).toList();
    expect(tags.every((t) => t.length == 4), isTrue);
    expect(tags.toSet().length, 2, reason: '복원한 뒤에도 유일해야 한다');
  });
}
