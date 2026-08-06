import 'dart:async';
import 'dart:convert';

import 'package:party_room_server/party_room_server.dart';
import 'package:party_room_server/testing.dart';
import 'package:test/test.dart';

/// 참가자가 방에 들어오는 **문** 하나.
///
/// 이 절차는 길마다 따로 있으면 안 된다 — 같은 망에서 곧장 오든 랑데부가
/// 물어다 주든 [serveParticipant] 를 지나야, 보안 수정이 한쪽에만 반영되는
/// 일이 없다. 여기 있는 것들은 그 문이 지켜야 할 약속이다.
///
/// 이 파일이 생긴 계기: 전송 계층을 [ParticipantLink] 뒤로 옮긴 뒤 돌연변이를
/// 걸어 봤더니 **215개 테스트가 있는데 `broadcast` 를 첫 사람에게만 보내도
/// 전부 통과했다.** 방에서 제일 많이 쓰는 길에 아무도 안 서 있었다.
void main() {
  /// 통로를 손으로 물려 준다 — 실제 소켓 없이 방과 문만 시험한다.
  ({RecordingLink link, StreamController<dynamic> inbound}) connect(Room room) {
    final inbound = StreamController<dynamic>();
    final link = RecordingLink();
    serveParticipant(room: room, link: link, inbound: inbound.stream);
    addTearDown(inbound.close);
    return (link: link, inbound: inbound);
  }

  void frame(StreamController<dynamic> c, Map<String, dynamic> m) =>
      c.add(jsonEncode(m));

  group('브로드캐스트', () {
    test('방에 있는 모두에게 간다', () async {
      // 돌연변이(`players.take(1)`)가 살아남았던 자리. 채팅·로비·장면 전환이
      // 전부 이 길로 나가므로, 여기가 새면 폰 몇 대가 엉뚱한 화면에 멈춘다.
      final room = Room();
      final links = [
        for (final n in ['민서', '태윤', '지우'])
          (room.seat(n)!..link = RecordingLink()).link! as RecordingLink,
      ];

      room.broadcast({'type': 'scene', 'scene': 'night'});

      for (final (i, l) in links.indexed) {
        expect(l.sentType('scene'), isTrue, reason: '${i + 1}번째 사람이 못 받았다');
      }
    });

    test('한 명의 통로가 터져도 나머지는 받는다', () {
      // 탭을 닫으면 sink 가 먼저 닫히고 onDone 은 조금 뒤에 온다. 그 틈의
      // 브로드캐스트가 예외로 끊기면 **뒷사람들이 통째로 놓친다**.
      final room = Room();
      room.seat('먼저나간사람')!.link = DeadLink();
      final live =
          (room.seat('남은사람')!..link = RecordingLink()).link! as RecordingLink;

      expect(() => room.broadcast({'type': 'scene'}), returnsNormally);
      expect(live.sentType('scene'), isTrue, reason: '앞사람이 터져서 뒷사람이 굶었다');
    });

    test('끊긴 사람은 건너뛴다', () {
      final room = Room();
      room.seat('접속중')!.link = RecordingLink();
      room.seat('끊김'); // 통로 없음
      expect(() => room.broadcast({'type': 'lobby'}), returnsNormally);
    });
  });

  group('지운 방', () {
    test('늦게 도착한 인증 프레임을 거절한다', () async {
      // 참가자 맵은 `dispose()` 뒤에도 메모리에 남는다. 그래서 방이 지워진
      // 뒤에 도착한 인증 프레임이 자리를 찾는 데 **성공할 수 있었다** —
      // 지운 방에 계속 채팅과 게임 메시지를 보낼 수 있었다는 뜻이다.
      // 방어가 두 겹(문과 `Room.attach`)이라 한 겹만 떼면 안 드러났고,
      // 두 겹을 다 떼도 215개 테스트가 전부 통과했다.
      final room = Room();
      final p = room.seat('민서')!;
      await room.dispose();

      final c = connect(room);
      frame(c.inbound, {'type': 'auth', 'session': p.sessionToken});
      await pumpEventQueue();

      expect(p.link, isNull, reason: '지운 방에 자리가 이어졌다');
      expect(p.connected, isFalse);
    });
  });

  group('인증', () {
    test('붙자마자 누구인지 밝히라고 한다', () async {
      final room = Room();
      final c = connect(room);
      await pumpEventQueue();
      expect(c.link.sentType('auth_required'), isTrue);
    });

    test('모르는 세션은 거절하고 통로를 닫는다', () async {
      final room = Room();
      final c = connect(room);
      frame(c.inbound, {'type': 'auth', 'session': '없는세션'});
      await pumpEventQueue();

      expect(c.link.sentType('auth_failed'), isTrue);
      expect(c.link.closed, isTrue, reason: '거절하고도 통로를 열어 두면 자리를 문다');
    });

    test('밝히기 전에는 아무 말도 못 한다', () async {
      final room = Room();
      room.seat('민서');
      final c = connect(room);

      // 인증 없이 곧장 채팅을 시도한다.
      frame(c.inbound, {'type': 'chat', 'text': '끼어들기'});
      await pumpEventQueue();

      expect(
        room.chatHistoryOf(room.channels.defaultId),
        isEmpty,
        reason: '누구인지 모르는 소켓의 말이 방에 남았다',
      );
    });

    test('안 밝히면 시간이 지나 닫힌다', () async {
      // 붙기만 하고 조용한 소켓이 자리를 물고 있으면, 방이 찼다는 이유로
      // 진짜 참가자가 못 들어온다.
      final room = Room();
      final inbound = StreamController<dynamic>();
      addTearDown(inbound.close);
      final link = RecordingLink();
      serveParticipant(
        room: room,
        link: link,
        inbound: inbound.stream,
        authTimeout: const Duration(milliseconds: 20),
      );

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(link.closed, isTrue);
    });

    test('밝히고 나면 밀린 것을 받는다', () async {
      final room = Room();
      final p = room.seat('민서')!;
      final c = connect(room);
      frame(c.inbound, {'type': 'auth', 'session': p.sessionToken});
      await pumpEventQueue();

      expect(p.connected, isTrue);
      for (final t in ['limits', 'sections', 'files', 'room_status']) {
        expect(c.link.sentType(t), isTrue, reason: '$t 를 안 내려 줬다');
      }
    });
  });

  group('통로가 겹칠 때', () {
    test('새로 붙으면 이전 통로는 닫힌다', () async {
      // 참가자 SPA 는 끊기면 자동 재연결하고 세션은 localStorage 에 남는다.
      // 탭 두 개나 네트워크 전환이면 한 세션에 통로가 겹친다.
      final room = Room();
      final p = room.seat('민서')!;

      final first = connect(room);
      frame(first.inbound, {'type': 'auth', 'session': p.sessionToken});
      await pumpEventQueue();

      final second = connect(room);
      frame(second.inbound, {'type': 'auth', 'session': p.sessionToken});
      await pumpEventQueue();
      await pumpEventQueue();

      expect(first.link.closed, isTrue, reason: '겹친 옛 통로가 안 닫혔다');
      expect(identical(p.link, second.link), isTrue);
      expect(p.connected, isTrue);
    });

    test('옛 통로가 늦게 끊겨도 새 통로를 죽이지 않는다', () async {
      // 겹친 이전 소켓의 onDone 이 뒤늦게 오는 경우. 그때 방금 붙은 통로를
      // null 로 만들면 참가자는 화면상 멀쩡한데 서버는 "끊김" 으로 보고,
      // 마피아 역할 같은 비밀 전송이 조용히 사라진다.
      final room = Room();
      final p = room.seat('민서')!;

      final first = connect(room);
      frame(first.inbound, {'type': 'auth', 'session': p.sessionToken});
      await pumpEventQueue();

      final second = connect(room);
      frame(second.inbound, {'type': 'auth', 'session': p.sessionToken});
      await pumpEventQueue();

      // 이제서야 옛 통로의 끊김이 도착한다.
      await first.inbound.close();
      await pumpEventQueue();

      expect(p.connected, isTrue, reason: '옛 소켓의 뒤늦은 onDone 이 산 사람을 끊었다');
      expect(identical(p.link, second.link), isTrue);
    });
  });

  group('길은 방에게 투명하다', () {
    test('중계로 온 참가자도 똑같이 방에 들어온다', () async {
      // 닌텐도 Pia 가 로컬 통신과 인터넷 통신에 공통 API 를 씌운 이유.
      // 방과 게임은 어느 길로 왔는지 몰라야 한다.
      final room = Room();
      final p = room.seat('민서')!;
      final inbound = StreamController<dynamic>();
      addTearDown(inbound.close);
      final link = RecordingLink(path: LinkPath.relay);
      serveParticipant(room: room, link: link, inbound: inbound.stream);

      frame(inbound, {'type': 'auth', 'session': p.sessionToken});
      await pumpEventQueue();

      expect(p.connected, isTrue);
      expect(link.sentType('limits'), isTrue);
      expect(p.link!.path, LinkPath.relay, reason: '길은 통로가 알고 있어야 한다');
    });

    test('중계로 온 사람에게는 자료 기능을 안 연다', () async {
      // 한 사람 30MB 를 남의 서버로 나르지 않는다. 화면이 이 값을 보고
      // 그 자리를 아예 감춘다 — 눌러 봐야 413 이 오는 버튼이 제일 나쁘다.
      final room = Room();
      final p = room.seat('민서')!;
      final inbound = StreamController<dynamic>();
      addTearDown(inbound.close);
      final link = RecordingLink(path: LinkPath.relay);
      serveParticipant(room: room, link: link, inbound: inbound.stream);
      frame(inbound, {'type': 'auth', 'session': p.sessionToken});
      await pumpEventQueue();

      expect(link.last('limits')!['canFiles'], isFalse);
    });

    test('같은 망에서 온 사람에게는 연다', () async {
      final room = Room();
      final p = room.seat('민서')!;
      final c = connect(room);
      frame(c.inbound, {'type': 'auth', 'session': p.sessionToken});
      await pumpEventQueue();

      expect(c.link.last('limits')!['canFiles'], isTrue);
    });
  });
}
