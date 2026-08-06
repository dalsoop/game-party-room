import 'package:game_party_room_app/server/app/bundle_assets.dart';
import 'package:party_room_server/party_room_server.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  group('역할 편성', () {
    test('인원수만큼 정확히 배정된다', () {
      for (var n = 4; n <= 20; n++) {
        expect(MafiaGame.compositionForTest(n).length, n, reason: '$n인 편성 길이');
      }
    });

    test('시작하자마자 마피아 승리인 편성은 없다', () {
      // 승리 판정이 `마피아팀 >= 시민팀` 이므로 편성 단계에서 이미 걸리면 게임이 성립 안 된다.
      for (var n = 4; n <= 20; n++) {
        final roles = MafiaGame.compositionForTest(n);
        final mafiaTeam = roles.where((r) => r.team == 'mafia').length;
        final others = roles.length - mafiaTeam;
        expect(
          mafiaTeam < others,
          isTrue,
          reason: '$n인: 마피아팀 $mafiaTeam vs 시민팀 $others',
        );
      }
    });

    test('마피아(킬 능력자)가 항상 1명 이상이다', () {
      for (var n = 4; n <= 20; n++) {
        expect(
          MafiaGame.compositionForTest(
            n,
          ).where((r) => r == MafiaRole.mafia).length,
          greaterThanOrEqualTo(1),
          reason: '$n인',
        );
      }
    });
  });

  group('밤 진행률 (실제 서버·소켓)', () {
    late RoomServer server;
    late Room room;
    late int port;
    final sockets = <IOWebSocketChannel>[];
    final inbox = <String, List<Map<String, dynamic>>>{};

    setUp(() async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      port = probe.port;
      await probe.close();
      server = RoomServer(assets: const BundleAssetSource(), port: port);
      room = server.createRoom(token: 'TESTRM');
      await server.start();
    });

    tearDown(() async {
      for (final s in sockets) {
        await s.sink.close();
      }
      sockets.clear();
      inbox.clear();
      await server.stop();
    });

    /// 참가자 n 명을 실제로 입장·연결시킨다. start() 가 connected 만 추리므로
    /// 소켓을 진짜로 붙여야 게임이 성립한다.
    Future<List<String>> seatPlayers(int n) async {
      final client = HttpClient();
      final tokens = <String>[];
      for (var i = 0; i < n; i++) {
        final req = await client.post('127.0.0.1', port, '/api/join');
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({'room': 'TESTRM', 'nickname': 'p$i'}));
        final res = await req.close();
        final body =
            jsonDecode(await res.transform(utf8.decoder).join())
                as Map<String, dynamic>;
        tokens.add(body['session'] as String);
      }
      client.close();

      for (final t in tokens) {
        // 세션은 주소가 아니라 **첫 프레임**으로 밝힌다 — 주소에 담으면
        // 자격증명이 방문기록·프록시 로그에 남는다.
        final ws = IOWebSocketChannel.connect(
          Uri.parse('ws://127.0.0.1:$port/ws?room=TESTRM'),
        );
        await ws.ready;
        sockets.add(ws);
        ws.stream.listen(
          (m) => (inbox[t] ??= []).add(
            jsonDecode(m as String) as Map<String, dynamic>,
          ),
        );
        ws.sink.add(jsonEncode({'type': 'auth', 'session': t}));
      }
      // 전원이 자리에 앉을 때까지 — 고정 지연은 기계가 바쁘면 밀린다.
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (room.players.where((p) => p.connected).length < tokens.length) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('참가자가 다 안 붙었다');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return tokens;
    }

    /// 참가자가 받은 역할 배정 메시지에서 역할 이름을 읽는다.
    String roleOf(String token) =>
        inbox[token]!.lastWhere((m) => m['scene'] == 'mafia_role')['role']
            as String;

    test('1회성 역할(저격수)이 행동해도 진행률이 분모를 넘지 않는다', () async {
      // 저격수가 편성되는 최소 인원은 11인.
      final tokens = await seatPlayers(11);
      final game = MafiaGame();
      room.startGame(game);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final progress = <Map<String, dynamic>>[];
      // 이벤트에 방이 함께 실린다 — 판은 여러 방에서 동시에 돌 수 있다.
      room.gameEvents.listen((e) {
        if (e.$1 == 'mafia_night_progress') progress.add(e.$2);
      });

      game.beginNight(room.gameCtx);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final sniper = tokens.firstWhere((t) => roleOf(t) == 'sniper');
      // 저격수부터 쏘게 해 소진 플래그를 먼저 켠다 — 예전엔 이 순간 분모가 줄었다.
      final ordered = [sniper, ...tokens.where((t) => t != sniper)];
      // 지목은 **공개 태그**로 한다 — 세션 토큰은 참가자 폰에 내려가지 않는다
      // (test/session_secrecy_test.dart 가 그 계약을 지킨다).
      String tagOf(String token) =>
          room.players.firstWhere((p) => p.sessionToken == token).tag;

      for (final t in ordered) {
        final other = tokens.firstWhere((o) => o != t);
        game.onMessage(
          room.gameCtx,
          room.players.firstWhere((p) => p.sessionToken == t),
          {'type': 'mafia_night_act', 'target': tagOf(other)},
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(progress, isNotEmpty);
      for (final p in progress) {
        expect(
          p['done'] as int,
          lessThanOrEqualTo(p['total'] as int),
          reason: '진행률이 분모를 넘었다: ${p['done']}/${p['total']}',
        );
      }
      expect(
        progress.last['allDone'],
        isTrue,
        reason: '행동 가능한 전원이 마쳤으면 allDone 이어야 한다',
      );
    });
  });
}
