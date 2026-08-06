import 'package:party_room_server/party_room_server.dart';

/// 제어 표면의 **계약 표** — 명령 구현과 분배 파사드가 같이 본다.
///
/// `actions`·`readPinArg`·`badAction` 을 `ControlService` 에만 두면 헬퍼
/// 클래스(게임·방)가 그 파일을 import 해야 하고, 파사드가 다시 헬퍼를
/// import 해 **순환**이 생긴다. 표는 구현을 몰라야 하므로 여기만 둔다.
/// 밖에서는 여전히 `ControlService.actions` / `readPinArg` 로 읽는다
/// (파사드가 그대로 드러낸다) — CLI 오류 문구와 `partyroom games` 계약이다.

/// 명령마다 받는 action 들 — **여기가 정본**이다.
///
/// 예전에는 이 목록이 각 `throw` 문 안의 문자열로만 있었다. 그래서 밖에서는
/// 틀리게 불러 봐야 알 수 있었고(실제로 `marble run`·`ladder reveal` 로 두 번
/// 헛짚었다), 액션을 추가해도 안내 문구는 옛것으로 남았다. 이제 오류 문구와
/// `games` 응답이 모두 이 표를 읽는다 — CLI 는 별 패키지라 이 표를 직접
/// 못 보고, `capabilities` 가 `partyroom games --json` 을 가리킨다.
const controlActions = <String, List<String>>{
  ...GameControlCommands.actions,
  'mc': ['probe'],
  'tunnel': ['start', 'stop', 'recheck'],
  'relay': ['status', 'set', 'start', 'stop'],
  'files': ['list', 'share', 'clear', 'remove'],
  'room': [
    'new',
    'use',
    'open',
    'close',
    'rename',
    'pin',
    'clear',
    'delete',
    'prune',
    'addresses',
    'address',
    'refresh',
  ],
};

/// 잘못 부른 action 에 돌려줄 문구. 목록은 [controlActions] 표에서만 나온다.
ControlUsageError controlBadAction(String command) => ControlUsageError(
  '$command 의 action 은 ${controlActions[command]!.join('|')}',
);

/// `room pin` 의 인자가 무슨 뜻인지. null 은 "해제".
///
/// **빈 값은 해제가 아니다.** 값을 잘못 넘겨 아무것도 안 실렸을 때
/// (예: `room pin --pin 4907` 처럼 위치 인자 대신 플래그로 부른 경우)
/// 자물쇠를 걸려던 명령이 조용히 자물쇠를 **푼 뒤 성공을 보고**한다 —
/// 호스트는 잠긴 줄 알고, 링크를 주운 사람은 그냥 들어온다. 실제로 그렇게
/// 당했으므로, 해제는 `off` 라고 적어야만 된다.
String? readControlPinArg(String? raw) {
  final v = raw?.trim() ?? '';
  if (v.isEmpty) {
    throw ControlUsageError('비밀번호를 적어 주세요: room pin <4자리> (해제는 room pin off)');
  }
  return v == 'off' ? null : v;
}
