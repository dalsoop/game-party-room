import 'package:party_room_server/party_room_server.dart';

import '../games/game_catalog.dart';
import '../host_controller.dart';
import 'control_contract.dart';
import 'control_snapshot.dart';

/// 방·자료·터널 명령 — 판 진행이 아니라 호스트 인프라.
///
/// 게임 명령과 갈라 둔 이유: `room pin` 은 빈 값을 해제로 읽으면 자물쇠가
/// 풀리던 **실사고** 가 있었고, 자료 공유·터널 수명은 판 페이즈와 다른
/// 실패 모드를 가진다. 한 파일에 두면 마피아 `night` 옆에서 pin 계약을
/// 고치게 되어 다시 실수하기 쉽다. 해제는 반드시 `off` 라고 적어야 한다
/// ([readControlPinArg] — 밖에서는 `ControlService.readPinArg`).
class ControlHostCommands {
  ControlHostCommands(this.ctrl);

  final HostController ctrl;

  /// 지금 보고 있는 방. CLI 도 이 방에 대고 말한다 —
  /// 다른 방을 조종하려면 먼저 `room use <토큰>` 으로 옮긴다.
  Room get _room {
    final r = ctrl.room;
    if (r == null) throw ControlFailure('방이 아직 열리지 않았습니다');
    return r;
  }

  Future<Map<String, dynamic>> tunnel(String action) async {
    switch (action) {
      case 'start':
        final err = await ctrl.startTunnel();
        if (err != null) throw ControlFailure(err);
        return {'url': ctrl.externalBase, 'running': ctrl.tunnelRunning};
      case 'stop':
        await ctrl.stopTunnel();
        return {'running': false};
      case 'recheck':
        await ctrl.recheckExternal();
        return {'dead': ctrl.externalDead, 'url': ctrl.externalBase};
      default:
        throw controlBadAction('tunnel');
    }
  }

  /// 밖에 있는 사람을 들이는 길(랑데부).
  ///
  /// 터널과 나란히 둔다 — 둘 다 "이 방에 바깥에서 닿게 하는 방법" 이고,
  /// 판 진행과는 다른 실패 모드를 가진다.
  Future<Map<String, dynamic>> relay(Map<String, dynamic> args) async {
    switch (args['action']) {
      case 'status':
        return relayStatusMap(ctrl);
      case 'set':
        // 화면 없이는 랑데부 주소를 정할 방법이 없었다 — start/stop/status 만
        // 있고 set 이 없어서, 이 앱 규약(GUI 와 CLI 가 대등)에 구멍이었다.
        final raw = (args['url'] as String? ?? '').trim();
        if (raw.isEmpty) {
          throw ControlUsageError('주소를 적으세요 (해제는 off)');
        }
        // 해제는 **off 라고 적어야** 한다. 빈 값을 해제로 읽으면 실수로
        // 지나갈 수 있다 — 방 비밀번호에서 이미 겪은 실사고와 같은 자리다.
        if (raw == 'off') {
          await ctrl.stopRelay();
          ctrl.settings.setRelayBase('');
          return relayStatusMap(ctrl);
        }
        final uri = Uri.tryParse(raw);
        if (uri == null || !uri.isScheme('https') && !uri.isScheme('http')) {
          throw ControlUsageError('http/https 주소여야 합니다: $raw');
        }
        if (uri.host.isEmpty) {
          throw ControlUsageError('호스트가 없습니다: $raw');
        }
        if (uri.isScheme('http')) {
          // 참가자 화면이 secure context 여야 브라우저가 제 기능을 다 연다.
          // 막지는 않는다 — 사내망이나 시험용 주소가 있을 수 있다.
          ctrl.settings.setRelayBase(raw);
          return {
            ...relayStatusMap(ctrl),
            'warning': 'https 가 아닙니다 — 참가자 화면에서 못 쓰는 기능이 생깁니다',
          };
        }
        ctrl.settings.setRelayBase(raw);
        return relayStatusMap(ctrl);
      case 'start':
        if (ctrl.settings.relayBase.trim().isEmpty) {
          throw ControlFailure(
            '랑데부 서버 주소가 없습니다 — 화면의 [밖에 있는 사람 들이기] 에서 먼저 정하세요',
          );
        }
        await ctrl.startRelay();
        return relayStatusMap(ctrl);
      case 'stop':
        await ctrl.stopRelay();
        return relayStatusMap(ctrl);
      default:
        throw controlBadAction('relay');
    }
  }

