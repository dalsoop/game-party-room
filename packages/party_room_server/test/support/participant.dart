import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// 붙은 소켓에 **누구인지 밝힌다** — 인증은 첫 프레임으로 한다.
///
/// 예전에는 `/ws?session=…` 로도 붙을 수 있었고 테스트가 전부 그 길을 썼다.
/// 세션 토큰은 이 앱의 인증 자격증명이라 주소에 담으면 브라우저 방문기록·
/// 중간 프록시 로그·인터넷 개방 시 Cloudflare 접속 로그에 그대로 남는다.
/// 참가자 화면이 첫 프레임으로 옮긴 뒤 그 경로는 없앴고, 테스트도 실제
/// 참가자와 같은 길로 붙어야 계약을 검증하는 것이 된다.
void authAs(WebSocketChannel ws, String? session) =>
    ws.sink.add(jsonEncode({'type': 'auth', 'session': session}));

/// 참가자 소켓 주소. 세션은 여기 담지 않는다 — [authAs] 로 밝힌다.
String wsUrl(int port, String room) =>
    'ws://127.0.0.1:$port/ws?room=${Uri.encodeComponent(room)}';

/// 조건이 참이 될 때까지 기다린다 (최대 [timeout]).
///
/// 고정 지연(`Future.delayed(150ms)`)으로 기다리면 기계가 바쁠 때 밀린다 —
/// 테스트를 여럿 동시에 돌리면 그 사이 아무 일도 안 일어나서, 코드가
/// 멀쩡한데도 빨간불이 뜬다. 얼마나 걸리는지가 아니라 **무슨 상태가 되는지**
/// 를 기다려야 한다.
Future<void> waitUntil(
  bool Function() done, {
  Duration timeout = const Duration(seconds: 5),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('기다리다 지쳤다: ${reason ?? "조건이 참이 되지 않았다"}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// 특정 종류의 프레임이 폰(테스트의 inbox)에 도착할 때까지 기다린다.
///
/// 서버가 보낸 시점과 클라이언트가 받은 시점은 다르다. 고정 지연으로
/// 그 사이를 메우면 기계가 바쁠 때 밀려서, 코드가 멀쩡한데 빨간불이 뜬다.
Future<void> waitForFrame(
  List<Map<String, dynamic>> inbox,
  String type, {
  Duration timeout = const Duration(seconds: 5),
}) => waitUntil(
  () => inbox.any((m) => m['type'] == type),
  timeout: timeout,
  reason: "'$type' 프레임이 안 왔다",
);

// 아무 데도 안 닿는 소켓(`NowhereSocket`)은 여기 있었다. 통로가
// `ParticipantLink` 로 좁아지면서 `package:party_room_server/testing.dart` 의
// `RecordingLink` 한 벌로 합쳐졌다 — 파일마다 흩어져 있던 같은 가짜들과 함께.
