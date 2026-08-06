// 제어 표면의 오류 종류.
//
// **정의는 패키지에 있다** — `party_room_server` 의 `src/control/control_errors.dart`.
// 헤드리스 서버도 같은 제어 계약을 말하게 되면서, 여기 따로 두면 두 벌이 된다.
// 실제로 한 번 두 벌이 됐고 `ambiguous_import` 로 드러났다 — 그게 아니었으면
// 앱의 오류와 헤드리스의 오류가 **다른 타입**인 채로 지나갔을 것이고,
// CLI 의 exit code 가 서버마다 달라졌을 것이다
// (ControlUsageError → 64, ControlFailure → 1).
//
// 이 파일은 앱 코드가 여태 쓰던 import 경로를 유지하기 위한 재수출이다.
export 'package:party_room_server/party_room_server.dart'
    show ControlFailure, ControlUsageError;
