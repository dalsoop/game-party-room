import 'package:party_room_server/party_room_server.dart';

import '../games/game_catalog.dart';
import '../host_controller.dart';

/// 화면 없이 "지금 무슨 상태인가" 를 답하는 한 덩어리.
///
/// 명령 실행과 갈라 둔 이유: 여기는 **읽기 전용** 이고, StateMirror 파일에
/// 그대로 실린다 — 에이전트가 스크린샷 없이 확인하는 채널이다. 쓰기 명령
/// 옆에 두면 스냅샷 필드 하나를 고치려다 `start`·`pin` 쪽을 건드릴 여지가
/// 생긴다. 응답 모양은 CLI `status --json` 계약이라 필드를 함부로 빼면 안 된다.
/// 랑데부 상태 한 덩어리.
///
/// 스냅샷(StateMirror)과 `relay` 명령이 **같은 모양**을 쓴다 — 화면에서 본
/// 것과 CLI 로 읽은 것이 다르면 그 채널은 못 믿는다.
Map<String, dynamic> relayStatusMap(HostController ctrl) {
  final r = ctrl.relay;
  return {
    'configured': ctrl.settings.relayBase.trim().isNotEmpty,
    'base': ctrl.settings.relayBase,
    'status': ctrl.relayStatus.name,
    'code': ctrl.relayCode,
    'url': ctrl.relayUrl,
    if (r?.deniedReason != null) 'deniedReason': r!.deniedReason,
    // 저쪽 릴레이가 무엇을 돌리는가. 참가자 화면이 릴레이 이미지에 구워져
    // 있어서, 앱만 고치고 이미지를 안 다시 구우면 **밖에서 온 사람만**
    // 옛 화면을 받는다. 그때 견줄 수 있는 값이다.
    if (r?.serverVersion != null) 'serverVersion': r!.serverVersion,
    if (r?.serverAssets != null) 'serverAssets': r!.serverAssets,
    // 지금 이 길로 들어와 있는 사람 수. 0 이면 켜져 있어도 아무도 안 쓰는 것이다 —
    // "켜짐" 만 보고 잘 돌고 있다고 판단하면 안 된다.
    'participants': [
      for (final room in ctrl.rooms)
        ...room.players.where((p) => p.link?.path == LinkPath.relay),
    ].length,
  };
}

class ControlSnapshot {
  ControlSnapshot(this.ctrl);

  final HostController ctrl;

  Map<String, dynamic> build() {
    final s = ctrl.room;
    final live = GameCatalog.liveOf(ctrl);
    return {
      'schemaVersion': 2,
      'at': DateTime.now().toIso8601String(),
      // **모든 방**을 싣는다.
      //
      // 방을 여럿으로 만들면서 여기가 한동안 선택된 방만 보고했다 —
      // 스크린샷 없이 앱을 보라고 만든 채널이 3분의 1만 보여주고 있었다.
      // 다른 방에서 판이 돌고 있어도 파일에는 안 나타났다.
      'rooms': [for (final r in ctrl.rooms) _roomSummary(r)],
      // 서버가 방을 몇 개까지·얼마나 오래 들고 있는가. 화면 없이 "왜 새 방이
      // 안 생기지" 를 답하려면 한계값이 보여야 한다.
      'roomPolicy': {
        'max': ctrl.server?.maxRooms,
        'full': ctrl.roomsFull,
        'ttlHours': ctrl.server?.roomTtl.inHours,
        'droppedOnLoad': ctrl.droppedOnLoad,
      },
      'selected': s?.roomToken,
      'room': {
        'open': s != null,
        'name': s?.name,
        'token': s?.roomToken,
        'hasPin': s?.hasPin ?? false,
        'port': ctrl.server?.port,
        'url': ctrl.url,
        'restored': ctrl.restored,
        'prunedOnLoad': ctrl.prunedOnLoad,
        if (ctrl.error != null) 'error': ctrl.error,
      },
      // 밖에서 들어오는 길. 꺼져 있어도 싣는다 — 없는 것과 꺼진 것을
      // 구분할 수 없으면 "왜 아무도 못 들어오지" 를 답할 수 없다.
      'relay': relayStatusMap(ctrl),
      'players': {
        'connected': ctrl.games.connectedCount,
        'total': s?.players.length ?? 0,
        'max': s?.limits.players,
        'list': s?.lobbySnapshot() ?? const [],
      },
      'game': live == null
          ? null
          : {
              'id': live.id,
              'title': live.title,
              'status': ctrl.games.gameStatus,
              if (ctrl.games.marble != null)
                'marble': {
                  'running': ctrl.games.marble!.running,
                  'finished': ctrl.games.marble!.finished,
                  'course': ctrl.games.marble!.courseId,
                  'remaining': ctrl.games.marble!.world?.remaining,
                },
              if (ctrl.games.ladder != null)
                'ladder': {
                  'revealed': ctrl.games.ladder!.revealed.length,
                  'total': ctrl.games.ladder!.roster.length,
                  'tracing': ctrl.games.ladderTracing,
                },
              if (ctrl.games.mafia != null) 'mafiaPhase': ctrl.games.mafiaPhase,
            },
      'sections': [
        for (final sec in s?.channels.sections ?? const <ChatSection>[])
          {...sec.toWire(), 'messages': sec.messages.length},
      ],
      'network': {
        'usingExternal': ctrl.usingExternal,
        'tunnelRunning': ctrl.tunnelRunning,
        'externalDead': ctrl.externalDead,
        'reapedOrphanTunnel': ctrl.reapedOrphanTunnel,
        'address': ctrl.address?.ip,
      },
      'mc': {
        'enabled': ctrl.settings.mcEnabled,
        'provider': ctrl.settings.mcProvider,
        'lastLine': ctrl.mcLine,
      },
      'sound': ctrl.settings.soundEnabled,
    };
  }

  /// 방 하나의 요약 — 목록에 실린다. 상세(칸·명단)는 그 방을 골라서 본다.
  Map<String, dynamic> _roomSummary(Room r) => {
    'token': r.roomToken,
    'name': r.name,
    'open': r.open,
    'hasPin': r.hasPin,
    'createdAt': r.createdAt.toIso8601String(),
    'connected': r.players.where((p) => p.connected).length,
    'total': r.players.length,
    'game': r.activeGame == null
        ? null
        : {
            'id': r.activeGame!.id,
            'name': r.activeGame!.name,
            'section': r.channels.liveGame?.id,
          },
    'sections': r.channels.sections.length,
    'messages': r.channels.sections.fold<int>(
      0,
      (n, sec) => n + sec.messages.length,
    ),
    'files': r.sharedFiles.length,
  };
}
