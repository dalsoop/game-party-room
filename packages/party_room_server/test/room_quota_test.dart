import 'dart:convert';

import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';

import 'support/memory_assets.dart';

/// 한 서버가 방을 몇 개까지, 얼마나 오래 들고 있는가.
///
/// 한동안 둘 다 무제한이었다. 개인 맥에서만 돌 때는 그래도 됐다 — 방을
/// 만드는 사람도 지우는 사람도 기계 주인 하나였으니까. **상시로 도는 공용
/// 서버**가 생기면서 전제가 달라졌다: 아무도 안 지우면 방은 영원히 남고,
/// 방 하나가 참가자 20명·자료 1GB 를 물 수 있다.
///
/// 수명 타이머를 뺐던 옛 이유("금요 모임방 링크는 다음 주에도 통해야 한다")는
/// 여전히 유효하다 — 그래서 이건 **서버마다 정하는 값**이지 방의 성질이 아니다.
void main() {
  final assets = MemoryAssets();

  RoomServer make({int maxRooms = 2, Duration? ttl}) => RoomServer(
    assets: assets,
    port: 0,
    maxRooms: maxRooms,
    roomTtl: ttl ?? const Duration(days: 3),
  );

  group('방 개수', () {
    test('기본은 두 개까지다', () {
      final s = make();
      s.createRoom(name: '1번');
      s.createRoom(name: '2번');
      expect(s.full, isTrue);
      expect(
        () => s.createRoom(name: '3번'),
        throwsA(isA<StateError>()),
        reason: '조용히 안 만들어지면 호스트는 왜 안 생기는지 모른다',
      );
      expect(s.rooms, hasLength(2));
    });

    test('가득 찼다는 것을 미리 알 수 있다', () {
      // 눌러 봐야 거절당하는 버튼을 화면에 남겨 두지 않으려면 필요하다.
      final s = make();
      expect(s.full, isFalse);
      s.createRoom();
      expect(s.full, isFalse);
      s.createRoom();
      expect(s.full, isTrue);
    });

    test('하나 지우면 다시 만들 수 있다', () async {
      final s = make();
      final first = s.createRoom(name: '1번');
      s.createRoom(name: '2번');
      await s.removeRoom(first.roomToken);
      expect(() => s.createRoom(name: '3번'), returnsNormally);
    });

    test('거절 메시지가 무엇을 해야 할지 말한다', () {
      final s = make();
      s.createRoom();
      s.createRoom();
      expect(
        () => s.createRoom(),
        throwsA(
          isA<StateError>().having((e) => e.message, '메시지', contains('지우세요')),
        ),
      );
    });

    test('서버마다 다르게 정할 수 있다', () {
      // 개인 기계에서 도는 앱과 공용 상시 서버는 정책이 다르다.
      final s = make(maxRooms: 5);
      for (var i = 0; i < 5; i++) {
        s.createRoom(name: '$i');
      }
      expect(s.rooms, hasLength(5));
      expect(() => s.createRoom(), throwsA(isA<StateError>()));
    });
  });

  group('방 수명', () {
    test('수명이 지난 방은 비질에 치워진다', () async {
      final s = make(ttl: const Duration(milliseconds: 40));
      s.createRoom(name: '곧 사라질 방');
      expect(s.rooms, hasLength(1));

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(s.sweepExpired(), 1);
      expect(s.rooms, isEmpty);
    });

    test('아직 살아 있는 방은 안 건드린다', () {
      final s = make();
      s.createRoom(name: '오늘 만든 방');
      expect(s.sweepExpired(), 0);
      expect(s.rooms, hasLength(1));
    });

    test('접속 중인 사람이 있어도 지운다', () async {
      // "최대 3일" 이 조건부면 유령 하나가 방을 영원히 붙잡는다.
      final s = make(ttl: const Duration(milliseconds: 40));
      final room = s.createRoom(name: '붙잡힌 방');
      room.seat('안 나가는 사람');

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(s.sweepExpired(), 1);
      expect(s.rooms, isEmpty);
    });

    test('만들기 전에 먼저 치운다', () async {
      // 자리가 나는데도 "가득 찼다" 고 하면 호스트는 무엇을 지워야 할지 모른다.
      final s = make(maxRooms: 1, ttl: const Duration(milliseconds: 40));
      s.createRoom(name: '늙을 방');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(() => s.createRoom(name: '새 방'), returnsNormally);
      expect(s.rooms.single.name, '새 방');
    });
  });

  group('저장분을 되살릴 때', () {
    String saved(
      List<({String token, String name, Duration ago})> rooms,
    ) => jsonEncode({
      'schemaVersion': 2,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'rooms': [
        for (final r in rooms)
          {
            'savedAt': DateTime.now().millisecondsSinceEpoch,
            'roomToken': r.token,
            'name': r.name,
            'open': true,
            // 수명은 **만든 시각**부터 잰다 — 마지막 활동이 아니라.
            // "최대 3일" 은 그래야 상한이 된다.
            'createdAt': DateTime.now().subtract(r.ago).millisecondsSinceEpoch,
            'players': <dynamic>[],
            'game': null,
          },
      ],
    });

    Future<RestoreOutcome> restore(RoomServer s, String json) async {
      final store = MemoryStateStore();
      await store.write(json);
      return RoomPersistence(store, assets).restoreInto(s);
    }

    test('수명이 지난 방은 안 되살린다', () async {
      final s = make();
      final out = await restore(
        s,
        saved([
          (token: 'OLD001', name: '지난주 방', ago: const Duration(days: 5)),
          (token: 'NEW001', name: '어제 방', ago: const Duration(days: 1)),
        ]),
      );
      expect(s.rooms.map((r) => r.roomToken), ['NEW001']);
      expect(out.rooms, 1);
      expect(out.droppedRooms, 1, reason: '조용히 빼면 호스트는 "내 방 어디 갔지" 를 답할 수 없다');
    });

    test('정원을 넘는 저장분은 앞에서부터만 받는다', () async {
      final s = make(maxRooms: 2);
      final out = await restore(
        s,
        saved([
          (token: 'AAA001', name: '1', ago: Duration.zero),
          (token: 'BBB001', name: '2', ago: Duration.zero),
          (token: 'CCC001', name: '3', ago: Duration.zero),
        ]),
      );
      expect(s.rooms, hasLength(2));
      expect(out.droppedRooms, 1);
    });
  });
}
