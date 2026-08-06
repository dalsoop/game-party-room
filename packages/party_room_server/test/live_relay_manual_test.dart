@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'support/memory_assets.dart';
import 'support/participant.dart';

/// **진짜 배포된 랑데부**에 붙어 한 판 돌린다.
///
/// 평소 스위트에서는 안 돈다(`-t live` 로만). 인터넷과 남의 서버에 기대는
/// 테스트를 기본으로 두면, 그쪽이 잠깐 흔들릴 때마다 우리 빨간불이 된다.
///
/// 그래도 이게 있어야 하는 이유: 루프백에서 도는 것과 **Cloudflare·traefik·
/// 파드를 다 지나서** 도는 것은 다른 문제다. 웹소켓이 중간에서 잘리거나,
/// 프록시가 프레임을 뭉개거나, 판이 어긋나면 여기서만 드러난다.
///
///   dart test test/live_relay_manual_test.dart -t live
void main() {
  final base = Platform.environment['RELAY_BASE'] ?? 'https://relay.ranode.net';

  test('배포된 랑데부로 참가자가 들어와 말이 오간다', () async {
    final server = RoomServer(assets: MemoryAssets(), port: 0);
    final room = server.createRoom(name: '실전 확인');
    addTearDown(server.stop);

    final client = RelayClient(
      server: server,
      relayBase: base,
      secret: RelayClient.newSecret(),
    );
    await client.start();
    addTearDown(client.stop);

    await waitUntil(
      () => client.status == RelayStatus.ready,
      timeout: const Duration(seconds: 30),
      reason: '랑데부가 방 코드를 안 줬다 (상태 ${client.status})',
    );
    final code = client.code!;
    // ignore: avoid_print
    print('  방 코드: $code · ${client.joinUrl(room.roomToken)}');

    // ---- 참가자: 입장 API (릴레이가 호스트에게 물어다 준다) ----
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final req = await http.postUrl(Uri.parse('$base/api/join?c=$code'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'room': room.roomToken, 'nickname': '밖에있는사람'}));
    final res = await req.close();
    final body =
        jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    expect(res.statusCode, 200, reason: '입장이 거절됐다: $body');

    // ---- 참가자: 소켓 ----
    final ws = WebSocketChannel.connect(
      Uri.parse(
        '${base.replaceFirst("https", "wss")}/ws'
        '?c=$code&room=${Uri.encodeComponent(room.roomToken)}',
      ),
    );
    await ws.ready;
    addTearDown(ws.sink.close);
    final inbox = <Map<String, dynamic>>[];
    ws.stream.listen(
      (raw) => inbox.add(jsonDecode(raw as String) as Map<String, dynamic>),
    );

    await waitForFrame(
      inbox,
      'auth_required',
      timeout: const Duration(seconds: 20),
    );
    authAs(ws, body['session'] as String);
    await waitForFrame(inbox, 'limits', timeout: const Duration(seconds: 20));

    // 자료 기능은 닫혀 있어야 한다 — 남의 서버로 30MB 를 안 나른다.
    final limits = inbox.firstWhere((m) => m['type'] == 'limits');
    expect(limits['canFiles'], isFalse);

    await waitUntil(() => room.players.any((p) => p.connected));
    expect(room.players.single.link!.path, LinkPath.relay);

    // ---- 말이 오간다 ----
    ws.sink.add(jsonEncode({'type': 'chat', 'text': '인터넷 너머에서 왔습니다'}));
    await waitUntil(
      () => room
          .chatHistoryOf(room.channels.defaultId)
          .any((m) => m['text'] == '인터넷 너머에서 왔습니다'),
      timeout: const Duration(seconds: 20),
      reason: '올라가는 방향이 막혔다',
    );

    room.broadcast({'type': 'scene', 'scene': 'night'});
    await waitForFrame(inbox, 'scene', timeout: const Duration(seconds: 20));
    expect(inbox.last['scene'], 'night');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
