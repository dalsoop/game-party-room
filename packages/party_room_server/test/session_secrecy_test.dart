import 'dart:convert';
import 'dart:io';

import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

import 'support/memory_assets.dart';
import 'support/participant.dart';

/// 세션 토큰은 폰으로 내려가지 않는다.
///
/// 세션 토큰은 이 앱의 **인증 자격증명**이다 — 인증 프레임으로 그 사람이
/// 되고, `/api/join {session}` 으로 자리를 이어받는다. 예전에는 마피아 밤
/// 장면의 지목 대상 목록에 남의 세션 토큰이 그대로 실려서, 참가자 아무나
/// 자기 폰에서 그것을 읽어 (1) 남의 비밀 역할을 받아 보고 (2) 대신 투표하고
/// (3) 같은 세션의 이전 소켓을 닫아 그 사람을 끊어 버릴 수 있었다.
/// 비밀 역할이 이 게임의 존재 이유라, 여기가 무너지면 앱이 무너진다.
///
/// 지목은 공개 태그로 하고 서버가 태그→세션을 푼다. 이 테스트는 그 계약이
/// 깨지는 순간(누가 다시 스냅샷에 세션을 넣는 순간) 바로 터진다.
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

  /// 참가자 넷을 붙이고 각자가 받은 메시지를 모아 준다.
  Future<
    ({
      Map<String, String> sessions,
      Map<String, List<Map<String, dynamic>>> inbox,
      List<IOWebSocketChannel> sockets,
    })
  >
  seatFour() async {
    final sessions = <String, String>{};
    final inbox = <String, List<Map<String, dynamic>>>{};
    final sockets = <IOWebSocketChannel>[];
    for (final n in ['A', 'B', 'C', 'D']) {
      final s = await join(n);
      sessions[n] = s;
      inbox[n] = [];
      final ws = IOWebSocketChannel(
        await WebSocket.connect(wsUrl(port, 'TESTRM')),
      );
      authAs(ws, s);
      sockets.add(ws);
      ws.stream.listen(
        (m) => inbox[n]!.add(jsonDecode(m as String) as Map<String, dynamic>),
      );
    }
    await Future.delayed(const Duration(milliseconds: 200));
    return (sessions: sessions, inbox: inbox, sockets: sockets);
  }

  /// 받은 것 전부를 문자열로 펴서 남의 토큰이 섞였는지 본다.
  void expectNoForeignTokens(
    String who,
    List<Map<String, dynamic>> inbox,
    Map<String, String> sessions,
  ) {
    final raw = jsonEncode(inbox);
    for (final e in sessions.entries) {
      if (e.key == who) continue;
      expect(
        raw.contains(e.value),
        isFalse,
        reason: '$who 가 받은 메시지에 $who 아닌 ${e.key} 의 세션 토큰이 들어 있다',
      );
    }
  }

  test('마피아 — 밤·낮·투표 어디서도 남의 세션 토큰이 안 보인다', () async {
    final r = await seatFour();
    final game = MafiaGame();
    room.startGame(game);

    game.beginNight(room.gameCtx);
    await Future.delayed(const Duration(milliseconds: 150));
    game.beginDay(room.gameCtx);
    await Future.delayed(const Duration(milliseconds: 150));
    game.beginVote(room.gameCtx);
    await Future.delayed(const Duration(milliseconds: 200));

    for (final who in r.sessions.keys) {
      expectNoForeignTokens(who, r.inbox[who]!, r.sessions);
    }
    // 그러면서도 지목은 가능해야 한다 — 태그가 실려 있어야 화면이 그려진다.
    // 밤에 행동하는 역할은 배역 뽑기에 달렸으니 특정인을 가정하지 않는다.
    final targets = [
      for (final list in r.inbox.values)
        for (final m in list)
          if (m['scene'] == 'mafia_night' && (m['targets'] as List).isNotEmpty)
            ...(m['targets'] as List).cast<Map<String, dynamic>>(),
    ];
    expect(targets, isNotEmpty, reason: '밤에 행동할 수 있는 역할이 하나도 없었다');
    expect(targets.first, contains('tag'));
    expect(targets.first, isNot(contains('session')));

    for (final s in r.sockets) {
      await s.sink.close();
    }
  });

  test('마피아 — 태그로 보낸 투표가 실제로 집계된다', () async {
    final r = await seatFour();
    final game = MafiaGame();
    room.startGame(game);
    game.beginNight(room.gameCtx);
    game.beginDay(room.gameCtx);
    game.beginVote(room.gameCtx);
    await Future.delayed(const Duration(milliseconds: 200));

    final vote = r.inbox['A']!.lastWhere((m) => m['scene'] == 'mafia_vote');
    final victimTag =
        ((vote['targets'] as List).first as Map<String, dynamic>)['tag']
            as String;
    r.sockets[0].sink.add(
      jsonEncode({'type': 'mafia_vote', 'target': victimTag}),
    );
    await Future.delayed(const Duration(milliseconds: 200));

    expect(
      r.inbox['A']!.any((m) => m['type'] == 'mafia_vote_ack'),
      isTrue,
      reason: '태그 지목이 서버에서 세션으로 풀리지 않았다',
    );
    for (final s in r.sockets) {
      await s.sink.close();
    }
  });

  test('마피아 — 세션 토큰을 그대로 지목해도 먹히지 않는다', () async {
    final r = await seatFour();
    final game = MafiaGame();
    room.startGame(game);
    game.beginNight(room.gameCtx);
    game.beginDay(room.gameCtx);
    game.beginVote(room.gameCtx);
    await Future.delayed(const Duration(milliseconds: 200));

    // 옛 클라이언트(또는 토큰을 어디선가 주운 사람)가 세션으로 지목하면
    // 조용히 무시돼야 한다 — 태그 공간과 토큰 공간이 섞이면 안 된다.
    r.sockets[0].sink.add(
      jsonEncode({'type': 'mafia_vote', 'target': r.sessions['B']}),
    );
    await Future.delayed(const Duration(milliseconds: 200));
    expect(r.inbox['A']!.any((m) => m['type'] == 'mafia_vote_ack'), isFalse);

    for (final s in r.sockets) {
      await s.sink.close();
    }
  });

  test('라이어 — 지목 대상 목록에 세션 토큰이 없고 태그 투표가 먹는다', () async {
    final r = await seatFour();
    final game = LiarGame();
    room.startGame(game);
    game.beginVote(room.gameCtx);
    await Future.delayed(const Duration(milliseconds: 200));

    for (final who in r.sessions.keys) {
      expectNoForeignTokens(who, r.inbox[who]!, r.sessions);
    }

    final vote = r.inbox['A']!.lastWhere((m) => m['scene'] == 'liar_vote');
    final tag =
        ((vote['targets'] as List).first as Map<String, dynamic>)['tag']
            as String;
    r.sockets[0].sink.add(jsonEncode({'type': 'liar_vote', 'target': tag}));
    await Future.delayed(const Duration(milliseconds: 200));
    expect(r.inbox['A']!.any((m) => m['type'] == 'liar_vote_ack'), isTrue);

    for (final s in r.sockets) {
      await s.sink.close();
    }
  });

  test('로비 명단에도 세션 토큰이 없다', () async {
    final r = await seatFour();
    for (final who in r.sessions.keys) {
      expectNoForeignTokens(who, r.inbox[who]!, r.sessions);
    }
    for (final s in r.sockets) {
      await s.sink.close();
    }
  });
}