  Future<Map<String, dynamic>> room(Map<String, dynamic> args) async {
    switch (args['action']) {
      case 'clear':
        // 참가자·대화·자료가 사라진다 — 실수로 지나가면 안 된다.
        // (방 자체를 없애는 것은 delete. 이건 토큰·이름을 남긴다.)
        if (args['confirm'] != true) {
          throw ControlUsageError('방 비우기는 confirm 이 필요합니다 (--yes)');
        }
        final clearing = (args['token'] as String?) ?? _room.roomToken;
        await ctrl.clearRoom(clearing);
        return {'cleared': clearing};
      case 'prune':
        if (GameCatalog.liveOf(ctrl) != null) {
          // 명단은 시작 시점에 고정돼 있어, 판 중에 지우면 게임이 없는
          // 자리를 참조한다.
          throw ControlFailure('판이 도는 동안에는 정리할 수 없습니다');
        }
        return {'pruned': _room.pruneDisconnected()};
      case 'new':
        final r = ctrl.createRoom(args['name'] as String? ?? '');
        if (r == null) throw ControlFailure('방을 열지 못했습니다');
        return {'token': r.roomToken, 'name': r.name};
      case 'use':
        final t = args['token'] as String?;
        if (ctrl.server?.byToken(t) == null) {
          throw ControlUsageError('그런 방이 없습니다: $t');
        }
        ctrl.selectRoom(t!);
        return {'token': t, 'name': ctrl.room?.name};
      case 'open':
      case 'close':
        final t = (args['token'] as String?) ?? _room.roomToken;
        if (ctrl.server?.byToken(t) == null) {
          throw ControlUsageError('그런 방이 없습니다: $t');
        }
        ctrl.setRoomOpen(t, args['action'] == 'open');
        return {'token': t, 'open': args['action'] == 'open'};
      case 'rename':
        final t = (args['token'] as String?) ?? _room.roomToken;
        ctrl.renameRoom(t, args['name'] as String? ?? '');
        return {'token': t, 'name': ctrl.server?.byToken(t)?.name};
      case 'pin':
        // 인자 판정이 먼저다 — 방을 못 찾았다는 이유로 잘못된 인자가
        // 묻히면 안 된다.
        final wanted = readControlPinArg(args['pin'] as String?);
        final pt = (args['token'] as String?) ?? _room.roomToken;
        final off = wanted == null;
        if (!ctrl.setRoomPin(pt, wanted)) {
          throw ControlUsageError('비밀번호는 숫자 4자리입니다 (해제는 off)');
        }
        // 원문은 돌려주지 않는다 — 걸렸는지만 알린다.
        return {'token': pt, 'hasPin': !off};
      case 'delete':
        if (args['confirm'] != true) {
          throw ControlUsageError('방 삭제는 confirm 이 필요합니다 (--yes)');
        }
        final t = (args['token'] as String?) ?? _room.roomToken;
        if (!await ctrl.deleteRoom(t)) {
          throw ControlFailure('그런 방이 없습니다: $t');
        }
        return {'deleted': t};
      case 'addresses':
        return {
          'addresses': [
            for (var i = 0; i < ctrl.addresses.length; i++)
              {
                'index': i,
                'ip': ctrl.addresses[i].ip,
                'label': ctrl.addresses[i].label,
                'interface': ctrl.addresses[i].interfaceName,
                'selected': i == ctrl.addressIndex,
              },
          ],
        };
      case 'address':
        final i = (args['index'] as num?)?.toInt();
        if (i == null || i < 0 || i >= ctrl.addresses.length) {
          throw ControlUsageError('index 가 주소 범위를 벗어났습니다');
        }
        ctrl.selectAddress(i);
        return {'url': ctrl.url};
      case 'refresh':
        await ctrl.refreshAddresses();
        return {'url': ctrl.url, 'count': ctrl.addresses.length};
      default:
        throw controlBadAction('room');
    }
  }

  Future<Map<String, dynamic>> files(Map<String, dynamic> args) async {
    switch (args['action']) {
      case 'list':
        return {
          'files': [
            for (final f in _room.sharedFiles)
              {
                'id': f.id,
                'name': f.name,
                'size': f.size,
                'section': f.sectionId,
                'owner': f.ownerName.isEmpty ? '호스트' : f.ownerName,
              },
          ],
        };
      case 'share':
        final paths = [
          for (final p in (args['paths'] as List<dynamic>? ?? const [])) '$p',
        ];
        if (paths.isEmpty) throw ControlUsageError('share 는 paths 가 필요합니다');
        final n = await ctrl.shareFiles(
          paths,
          sectionId: args['section'] as String?,
        );
        if (n == 0) throw ControlFailure('공유하지 못했습니다 (칸이 찼거나 파일이 없습니다)');
        return {'shared': n};
      case 'clear':
        final sec = args['section'] as String? ?? _room.channels.defaultId;
        return {'removed': await ctrl.clearSectionFiles(sec), 'section': sec};
      case 'remove':
        final id = args['id'] as String?;
        if (id == null) throw ControlUsageError('remove 는 id 가 필요합니다');
        await ctrl.removeSharedFile(id);
        return {'removed': id};
      default:
        throw controlBadAction('files');
    }
  }
}
