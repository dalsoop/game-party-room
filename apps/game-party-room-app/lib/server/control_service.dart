import 'package:party_room_server/party_room_server.dart';

import '../games/game_catalog.dart';
import '../host_controller.dart';
import 'control_contract.dart';
import 'control_game_commands.dart';
import 'control_host_commands.dart';
import 'control_snapshot.dart';

// 호출부는 예전처럼 이 파일만 import 하면 된다 — 오류 타입·StateMirror 는
// 관심사별로 갈랐을 뿐 표면은 같다.
export 'control_errors.dart';
export 'state_mirror.dart';

/// 앱 기능의 **단일 실행 경로**.
///
/// 이 저장소 계약(`docs/app-interop-contract.md`)의 핵심은 "GUI와 CLI가 같은
/// Core를 호출한다" 이다. 예전에는 판을 시작하거나 끝내는 길이 화면 버튼
/// 하나뿐이라, 에이전트·스크립트가 확인하려면 스크린샷을 찍고 좌표를 눌러야
/// 했다 — 그리고 이 앱의 호스트 화면은 그 방법으로 **한 번도 검증되지
/// 못했다**(창이 다른 Space에 있으면 캡처조차 안 된다).
///
/// 이제 화면과 CLI가 모두 여기를 지난다. 검증 규칙이 갈라지지 않고,
/// 자동화가 GUI를 흉내 낼 이유가 없어진다.
///
/// 구현은 관심사별로 위임한다 — 한 클래스에 방·판·자료·터널·스냅샷이
/// 600줄을 넘기면 "자물쇠를 풀던 실사고" 주석 옆에서 마피아 페이즈를
/// 고치게 된다. 여기는 **분배·계약 표·짧은 조회** 만 두고, 갈래는
/// [ControlGameCommands]·[ControlHostCommands]·[ControlSnapshot] 이 맡는다.
class ControlService {
  ControlService(this.ctrl)
    : _games = ControlGameCommands(ctrl),
      _host = ControlHostCommands(ctrl),
      _snap = ControlSnapshot(ctrl);

  final HostController ctrl;
  final ControlGameCommands _games;
  final ControlHostCommands _host;
  final ControlSnapshot _snap;

  /// 명령마다 받는 action 들 — **여기가 정본**이다.
  ///
  /// 표 본문은 [controlActions] 에 있다(헬퍼와 순환 import 를 피하려고).
  /// 밖에서는 여전히 이 필드를 읽는다 — 오류 문구와 `partyroom games` 계약.
  static const actions = controlActions;

  /// 잘못 부른 action 에 돌려줄 문구. 목록은 [actions] 표에서만 나온다.
  static ControlUsageError badAction(String command) =>
      controlBadAction(command);

  /// `room pin` 의 인자가 무슨 뜻인지. null 은 "해제".
  ///
  /// **빈 값은 해제가 아니다.** 값을 잘못 넘겨 아무것도 안 실렸을 때
  /// (예: `room pin --pin 4907` 처럼 위치 인자 대신 플래그로 부른 경우)
  /// 자물쇠를 걸려던 명령이 조용히 자물쇠를 **푼 뒤 성공을 보고**한다 —
  /// 호스트는 잠긴 줄 알고, 링크를 주운 사람은 그냥 들어온다. 실제로 그렇게
  /// 당했으므로, 해제는 `off` 라고 적어야만 된다.
  static String? readPinArg(String? raw) => readControlPinArg(raw);

