import 'dart:convert';

import 'asset_source.dart';
import 'game_registry.dart';
import 'room_limits.dart';
import 'room_server.dart';
import 'state_store.dart';

/// 복구 결과 — 몇 개를 되살렸고, 몇 명의 유령을 걷어냈는지.
/// [droppedRooms] 은 서버가 받아 주지 않은 방 수 — 수명이 지났거나 정원을
/// 넘었다는 뜻이다. 조용히 빼면 호스트는 "내 방 어디 갔지" 를 답할 수 없다.
typedef RestoreOutcome = ({int rooms, int prunedPlayers, int droppedRooms});

/// 방들의 저장·복구.
///
/// 예전에는 방이 하나뿐이었고 12시간이 지나면 통째로 버렸다. 그건 "일회성
/// 파티방" 의 규칙이었다 — 이름을 붙여 친구 그룹마다 쓰는 방에는 맞지 않는다.
/// 지난달 링크가 살아 있는 책임은 이제 타이머가 아니라 **호스트가 스위치로**
/// 진다([Room.open]).
///
/// 다만 명단은 여전히 늙는다. 반년 전에 한 번 들른 사람이 정원을 먹고 있을
/// 이유는 없으므로, 오래 안 보인 참가자는 불러올 때 걷어낸다(다시 QR 을
/// 찍으면 새 자리로 들어온다).
class RoomPersistence {
  RoomPersistence(this.store, this.assets);

  final StateStore store;

  /// 복원한 방에 다시 넣어줄 자산 소스(지금은 서버가 쓴다).
  final AssetSource assets;

  /// 이 기간 넘게 안 보인 참가자는 명단에서 뺀다.
  static const forgetPlayerAfter = Duration(hours: 12);

  Future<void> save(RoomServer server) => store.write(
    jsonEncode({
      'schemaVersion': 2,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'rooms': [for (final r in server.rooms) r.toJson()],
    }),
  );

  Future<void> clear() => store.clear();

  /// 저장된 방들을 [server] 에 되살린다.
  Future<RestoreOutcome> restoreInto(
    RoomServer server, {
    DateTime? now,
    RoomLimits limits = const RoomLimits(),
  }) async {
    final raw = await store.read();
    if (raw == null) return (rooms: 0, prunedPlayers: 0, droppedRooms: 0);
    final at = now ?? DateTime.now();

    final List<dynamic> list;
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(raw) as Map<String, dynamic>;
      // v1 은 방 하나를 최상위에 뒀다. 통째로 버리지 않고 방 하나로 옮긴다 —
      // 진행 중이던 판 하나 때문에 기록·자료까지 잃을 이유는 없다.
      list =
          (j['rooms'] as List<dynamic>?) ??
          (j.containsKey('roomToken') ? [j] : const []);
    } catch (_) {
      // 파일 자체가 JSON 이 아니면 살릴 것이 없다. 이때만 버린다 —
      // 복구 실패로 앱을 아예 못 여는 것보다 낫다.
      await store.clear();
      return (rooms: 0, prunedPlayers: 0, droppedRooms: 0);
    }

    // **방마다 따로 살린다.** 예전에는 하나가 깨지면 catch 가 저장소를 통째로
    // 지웠다 — 두 번째 방의 필드 하나가 이상하다고 멀쩡한 첫 방까지, 그것도
    // 영구히 날아갔다. 게다가 서버에는 이미 받은 방이 남아 "복구 0개" 라고
    // 보고하면서 실제로는 방이 있는 상태가 됐다. 깨진 것만 건너뛴다.
    var pruned = 0;
    var adopted = 0;
    var dropped = 0;
    for (final e in list) {
      Room? room;
      try {
        final rj = (e as Map).cast<String, dynamic>();
        final savedAt = (rj['savedAt'] as num?) ?? (j['savedAt'] as num?);
        final fresh = <dynamic>[];
        for (final pj in (rj['players'] as List<dynamic>? ?? const [])) {
          if (_stillHere(pj as Map<String, dynamic>, savedAt, at)) {
            fresh.add(pj);
          } else {
            pruned++;
          }
        }

        room = Room(
          name: rj['name'] as String? ?? '',
          limits: limits,
          roomToken: rj['roomToken'] as String,
          createdAt: rj['createdAt'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  (rj['createdAt'] as num).toInt(),
                ),
        )..open = rj['open'] as bool? ?? true;
        room.setPin(rj['pin'] as String?);

        room.restorePlayers(fresh);
        room.channels.restore(
          (rj['channels'] as Map?)?.cast<String, dynamic>(),
        );
        final game = rj['game'] as Map<String, dynamic>?;
        if (game != null) {
          final module = GameRegistry.create(game['id'] as String);
          if (module != null) {
            room.restoreGame(module, game['state'] as Map<String, dynamic>);
          }
        }
        room.restoreFiles(rj['files'] as List<dynamic>?);
      } catch (_) {
        // 이 방만 포기한다. 옆 방은 죄가 없다.
        if (room != null) await room.dispose();
        continue;
      }
      // 겹친 토큰은 서버가 물리친다 — 센 것은 실제로 들어간 방뿐이다.
      if (server.adoptRoom(room)) {
        adopted++;
      } else {
        // 겹친 토큰·수명 초과·정원 초과. 어느 쪽이든 이 방은 안 살아난다.
        dropped++;
        await room.dispose();
      }
    }
    return (rooms: adopted, prunedPlayers: pruned, droppedRooms: dropped);
  }

  static bool _stillHere(
    Map<String, dynamic> pj,
    num? savedAtMs,
    DateTime now,
  ) {
    // 저장 시점에 접속 중이던 사람은 lastSeen 이 없다 — 저장 시각으로 본다.
    final ms = (pj['lastSeen'] as num?) ?? savedAtMs;
    if (ms == null) return true;
    final seen = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
    return now.difference(seen) <= forgetPlayerAfter;
  }
}
