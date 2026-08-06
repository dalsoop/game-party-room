import 'dart:convert';
import 'dart:io';

import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

import 'support/memory_assets.dart';
import 'support/participant.dart';

/// 입장 비밀번호는 폰으로 내려가지 않는다.
///
/// PIN 은 4자리, 1만 가지뿐이다. 한 번이라도 프레임에 실려 나가면 그 방의
/// 두 번째 자물쇠는 그냥 없는 것이 된다 — 이미 들어와 있는 사람이 자기 폰에서
/// 읽어 다른 단톡방에 그대로 붙일 수 있기 때문이다. 그래서 밖에서 보이는 것은
/// `hasPin` 불리언까지고, 원문은 이 맥의 저장 파일에만 산다.
///
/// 이 테스트는 누가 편의를 위해 방 스냅샷에 `pin` 을 얹는 순간 터진다.
void main() {
  final assets = MemoryAssets();
  late RoomServer server;
  late Room room;
  late int port;

  const pin = '4907';

  setUp(() async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = probe.port;
    await probe.close();
    server = RoomServer(assets: assets, port: port);
    room = server.createRoom(token: 'PINRM1', name: '금요 모임');
    room.setPin(pin);
    await server.start();
  });
  tearDown(() => server.stop());

  Future<Map<String, dynamic>> join(String nick, {String? withPin}) async {
    final c = HttpClient();
    final req = await c.post('127.0.0.1', port, '/api/join');
    req.headers.contentType = ContentType.json;
    req.write(
      jsonEncode({'room': 'PINRM1', 'nickname': nick, 'pin': ?withPin}),
    );
    final res = await req.close();
    final body =
        jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    c.close();
    return body;
  }

  test('맞는 비밀번호로 들어간 사람도 원문은 못 본다', () async {
    final joined = await join('민서', withPin: pin);
    expect(joined['session'], isNotNull, reason: '맞는 비밀번호인데 못 들어갔다');
    expect(jsonEncode(joined).contains(pin), isFalse, reason: '입장 응답에 원문이 실렸다');

    final inbox = <Map<String, dynamic>>[];
    final ws = IOWebSocketChannel(
      await WebSocket.connect(wsUrl(port, 'PINRM1')),
    );
    authAs(ws, joined['session'] as String?);
    ws.stream.listen(
      (m) => inbox.add(jsonDecode(m as String) as Map<String, dynamic>),
    );
    await Future.delayed(const Duration(milliseconds: 200));

    // 판까지 돌려 본다 — 장면 프레임에 방 정보가 얹혀 나가는 경로가 여럿이다.
    room.startGame(LiarGame());
    room.hostChat('시작합니다');
    await Future.delayed(const Duration(milliseconds: 200));

    expect(inbox, isNotEmpty, reason: '아무것도 안 받았으면 검사가 무의미하다');
    expect(
      jsonEncode(inbox).contains(pin),
      isFalse,
      reason: '폰이 받은 프레임 어딘가에 비밀번호 원문이 들어 있다',
    );
    await ws.sink.close();
  });

  test('틀린 비밀번호는 거절하고, 거절하면서도 흘리지 않는다', () async {
    final denied = await join('태윤', withPin: '0000');
    expect(denied['session'], isNull);
    expect(denied['error'], 'pin_required');
    expect(jsonEncode(denied).contains(pin), isFalse);
  });

  test('비밀번호를 안 내면 잠긴 방이라고만 알려 준다', () async {
    final denied = await join('지우');
    expect(denied['error'], 'pin_required');
    expect(jsonEncode(denied).contains(pin), isFalse);
  });

  test('연타하면 잠긴다 — 1만 가지를 훑지 못하게', () async {
    for (var i = 0; i < 5; i++) {
      await join('서준', withPin: '000$i');
    }
    final locked = await join('서준', withPin: '0001');
    expect(locked['error'], 'pin_locked');
    expect(
      (locked['retryAfter'] as num).toInt(),
      greaterThan(0),
      reason: '얼마나 기다려야 하는지 안 알려주면 화면이 안내를 못 쓴다',
    );
  });

  test('저장 파일에는 남는다 — 껐다 켜도 자물쇠가 풀리면 안 되니까', () async {
    final store = MemoryStateStore();
    final p = RoomPersistence(store, assets);
    await p.save(server);

    final revived = RoomServer(assets: assets);
    await p.restoreInto(revived);
    expect(revived.rooms.single.hasPin, isTrue, reason: '재시작에 자물쇠가 조용히 풀렸다');

    // 되살아난 방도 원문을 요구한다.
    expect(revived.rooms.single.admits('0000').error, 'pin_required');
    expect(revived.rooms.single.admits(pin).error, isNull);
  });

  test('원문이 실리는 곳은 저장용 toJson 하나뿐이다', () {
    // 예외가 하나라는 것 자체를 못 박아 둔다. 화면·CLI·상태 미러는 저마다
    // 요약을 만들어 쓰는데, 그때 편하다고 toJson 을 갖다 쓰면 새는 것이라
    // 여기서 "이건 저장 전용" 이라고 남긴다.
    expect(jsonEncode(room.toJson()).contains(pin), isTrue);
    expect(room.hasPin, isTrue, reason: '잠긴 방인지는 보여야 자물쇠를 그린다');
  });

  test('임자 없는 방은 아무나 그냥 들어온다 — 잠금은 옵션이다', () async {
    final open = server.createRoom(token: 'OPENRM');
    expect(open.hasPin, isFalse);
    expect(open.admits(null).error, isNull);
  });

  test('비밀번호를 풀면 다시 그냥 들어온다', () {
    expect(room.setPin(null), isTrue);
    expect(room.hasPin, isFalse);
    expect(room.admits(null).error, isNull);
  });

  test('4자리 숫자가 아니면 안 걸린다', () {
    final r = server.createRoom(token: 'BADPIN');
    for (final bad in ['123', '12345', 'abcd', '12 4', '１２３４']) {
      expect(r.setPin(bad), isFalse, reason: '$bad 를 비밀번호로 받아 버렸다');
      expect(r.hasPin, isFalse);
    }
  });
}
