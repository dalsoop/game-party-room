import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/host_controller.dart';
import 'package:game_party_room_app/server/app/bundle_assets.dart';
import 'package:game_party_room_app/server/control_service.dart';
import 'package:game_party_room_app/server/control_snapshot.dart';
import 'package:party_room_server/party_room_server.dart';
import 'package:party_room_server/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 랑데부를 **화면 없이** 확인할 수 있는가.
///
/// 이 앱의 규약은 GUI·Core·CLI·StateMirror 넷이 함께 붙어야 완료다. 랑데부는
/// 한동안 화면에만 있었다 — 켜져 있는지, 방 코드가 뭔지, 밖에서 몇 명이
/// 들어와 있는지를 `partyroom` 으로도 `state.json` 으로도 알 수 없었다.
/// 남의 서버를 거치는 길이라 오히려 **더** 보여야 하는 자리다.
void main() {
  _roomPolicy();
  _relaySet();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  HostController host() {
    final ctrl = HostController();
    addTearDown(ctrl.dispose);
    final srv = RoomServer(assets: const BundleAssetSource(), port: 0);
    srv.createRoom(name: '금요 모임');
    ctrl.server = srv;
    ctrl.room = srv.rooms.first;
    return ctrl;
  }

  group('상태 미러', () {
    test('꺼져 있어도 랑데부 칸이 있다', () {
      // 없는 것과 꺼진 것을 구분할 수 없으면 "왜 아무도 못 들어오지" 를
      // 답할 수 없다. 필드가 아예 없으면 읽는 쪽은 옛 버전인지 꺼진 건지 모른다.
      final snap = ControlSnapshot(host()).build();
      expect(snap['relay'], isA<Map<String, dynamic>>());
      final relay = snap['relay'] as Map<String, dynamic>;
      expect(relay['status'], 'off');
      expect(relay['configured'], isFalse);
      expect(relay['code'], isNull);
    });

    test('서버 주소를 정하면 configured 가 뜬다', () {
      final ctrl = host();
      ctrl.settings.setRelayBase('https://relay.ranode.net');
      final relay =
          ControlSnapshot(ctrl).build()['relay'] as Map<String, dynamic>;
      expect(relay['configured'], isTrue);
      expect(relay['base'], 'https://relay.ranode.net');
      // 아직 안 켰으므로 상태는 off 다 — 주소가 있다고 도는 게 아니다.
      expect(relay['status'], 'off');
    });

    test('이 길로 들어온 사람 수를 센다', () {
      // "켜짐" 만 보고 잘 돌고 있다고 판단하면 안 된다. 코드는 받았는데
      // 아무도 그 길로 안 들어와 있을 수 있고, 그건 QR 이 잘못 퍼진 것이다.
      final ctrl = host();
      final room = ctrl.room!;
      room.seat('밖1')!.link = RecordingLink(path: LinkPath.relay);
      room.seat('밖2')!.link = RecordingLink(path: LinkPath.relay);
      room.seat('여기')!.link = RecordingLink();

      final relay = relayStatusMap(ctrl);
      expect(relay['participants'], 2, reason: '로컬 참가자까지 세면 안 된다');
    });

    test('여러 방에 흩어져 있어도 합쳐 센다', () {
      final ctrl = host();
      final second = ctrl.server!.createRoom(name: '옆 방');
      ctrl.room!.seat('밖1')!.link = RecordingLink(path: LinkPath.relay);
      second.seat('밖2')!.link = RecordingLink(path: LinkPath.relay);

      expect(relayStatusMap(ctrl)['participants'], 2);
    });
  });

  group('CLI 표면', () {
    test('capabilities 에 나온다', () {
      // 여기 없으면 에이전트는 이 명령이 있는 줄 모른다.
      expect(
        ControlService.actions['relay'],
        containsAll(['status', 'start', 'stop']),
      );
    });

    test('상태 조회가 미러와 같은 모양이다', () async {
      // 화면에서 본 것과 CLI 로 읽은 것이 다르면 그 채널은 못 믿는다.
      final ctrl = host();
      ctrl.settings.setRelayBase('https://relay.ranode.net');

      final viaCommand = await ControlService(
        ctrl,
      ).run('relay', {'action': 'status'});
      final viaMirror =
          ControlSnapshot(ctrl).build()['relay'] as Map<String, dynamic>;
      expect(viaCommand.keys.toSet(), viaMirror.keys.toSet());
      expect(viaCommand['status'], viaMirror['status']);
      expect(viaCommand['base'], viaMirror['base']);
    });

    test('인자 없이 부르면 상태를 준다', () async {
      final r = await ControlService(host()).run('relay', const {});
      expect(r['status'], 'off');
    });

    test('주소 없이 켜려 하면 무엇을 해야 할지 알려준다', () async {
      // 조용히 아무 일도 안 일어나는 것이 제일 나쁘다 — 스크립트는 성공으로
      // 읽고, 사람은 왜 안 켜지는지 모른다.
      await expectLater(
        ControlService(host()).run('relay', {'action': 'start'}),
        throwsA(
          isA<ControlFailure>().having(
            (e) => e.toString(),
            'message',
            contains('주소'),
          ),
        ),
      );
    });

    test('모르는 액션은 사용법 오류다', () async {
      // 실행 실패(1)와 갈라야 스크립트가 재시도할지 말지 안다.
      await expectLater(
        ControlService(host()).run('relay', {'action': 'zzz'}),
        throwsA(isA<ControlUsageError>()),
      );
    });
  });
}