  /// 명령 하나를 실행한다. 봉투(`{ok, result}`)는 부르는 쪽이 씌운다.
  ///
  /// 모르는 명령·잘못된 인자는 [ControlUsageError], 지금 할 수 없는 일은
  /// [ControlFailure] 로 구분해 던진다 — CLI 의 exit code 가 이 구분을 쓴다.
  Future<Map<String, dynamic>> run(
    String command, [
    Map<String, dynamic> args = const {},
  ]) async {
    switch (command) {
      case 'status':
        return snapshot();

      case 'games':
        return {
          'games': [
            for (final e in GameCatalog.all)
              {
                'id': e.id,
                'title': e.title,
                'minPlayers': e.meta.minPlayers,
                'maxPlayers': e.meta.maxPlayers,
                'ready': ctrl.games.connectedCount >= e.meta.minPlayers,
                'live': e.isLive(ctrl),
                // 판을 시작한 뒤 이 게임에 뭘 시킬 수 있는지. 이게 없으면
                // 밖에서는 틀리게 불러 봐야 알 수 있다.
                'actions': actions[e.id] ?? const <String>[],
              },
          ],
        };

      case 'players':
        return {
          'players': ctrl.room?.lobbySnapshot() ?? const [],
          'connected': ctrl.games.connectedCount,
        };

      case 'rooms':
        return {
          'rooms': [
            for (final r in ctrl.rooms)
              {
                'token': r.roomToken,
                'name': r.name,
                'open': r.open,
                'hasPin': r.hasPin,
                'connected': r.players.where((p) => p.connected).length,
                'total': r.players.length,
                'game': r.activeGame?.id,
                'selected': identical(r, ctrl.room),
              },
          ],
        };

      case 'sections':
        final ch = _room.channels;
        return {
          'sections': [
            for (final s in ch.sections)
              {
                ...s.toWire(),
                'messages': s.messages.length,
                'files': ctrl.room!.sharedFilesIn(s.id).length,
              },
          ],
          'active': ch.defaultId,
        };

      case 'chat':
        final text = (args['text'] as String? ?? '').trim();
        if (text.isEmpty) throw ControlUsageError('보낼 말이 없습니다');
        ctrl.sendChat(text, sectionId: args['section'] as String?);
        return {'sent': text};

      case 'start':
        return _games.start(args);

      case 'end':
        return _games.end();

      case 'kick':
        final tag = (args['tag'] as String? ?? '').toUpperCase();
        final p = ctrl.room?.players.where((p) => p.tag == tag).firstOrNull;
        if (p == null) throw ControlFailure('그런 참가자가 없습니다: $tag');
        ctrl.room!.kick(p.sessionToken);
        return {'kicked': tag, 'nickname': p.nickname};

      case 'marble':
        return _games.marble(args['action'] as String? ?? '');

      case 'ladder':
        return _games.ladder(args['action'] as String? ?? '');

      case 'mafia':
        return _games.mafia(args['action'] as String? ?? '');

      case 'liar':
        return _games.liar(args['action'] as String? ?? '');

      case 'restart':
        return _games.restart();

      case 'tunnel':
        return _host.tunnel(args['action'] as String? ?? '');
      case 'relay':
        // 인자 없이 부르면 상태를 준다 — 조회가 제일 흔한 쓰임이다.
        return _host.relay({'action': 'status', ...args});

      case 'room':
        return _host.room(args);

      case 'files':
        return _host.files(args);

      case 'mc':
        if (args['action'] != 'probe') {
          throw badAction('mc');
        }
        final r = await ctrl.probeMc();
        if (!r.ok) throw ControlFailure(r.error ?? '사회자를 부르지 못했습니다');
        return {'sample': r.sample};

      default:
        throw ControlUsageError('모르는 명령: $command');
    }
  }

  /// 지금 보고 있는 방. CLI 도 이 방에 대고 말한다 —
  /// 다른 방을 조종하려면 먼저 `room use <토큰>` 으로 옮긴다.
  Room get _room {
    final r = ctrl.room;
    if (r == null) throw ControlFailure('방이 아직 열리지 않았습니다');
    return r;
  }

  /// 화면 없이 "지금 무슨 상태인가" 를 답하는 한 덩어리.
  ///
  /// [StateMirror] 파일에 그대로 실린다 — 에이전트가 **스크린샷 없이** 확인하는
  /// 채널이 이것이다. 본문은 [ControlSnapshot] 에 있다.
  Map<String, dynamic> snapshot() => _snap.build();
}
