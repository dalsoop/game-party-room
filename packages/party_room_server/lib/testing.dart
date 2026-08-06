/// 테스트용 통로 대역.
///
/// 별도 진입점인 이유: 이것들은 배포되는 앱이 쓸 물건이 아니다.
/// (`package:http/testing.dart` 와 같은 관례.)
///
/// 예전에는 파일마다 `WebSocketChannel` 을 흉내 내는 가짜를 따로 만들었다 —
/// `NowhereSocket`·`_FakeChannel`·`_ClosingSocket`… 이름만 다른 같은 것이
/// 여러 벌 있었다. 통로가 [ParticipantLink] 로 좁아진 지금은 한 벌이면 된다.
library;

import 'dart:convert';

import 'src/participant_link.dart';

export 'src/participant_link.dart' show LinkPath, ParticipantLink;

/// 보낸 것을 다 기억하는 통로. 아무 데도 안 닿는다.
///
/// `Player.connected` 는 통로가 붙었는지로 판정하므로, 자리만 만들고
/// 통로를 안 주면 "아무도 접속 안 함" 이 된다 — 전원 투표 자동 마감처럼
/// **접속자 수를 보는 규칙**은 그 상태로는 시험할 수 없다.
class RecordingLink implements ParticipantLink {
  RecordingLink({this.path = LinkPath.direct});

  @override
  final LinkPath path;

  /// 내려간 프레임 원문, 순서대로.
  final List<String> sent = [];

  bool closed = false;

  /// 이 종류의 프레임이 하나라도 내려갔는가.
  bool sentType(String type) =>
      sent.any((s) => (jsonDecode(s) as Map)['type'] == type);

  /// 마지막으로 내려간 이 종류의 프레임.
  Map<String, dynamic>? last(String type) {
    for (final s in sent.reversed) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      if (m['type'] == type) return m;
    }
    return null;
  }

  @override
  void send(String frame) {
    // 닫힌 뒤에 온 것은 버린다 — 진짜 소켓도 그렇게 행동한다.
    if (closed) return;
    sent.add(frame);
  }

  @override
  void sendJson(Map<String, dynamic> message) => send(jsonEncode(message));

  @override
  Future<void> close() async {
    // **한 틱 미룬다.** 여기서 곧바로 `closed = true` 를 하면, 닫힘을
    // 기다리지 않는 구현도 테스트를 통과한다 — `dispose()`/`clear()` 가
    // "다 닫았다" 고 돌아온 뒤에도 통로가 살아 있던 실제 버그를 잡아낸
    // 것이 정확히 이 한 틱이었다. 편의를 위해 지우지 말 것.
    await Future<void>.delayed(Duration.zero);
    closed = true;
  }
}

/// 보내려 하면 터지는 통로 — 죽어 가는 소켓을 흉내 낸다.
///
/// 실제로 일어난다: 참가자가 탭을 닫으면 sink 는 먼저 닫히고 `onDone` 은
/// 조금 뒤에 온다. 그 사이의 브로드캐스트는 **닫힌 sink 에 add** 가 된다.
class DeadLink implements ParticipantLink {
  @override
  LinkPath get path => LinkPath.direct;

  @override
  void send(String frame) => throw StateError('Cannot add event after closing');

  @override
  void sendJson(Map<String, dynamic> message) => send(jsonEncode(message));

  @override
  Future<void> close() async {}
}