/// 방 정책(개수·수명)이 화면 밖에서도 보이는가.
///
/// "왜 새 방이 안 생기지" 는 화면 없이도 답할 수 있어야 한다 — 한계값이
/// 안 보이면 스크립트는 무한 재시도에 빠지고, 사람은 버그로 읽는다.
void _roomPolicy() {
  group('방 정책', () {
    HostController host({int maxRooms = 2}) {
      final ctrl = HostController();
      addTearDown(ctrl.dispose);
      ctrl.server = RoomServer(
        assets: const BundleAssetSource(),
        port: 0,
        maxRooms: maxRooms,
      );
      ctrl.room = ctrl.server!.createRoom(name: '금요 모임');
      return ctrl;
    }

    test('한계값이 미러에 실린다', () {
      final snap = ControlSnapshot(host()).build();
      final policy = snap['roomPolicy'] as Map<String, dynamic>;
      expect(policy['max'], 2);
      expect(policy['ttlHours'], 72, reason: '3일 = 72시간');
      expect(policy['full'], isFalse);
    });

    test('가득 차면 그렇게 보인다', () {
      final ctrl = host();
      ctrl.createRoom('두 번째');
      final policy =
          ControlSnapshot(ctrl).build()['roomPolicy'] as Map<String, dynamic>;
      expect(policy['full'], isTrue);
    });

    test('정원을 넘기면 이유가 남는다', () {
      // 조용히 null 만 돌려주면 화면은 "아무 일도 안 일어난" 것으로 보인다.
      final ctrl = host();
      ctrl.createRoom('두 번째');
      final third = ctrl.createRoom('세 번째');

      expect(third, isNull);
      expect(ctrl.createRoomError, isNotNull);
      expect(ctrl.createRoomError, contains('최대 2개'));
      expect(ctrl.roomsFull, isTrue);
    });

    test('성공하면 옛 오류가 남지 않는다', () {
      final ctrl = host(maxRooms: 3);
      ctrl.createRoom('두 번째');
      ctrl.createRoom('세 번째');
      expect(ctrl.createRoom('네 번째'), isNull);
      expect(ctrl.createRoomError, isNotNull);

      // 하나 지우고 다시 — 옛 오류가 그대로 남아 있으면 화면이 거짓말을 한다.
      ctrl.server!.removeRoom(ctrl.rooms.first.roomToken);
      expect(ctrl.createRoom('다시'), isNotNull);
      expect(ctrl.createRoomError, isNull);
    });
  });
}

/// 화면 없이 랑데부 주소를 정할 수 있는가.
///
/// `start`·`stop`·`status` 는 있었는데 `set` 이 없었다 — 그래서 CLI 만으로는
/// 이 기능을 **켤 수가 없었다.** GUI 와 CLI 가 대등해야 한다는 이 앱의 규약에
/// 난 구멍이었고, 실제로 그것 때문에 설정 파일을 직접 건드리려다 막혔다.
void _relaySet() {
  group('relay set', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    HostController host() {
      final ctrl = HostController();
      addTearDown(ctrl.dispose);
      ctrl.server = RoomServer(assets: const BundleAssetSource(), port: 0);
      ctrl.room = ctrl.server!.createRoom(name: '금요 모임');
      return ctrl;
    }

    test('주소를 정하면 설정에 남는다', () async {
      final ctrl = host();
      final r = await ControlService(
        ctrl,
      ).run('relay', {'action': 'set', 'url': 'https://relay.ranode.net'});
      expect(ctrl.settings.relayBase, 'https://relay.ranode.net');
      expect(r['configured'], isTrue);
      expect(r['base'], 'https://relay.ranode.net');
    });

    test('off 라고 적어야 해제된다', () async {
      final ctrl = host();
      ctrl.settings.setRelayBase('https://relay.ranode.net');
      final r = await ControlService(
        ctrl,
      ).run('relay', {'action': 'set', 'url': 'off'});
      expect(ctrl.settings.relayBase, isEmpty);
      expect(r['configured'], isFalse);
    });

    test('빈 값은 해제가 아니라 사용법 오류다', () async {
      // 빈 값을 해제로 읽으면 실수로 지나간다 — 방 비밀번호에서 이미 겪었다.
      final ctrl = host();
      ctrl.settings.setRelayBase('https://relay.ranode.net');
      await expectLater(
        ControlService(ctrl).run('relay', {'action': 'set', 'url': '  '}),
        throwsA(isA<ControlUsageError>()),
      );
      expect(
        ctrl.settings.relayBase,
        'https://relay.ranode.net',
        reason: '거절했으면 값도 그대로여야 한다',
      );
    });

    test('http/https 가 아니면 거절한다', () async {
      final ctrl = host();
      for (final bad in ['ftp://x.com', 'relay.ranode.net', 'https://']) {
        await expectLater(
          ControlService(ctrl).run('relay', {'action': 'set', 'url': bad}),
          throwsA(isA<ControlUsageError>()),
          reason: '"$bad" 를 받아들이면 켤 때야 실패한다',
        );
      }
      expect(ctrl.settings.relayBase, isEmpty);
    });

    test('http 는 받되 왜 아쉬운지 말한다', () async {
      // 사내망·시험용 주소가 있을 수 있어 막지는 않는다. 다만 참가자 화면이
      // secure context 가 아니면 브라우저가 일부 기능을 안 열어 준다.
      final ctrl = host();
      final r = await ControlService(
        ctrl,
      ).run('relay', {'action': 'set', 'url': 'http://192.168.0.9:8080'});
      expect(ctrl.settings.relayBase, 'http://192.168.0.9:8080');
      expect(r['warning'], contains('https'));
    });

    test('capabilities 에 set 이 있다', () {
      expect(ControlService.actions['relay'], contains('set'));
    });
  });
}
