import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/server/tunnel_service.dart';

/// 지난 실행이 남긴 터널 거두기.
///
/// 자식 프로세스는 부모가 죽어도 따라 죽지 않는다 — 앱을 강제 종료하면
/// cloudflared 가 살아남아 공개 주소가 계속 열려 있고, 방 토큰은 복원되므로
/// **어제 나눠준 링크가 오늘 방에 그대로 붙는다.** 이 테스트는 그 시나리오를
/// 그대로 만든다: 진짜 프로세스를 띄우고, 앱이 남겼을 흔적을 손으로 써 두고,
/// 다음 실행이 실제로 죽이는지 본다.
void main() {
  late File pidFile;

  setUp(() {
    final home = Platform.environment['HOME']!;
    pidFile = File('$home/Library/Application Support/PartyRoom/tunnel.json');
    if (pidFile.existsSync()) pidFile.deleteSync();
  });
  tearDown(() {
    if (pidFile.existsSync()) pidFile.deleteSync();
  });

  bool alive(int pid) =>
      Process.runSync('/bin/ps', ['-p', '$pid']).exitCode == 0;

  String commandName(int pid) {
    final result = Process.runSync('/bin/ps', ['-o', 'comm=', '-p', '$pid']);
    return (result.stdout as String).trim();
  }

  Future<bool> waitUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return condition();
  }

  test('남아 있던 cloudflared 를 죽인다', () async {
    // 이름이 cloudflared 인 프로세스가 필요하다. 서명된 시스템 바이너리를
    // 복사하면 서명이 깨져 즉사하고, 셸 스크립트는 프로세스 이름이 sh 로
    // 잡힌다 — 심링크가 둘 다 피한다(ps 는 심링크 경로를 보고한다).
    final dir = Directory.systemTemp.createTempSync('reap');
    final fake = Link('${dir.path}/cloudflared')..createSync('/bin/sleep');
    final proc = await Process.start(fake.path, ['30']);
    addTearDown(() async {
      proc.kill(ProcessSignal.sigkill);
      await proc.exitCode;
      dir.deleteSync(recursive: true);
    });

    // Process.start 는 fork 직후 반환할 수 있다. Linux 러너에서는 exec 가
    // 끝나기 전에 ps 를 읽으면 아직 cloudflared 로 보이지 않아 간헐적으로
    // orphan 판별이 빗나간다. 실제 명령 이름이 준비된 뒤 흔적을 남긴다.
    expect(
      await waitUntil(() => commandName(proc.pid).contains('cloudflared')),
      isTrue,
      reason: '가짜 cloudflared 프로세스가 준비되지 않았다',
    );

    pidFile.parent.createSync(recursive: true);
    pidFile.writeAsStringSync(jsonEncode({'pid': proc.pid, 'port': 8765}));
    expect(alive(proc.pid), isTrue, reason: '테스트 준비가 안 됐다');

    expect(TunnelService.reapOrphan(), isTrue);
    await proc.exitCode.timeout(const Duration(seconds: 3));
    expect(alive(proc.pid), isFalse, reason: '남은 터널이 살아 있다');
    expect(pidFile.existsSync(), isFalse, reason: '흔적이 남았다');
  });

  test('PID 가 재사용됐으면 남의 프로세스를 죽이지 않는다', () async {
    // cloudflared 가 아닌 것을 가리키는 흔적 — 죽은 뒤 PID 가 돌아온 경우다.
    final victim = await Process.start('/bin/sleep', ['30']);
    addTearDown(() => victim.kill(ProcessSignal.sigkill));
    pidFile.parent.createSync(recursive: true);
    pidFile.writeAsStringSync(jsonEncode({'pid': victim.pid, 'port': 8765}));

    expect(TunnelService.reapOrphan(), isFalse);
    await Future.delayed(const Duration(milliseconds: 200));
    expect(alive(victim.pid), isTrue, reason: '엉뚱한 프로세스를 죽였다');
    // 판단이 끝난 흔적은 어느 쪽이든 지운다.
    expect(pidFile.existsSync(), isFalse);
  });

  test('흔적이 없으면 아무 일도 없다', () {
    expect(TunnelService.reapOrphan(), isFalse);
  });
}
