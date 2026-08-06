import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// 참가자가 **어느 길로** 왔는가.
///
/// 방과 게임은 이걸 보지 않는다 — 누가 붙었는지만 알면 된다. 보는 쪽은
/// 둘뿐이다: 진단 화면(호스트가 상황을 파악할 때)과 자료 정책(중계로 온
/// 참가자에게 30MB 업로드를 열어 주면 남의 서버 대역폭을 태운다).
enum LinkPath {
  /// 같은 망에서 우리 포트로 곧장. 오늘의 기본이자 언제나 가장 빠른 길.
  direct,

  /// 랑데부 서버가 물어다 준 통로.
  relay,
}

/// 참가자 한 명에게 닿는 통로.
///
/// 방이 소켓을 직접 들고 있으면 길을 하나 늘릴 때마다 방을 뜯어야 한다.
/// 닌텐도 Pia 가 로컬 통신과 인터넷 통신에 **공통 API** 를 씌운 이유가
/// 이것이다 — 게임은 어느 길로 왔는지 몰라야 하고, 길은 나중에 늘어난다.
/// (LDN·LAN·NEX 셋이 같은 인터페이스 뒤에 있다.)
///
/// 이 통로가 할 줄 아는 일은 **둘뿐**이다: 프레임 하나 보내기, 닫기.
/// 떼어내기 전 방이 실제로 쓰던 것도 정확히 그 둘이었다.
abstract class ParticipantLink {
  /// 이 통로가 온 길. 기본은 [LinkPath.direct].
  LinkPath get path => LinkPath.direct;

  /// 프레임 하나를 내려 보낸다. 이미 닫혔으면 조용히 버린다 —
  /// 끊긴 참가자에게 보내려다 방 전체 브로드캐스트가 터지면 안 된다.
  void send(String frame);

  /// 지도 대신 지형: 방은 늘 Map 을 보내므로 직렬화를 여기서 한 번만 한다.
  void sendJson(Map<String, dynamic> message) => send(jsonEncode(message));

  Future<void> close();
}

/// 우리 포트에 직접 붙은 WebSocket.
class WebSocketLink implements ParticipantLink {
  WebSocketLink(this.channel);

  final WebSocketChannel channel;

  @override
  LinkPath get path => LinkPath.direct;

  @override
  void send(String frame) {
    // 닫히는 중인 소켓에 add 하면 StateError 가 난다. 그 하나 때문에
    // `broadcast` 가 중간에서 끊기면 **뒷사람들이 통째로 프레임을 놓친다**.
    try {
      channel.sink.add(frame);
    } catch (_) {}
  }

  @override
  void sendJson(Map<String, dynamic> message) => send(jsonEncode(message));

  @override
  Future<void> close() async {
    try {
      await channel.sink.close();
    } catch (_) {}
  }
}
