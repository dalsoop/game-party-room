import 'dart:convert';

import 'package:party_room_server/party_room_server.dart';
import 'package:party_room_server/testing.dart';
import 'package:test/test.dart';

/// 참가자가 자기 이름을 바꾼다.
///
/// 한동안 **길이 아예 없었다.** 서버가 받는 참가자 메시지는 `ping`·`chat`
/// 뿐이었고, 세션으로 재입장해도 옛 이름을 그대로 돌려줬다. 오타 하나면
/// 파티 내내 그 이름을 달고 다녀야 했다.
///
/// `Player.nickname` 주석에는 진작 "닉네임은 겹치고 바뀌기도 한다" 고 적혀
/// 있었다 — 바뀔 것을 전제한 설계인데 그 길만 없었다.
///
/// 태그(4자)는 바뀌지 않는다. 사람을 특정하는 기준은 그쪽이라, 이름이
/// 바뀌어도 기록·지목이 흐트러지지 않는다.
void main() {
  ({Room room, Player p, RecordingLink link}) seated([String name = '민서']) {
    final room = Room();
    final p = room.seat(name)!;
    final link = RecordingLink();
    p.link = link;
    return (room: room, p: p, link: link);
  }

  void send(Room room, Player p, Map<String, dynamic> msg) =>
      room.handleMessage(p, jsonEncode(msg));

  test('이름을 바꾼다', () {
    final r = seated();
    send(r.room, r.p, {'type': 'rename', 'nickname': '민서2'});
    expect(r.p.nickname, '민서2');
  });

  test('태그는 그대로다', () {
    // 이름이 바뀌어도 사람을 특정하는 기준은 흔들리면 안 된다.
    final r = seated();
    final tag = r.p.tag;
    send(r.room, r.p, {'type': 'rename', 'nickname': '다른이름'});
    expect(r.p.tag, tag);
  });

  test('본인에게 확인을 돌려준다', () {
    // 화면이 낙관적으로 바꿔 놓고 서버가 거절하면 둘이 어긋난 채 남는다.
    final r = seated();
    send(r.room, r.p, {'type': 'rename', 'nickname': '민서2'});
    expect(r.link.last('renamed')?['nickname'], '민서2');
  });

  test('남들 화면에도 반영된다', () {
    final room = Room();
    final me = room.seat('민서')!..link = RecordingLink();
    final other = room.seat('태윤')!;
    final otherLink = RecordingLink();
    other.link = otherLink;

    send(room, me, {'type': 'rename', 'nickname': '민서2'});

    final lobby = otherLink.last('lobby');
    expect(lobby, isNotNull, reason: '옆 사람 화면이 옛 이름에 머문다');
    final names = [
      for (final p in (lobby!['players'] as List)) (p as Map)['nickname'],
    ];
    expect(names, containsAll(['민서2', '태윤']));
  });

  group('거절하는 것', () {
    test('빈 이름', () {
      final r = seated();
      for (final bad in ['', '   ', '\t']) {
        send(r.room, r.p, {'type': 'rename', 'nickname': bad});
        expect(r.p.nickname, '민서', reason: '"$bad" 가 통과했다');
      }
    });

    test('12자를 넘는 이름', () {
      final r = seated();
      send(r.room, r.p, {'type': 'rename', 'nickname': '가' * 13});
      expect(r.p.nickname, '민서');
    });

    test('12자는 받는다', () {
      final r = seated();
      send(r.room, r.p, {'type': 'rename', 'nickname': '가' * 12});
      expect(r.p.nickname, '가' * 12);
    });

    test('이름이 아닌 값', () {
      final r = seated();
      send(r.room, r.p, {'type': 'rename'});
      expect(r.p.nickname, '민서');
    });
  });

  test('연타는 억제한다', () async {
    // 이름 바꾸기마다 로비 브로드캐스트가 따라온다 — 연타를 놔두면 방 전체가
    // 그 사람 때문에 시끄러워진다. 채팅과 같은 간격을 쓴다.
    final r = seated();
    send(r.room, r.p, {'type': 'rename', 'nickname': '첫번째'});
    send(r.room, r.p, {'type': 'rename', 'nickname': '두번째'});
    expect(r.p.nickname, '첫번째', reason: '연타가 그대로 통과했다');

    await Future<void>.delayed(
      Duration(milliseconds: const RoomLimits().chatIntervalMs + 40),
    );
    send(r.room, r.p, {'type': 'rename', 'nickname': '두번째'});
    expect(r.p.nickname, '두번째', reason: '간격이 지났는데도 안 바뀐다');
  });

  test('입장과 같은 자를 쓴다', () {
    // 규칙이 두 곳에 있으면 한쪽만 고쳐져서, 입장 때는 막히는 이름이
    // 바꾸기로는 통과한다.
    for (final raw in ['', '  ', '가' * 13]) {
      expect(Room.cleanNickname(raw), isNull, reason: '"$raw"');
    }
    expect(Room.cleanNickname('  민서  '), '민서', reason: '앞뒤 공백은 다듬는다');
    expect(Room.cleanNickname('가' * 12), '가' * 12);
  });
}
