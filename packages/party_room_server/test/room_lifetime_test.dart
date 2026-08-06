import 'dart:convert';

import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';

import 'support/memory_assets.dart';

/// 방의 수명.
///
/// 예전에는 방이 하나뿐이었고 12시간이 지나면 통째로 버렸다 — "일회성
/// 파티방" 의 규칙이었다. 이름을 붙여 친구 그룹마다 쓰는 방에는 맞지 않는다:
/// 금요 모임방 링크는 다음 주에도 통해야 한다.
///
/// 그래서 방은 호스트가 지울 때까지 살고, "지난달 링크가 아직 통한다" 는
/// 책임은 타이머가 아니라 **호스트의 열림/닫힘 스위치**가 진다. 다만 명단은
/// 여전히 늙으므로 오래 안 보인 사람은 불러올 때 걷어낸다.
void main() {
  final assets = MemoryAssets();

  String snapshot({
    required Duration savedAgo,
    required List<Duration?> lastSeenAgo,
    String token = 'OLDRM1',
    String name = '금요 모임',
    bool open = true,
  }) {
    final now = DateTime.now();
    return jsonEncode({
      'schemaVersion': 2,
      'rooms': [
        {
          'savedAt': now.subtract(savedAgo).millisecondsSinceEpoch,
          'roomToken': token,
          'name': name,
          'open': open,
          'players': [
            for (var i = 0; i < lastSeenAgo.length; i++)
              {
                'sessionToken': 'SESSION$i',
                'tag': 'T$i',
                'nickname': '손님$i',
                'kicked': false,
                if (lastSeenAgo[i] != null)
                  'lastSeen': now
                      .subtract(lastSeenAgo[i]!)
                      .millisecondsSinceEpoch,
              },
          ],
          'game': null,
        },
      ],
    });
  }

  Future<(RoomServer, RestoreOutcome)> restore(String raw) async {
    final store = MemoryStateStore();
    await store.write(raw);
    final server = RoomServer(assets: assets);
    final outcome = await RoomPersistence(store, assets).restoreInto(server);
    return (server, outcome);
  }

  test('이름 붙인 방은 하루가 지나도 그대로 돌아온다', () async {
    final (server, outcome) = await restore(
      snapshot(savedAgo: const Duration(days: 30), lastSeenAgo: const [null]),
    );
    expect(outcome.rooms, 1);
    final room = server.rooms.single;
    expect(room.roomToken, 'OLDRM1', reason: '토큰이 바뀌면 나눠준 링크가 죽는다');
    expect(room.name, '금요 모임');
    expect(room.open, isTrue);
  });

  test('닫아 둔 방은 닫힌 채로 돌아온다', () async {
    final (server, _) = await restore(
      snapshot(
        savedAgo: const Duration(hours: 1),
        lastSeenAgo: const [],
        open: false,
      ),
    );
    expect(server.rooms.single.open, isFalse, reason: '닫힘이 곧 안전 스위치다');
  });

  test('오래 안 보인 사람만 걷어낸다', () async {
    final (server, outcome) = await restore(
      snapshot(
        savedAgo: const Duration(minutes: 10),
        lastSeenAgo: [
          null, // 저장 시점에 접속 중
          const Duration(minutes: 30), // 잠깐 끊긴 사람
          const Duration(hours: 18), // 지난 파티 손님
        ],
      ),
    );
    expect(outcome.prunedPlayers, 1);
    expect(server.rooms.single.players.map((p) => p.nickname), ['손님0', '손님1']);
  });

  test('아무도 안 남아도 방은 남는다', () async {
    // 예전에는 여기서 방을 통째로 버렸다 — 이름 붙인 방에는 그러면 안 된다.
    final (server, _) = await restore(
      snapshot(
        savedAgo: const Duration(minutes: 10),
        lastSeenAgo: [const Duration(hours: 18), const Duration(hours: 30)],
      ),
    );
    expect(server.rooms, hasLength(1));
    expect(server.rooms.single.players, isEmpty);
  });

  test('방 여러 개가 각자 돌아온다', () async {
    final store = MemoryStateStore();
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.write(
      jsonEncode({
        'schemaVersion': 2,
        'rooms': [
          for (final (t, n) in [('AAA111', '금요 모임'), ('BBB222', '회사 워크숍')])
            {
              'savedAt': now,
              'roomToken': t,
              'name': n,
              'open': true,
              'players': const [],
              'game': null,
            },
        ],
      }),
    );
    final server = RoomServer(assets: assets);
    await RoomPersistence(store, assets).restoreInto(server);
    expect(server.rooms.map((r) => r.name), ['금요 모임', '회사 워크숍']);
    expect(server.byToken('BBB222')!.name, '회사 워크숍');
    expect(server.byToken('없는토큰'), isNull);
  });

  test('방 하나뿐이던 옛 저장분도 잃지 않는다', () async {
    // v1 은 방을 최상위에 뒀다. 진행 중이던 판 하나 때문에 기록·자료까지
    // 버릴 이유는 없다 — 방 하나로 옮겨 담는다.
    final store = MemoryStateStore();
    await store.write(
      jsonEncode({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'roomToken': 'V1ROOM',
        'players': [
          {'sessionToken': 'S', 'tag': 'T1', 'nickname': '가', 'kicked': false},
        ],
        'game': null,
      }),
    );
    final server = RoomServer(assets: assets);
    final outcome = await RoomPersistence(store, assets).restoreInto(server);
    expect(outcome.rooms, 1);
    expect(server.rooms.single.roomToken, 'V1ROOM');
    expect(server.rooms.single.players.single.nickname, '가');
  });

  test('저장하고 불러오면 방들이 그대로다', () async {
    final store = MemoryStateStore();
    final a = RoomServer(assets: assets);
    a.createRoom(name: '금요 모임').hostChat('안녕');
    a.createRoom(name: '회사').open = false;
    final p = RoomPersistence(store, assets);
    await p.save(a);

    final b = RoomServer(assets: assets);
    await p.restoreInto(b);
    expect(b.rooms.map((r) => r.name), ['금요 모임', '회사']);
    expect(b.rooms.first.chatHistory.single['text'], '안녕');
    expect(b.rooms.last.open, isFalse);
  });

  test('닫힌 방은 입장을 거절한다', () {
    final room = Room()..open = false;
    expect(room.seat('가'), isNull);
  });

  group('토큰은 유일하다', () {
    // byToken 은 먼저 만난 방만 돌려준다. 같은 토큰이 둘이면 뒤엣것은
    // 목록에는 보이는데 QR 로도 링크로도 아무도 못 들어오는 유령이 된다.
    test('쓰고 있는 토큰으로는 방을 못 만든다', () {
      final server = RoomServer(assets: assets);
      server.createRoom(token: 'DUP001');
      expect(() => server.createRoom(token: 'DUP001'), throwsArgumentError);
      expect(server.rooms, hasLength(1));
    });

    test('겹친 저장분은 하나만 되살린다', () async {
      final store = MemoryStateStore();
      final now = DateTime.now().millisecondsSinceEpoch;
      await store.write(
        jsonEncode({
          'schemaVersion': 2,
          'rooms': [
            for (final n in ['금요 모임', '겹친 것'])
              {
                'savedAt': now,
                'roomToken': 'SAME01',
                'name': n,
                'open': true,
                'players': const [],
                'game': null,
              },
          ],
        }),
      );
      final server = RoomServer(assets: assets);
      final outcome = await RoomPersistence(store, assets).restoreInto(server);
      expect(server.rooms, hasLength(1));
      expect(server.rooms.single.name, '금요 모임', reason: '먼저 것이 살아야 한다');
      expect(outcome.rooms, 1, reason: '못 받은 방까지 세면 안내가 거짓말이 된다');
    });
  });

  _clearKeepsTheLink();
}

/// 방 비우기 — 지우기와 다르다.
void _clearKeepsTheLink() {
  group('방 비우기', () {
    test('토큰·이름은 살아 있고 안만 비워진다', () async {
      final room = Room(name: '금요 모임', roomToken: 'KEEP01');
      room.seat('민서');
      room.hostChat('안녕');
      room.startGame(MarbleGame());
      expect(room.channels.sections.length, 2);

      await room.clear();

      // 나눠준 QR·링크가 계속 통해야 한다 — 그래서 지우기와 다르다.
      expect(room.roomToken, 'KEEP01');
      expect(room.name, '금요 모임');
      expect(room.open, isTrue);
      // 안은 비었다.
      expect(room.players, isEmpty);
      expect(room.activeGame, isNull);
      expect(room.chatHistory, isEmpty);
      expect(room.sharedFiles, isEmpty);
      expect(room.channels.sections.map((s) => s.kind), [SectionKind.room]);
    });

    test('비운 뒤에도 새로 입장할 수 있다', () async {
      final room = Room(roomToken: 'KEEP02');
      room.seat('민서');
      await room.clear();
      final p = room.seat('태윤');
      expect(p, isNotNull);
      expect(room.players.single.nickname, '태윤');
    });
  });
}
