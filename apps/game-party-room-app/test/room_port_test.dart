import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/server/host_address.dart';
import 'package:party_room_server/party_room_server.dart';

import 'support/memory_assets.dart';

/// 기본 포트가 막혔을 때.
///
/// 예전에는 무조건 "이미 파티룸이 실행 중입니다" 였다. 8765 를 쓰는 것이
/// 파티룸만은 아니라, 남의 개발 서버 하나 때문에 앱이 안 열리고 원인 문구도
/// 틀렸다. 파티룸이면 안내하고, 남이면 비켜 앉는다.
void main() {
  test('비어 있으면 그 포트를 쓴다', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final free = probe.port;
    await probe.close();

    final (port, err) = await RoomPort.pick(start: free);
    expect(err, isNull);
    expect(port, free);
  });

  test('남이 물고 있으면 옆 포트로 비켜 앉는다', () async {
    final busy = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    addTearDown(busy.close);

    final (port, err) = await RoomPort.pick(start: busy.port);
    expect(err, isNull, reason: '남의 서버 때문에 앱이 안 열리면 안 된다');
    expect(port, isNot(busy.port));
    expect(port, greaterThan(busy.port));
  });

  test('파티룸이 물고 있으면 비켜 앉지 않고 알려 준다', () async {
    // 진짜 방 서버를 띄운다 — 참가자 화면으로 우리를 식별한다.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final taken = probe.port;
    await probe.close();
    final server = RoomServer(assets: MemoryAssets(), port: taken);
    await server.start();
    addTearDown(server.stop);

    final (port, err) = await RoomPort.pick(start: taken);
    expect(port, isNull);
    expect(err, contains('이미 파티룸이 실행 중'));
    expect(err, contains('$taken'));
  });

  test('전부 막혀 있으면 사람이 읽을 이유를 준다', () async {
    final held = <ServerSocket>[];
    final first = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    held.add(first);
    for (var p = first.port + 1; p < first.port + 3; p++) {
      try {
        held.add(await ServerSocket.bind(InternetAddress.anyIPv4, p));
      } catch (_) {
        // 이미 남이 쓰고 있으면 그것대로 막힌 것이라 목적에 맞다.
      }
    }
    addTearDown(() async {
      for (final s in held) {
        await s.close();
      }
    });

    final (port, err) = await RoomPort.pick(start: first.port, tries: 3);
    expect(port, isNull);
    expect(err, contains('사용 중'));
  });
}
