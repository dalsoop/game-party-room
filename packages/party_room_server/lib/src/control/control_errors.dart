// 제어 표면의 오류 종류.
//
// **패키지에 둔다.** 예전에는 앱에만 있었는데, 헤드리스 서버도 같은 제어
// 계약을 말하게 되면서 두 벌이 될 위기였다 — 오류 종류가 갈리면 CLI 의
// exit code 가 서버마다 달라진다. 앱은 이것을 그대로 다시 내보낸다.
//
// CLI 의 exit code 가 이 구분을 그대로 쓴다 — ControlUsageError → 64,
// ControlFailure → 1. 같은 타입으로 뭉뚱그리면 스크립트가 "내가 틀렸나
// 상황이 안 됐나" 를 구분하지 못해 무한 재시도에 빠진다.

/// 사용법이 틀렸다 — CLI 는 exit 64.
class ControlUsageError implements Exception {
  ControlUsageError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 지금은 할 수 없다 — CLI 는 exit 1.
class ControlFailure implements Exception {
  ControlFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 모르는 action 을 받았을 때의 한 줄. 가능한 것을 함께 알려준다 —
/// "모르는 action" 만 던지면 부르는 쪽은 뭘 써야 할지 모른다.
ControlUsageError badControlAction(String command, List<String> allowed) =>
    ControlUsageError('$command: 모르는 action (가능: ${allowed.join(", ")})');
