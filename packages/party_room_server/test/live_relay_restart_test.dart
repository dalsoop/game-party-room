@Tags(['live-disruptive'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'support/memory_assets.dart';
import 'support/participant.dart';

/// **릴레이가 재시작되면 파티는 어떻게 되나.**
///
/// 이건 예외 상황이 아니라 **일상**이다. 이미지를 올리는 것도, 값을 바꾸는
/// 것도, 노드가 갈리는 것도 전부 파드 재시작이다. 그때마다 나눠 준 QR 이
/// 죽는다면 이 서버는 운영할 수 없다 — 파티 중에는 손도 못 댄다는 뜻이니까.
///
/// 기대하는 동작:
///   1. 호스트가 스스로 다시 붙는다 (사람이 손대지 않는다)
///   2. **같은 방 코드**를 되찾는다 (이미 뿌린 QR 이 살아 있다)
///   3. 참가자가 그 코드로 다시 들어올 수 있다
///
/// 태그가 `live` 가 아니라 **`live-disruptive`** 인 이유: 이 테스트는 모두가
/// 쓰는 배포를 실제로 갈아 끼운다. `-t live` 로 다른 실물 테스트와 함께
/// 돌리면 그쪽이 한창일 때 파드를 죽여 **엉뚱한 실패**를 만든다(실제로 그랬다).
/// 혼자 돌려야 한다.
///
///   dart test test/live_relay_restart_test.dart -t live-disruptive --run-skipped
void main() {
  final base = Platform.environment['RELAY_BASE'] ?? 'https://relay.ranode.net';
  final pve = Platform.environment['PVE_HOST'] ?? 'root@192.168.2.50';

  Future<String> ssh(String cmd) async {
    final r = await Process.run('ssh', ['-o', 'BatchMode=yes', pve, cmd]);
    return '${r.stdout}${r.stderr}'.trim();
  }

  test('릴레이를 재시작해도 방 코드가 살아남는다', () async {
    final server = RoomServer(assets: MemoryAssets(), port: 0);
    final room = server.createRoom(name: '재시작 확인');
    addTearDown(server.stop);

    final client = RelayClient(
      server: server,
      relayBase: base,
      // 코드를 되찾는 열쇠. 앱은 이걸 설정에 저장해 두고 매번 같은 것을 쓴다.
      secret: RelayClient.newSecret(),
    );
    await client.start();
    addTearDown(client.stop);

    await waitUntil(
      () => client.status == RelayStatus.ready,
      timeout: const Duration(seconds: 30),
      reason: '첫 접속에서 코드를 못 받았다',
    );
    final code = client.code!;
    // ignore: avoid_print
    print('  재시작 전 코드: $code');

    // ---- 파드를 갈아 끼운다 (업그레이드와 같은 일) ----
    final out = await ssh(
      'kubectl -n party-room-relay rollout restart deploy/party-room-relay '
      '&& kubectl -n party-room-relay rollout status deploy/party-room-relay '
      '--timeout=120s',
    );
    // ignore: avoid_print
    print('  $out');
    expect(out, contains('successfully rolled out'));

    // ---- 호스트가 스스로 돌아온다 ----
    await waitUntil(
      () => client.status == RelayStatus.ready,
      // 재접속 백오프가 1·2·4·8·15·30초로 늘어난다. 최악을 넉넉히 잡는다.
      timeout: const Duration(seconds: 90),
      reason: '재시작 뒤 호스트가 다시 안 붙었다 (상태 ${client.status})',
    );
    expect(client.code, code, reason: '코드가 바뀌면 이미 나눠 준 QR 이 전부 죽는다');
    // ignore: avoid_print
    print('  재시작 후 코드: ${client.code}');

    // ---- 그 코드로 참가자가 실제로 들어온다 ----
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final req = await http.postUrl(Uri.parse('$base/api/join?c=$code'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'room': room.roomToken, 'nickname': '재시작후'}));
    final res = await req.close();
    final body =
        jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    expect(res.statusCode, 200, reason: '재시작 뒤 입장이 막혔다: $body');

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

    await waitUntil(() => room.players.any((p) => p.connected));
    expect(room.players.single.link!.path, LinkPath.relay);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
