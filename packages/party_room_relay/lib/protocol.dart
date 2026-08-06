/// 호스트와 랑데부 서버가 쓰는 말.
///
/// **이 파일은 게임을 모른다.** 릴레이가 아는 것은 "코드 ABCD 의 호스트에게
/// 이 프레임을 넘겨라" 뿐이고, 프레임 속은 들여다보지 않는다 — 그래야
/// 릴레이가 파티룸 버전과 무관하게 돌고, 게임 규칙이 남의 서버에 안 산다.
///
/// 닌텐도 NEX 가 하는 일도 딱 이만큼이다: 짝을 지어 주고, 서로 찌를 수 있게
/// 해 준 다음 빠진다. 다른 점은 우리 한쪽이 **브라우저**라 UDP 로 구멍을 뚫을
/// 수 없다는 것뿐이다 — 그래서 우리는 빠지는 대신 프레임을 날라 준다.
/// 그래도 싸다: 한 판 5명에 실시간 트래픽이 9.7KB 다.
library;

import 'dart:convert';

/// 이 프로토콜의 판. 호스트와 릴레이가 다르면 붙자마자 거절한다 —
/// 어긋난 채로 반쯤 도는 것이 제일 나쁘다.
const relayProtocolVersion = 1;

/// 방 코드에 쓰는 글자.
///
/// `0/O`·`1/I/l`·`2/Z`·`5/S`·`8/B` 를 뺐다. 이 코드는 **사람이 불러 주고
/// 받아 적는다** — 파티에서 "영이야 오야?" 로 한 번 막히면 QR 을 두고도
/// 못 들어온다.
const relayCodeAlphabet = 'ACDEFGHJKMNPQRTUVWXY34679';

/// 방 코드 길이. 25^4 ≈ 39만 — 동시에 열려 있는 파티 수를 생각하면 넉넉하다.
const relayCodeLength = 4;

/// 호스트↔릴레이 프레임 종류.
///
/// 짧은 이름을 쓴다. 이 프레임은 참가자 프레임을 **감싸서** 오가므로,
/// 긴 키 이름이 모든 채팅 한 줄마다 따라다닌다.
abstract final class RelayFrame {
  // ---- 호스트 → 릴레이 ----

  /// 등록. `{t, v, secret, code?}` — code 를 주면 그 코드를 다시 달라는 뜻
  /// (재접속). 남의 코드를 달라고 해도 secret 이 다르면 안 준다.
  static const hello = 'hello';

  /// 참가자에게 내려보낼 프레임. `{t, c, d}`
  static const data = 'data';

  /// 이 참가자 통로를 접는다. `{t, c}`
  static const close = 'close';

  /// HTTP 응답. `{t, i, s, b}`
  static const httpRes = 'http_res';

  // ---- 릴레이 → 호스트 ----

  /// 등록 완료. `{t, code, url}`
  static const ready = 'ready';

  /// 등록 거절. `{t, reason}`
  static const denied = 'denied';

  /// 참가자가 붙었다. `{t, c}`
  static const open = 'open';

  /// 참가자가 올려보낸 프레임. `{t, c, d}` — data 와 같은 모양, 방향만 반대.

  /// 참가자가 부탁한 HTTP. `{t, i, m, p, b}`
  static const http = 'http';

  /// 살아 있나. 호스트는 [pong] 으로 답한다. `{t}`
  static const ping = 'ping';
  static const pong = 'pong';
}

/// 프레임 한 줄을 만든다.
String encodeRelay(Map<String, Object?> m) => jsonEncode(m);

/// 프레임 한 줄을 읽는다. 못 읽으면 null — 남이 보낸 쓰레기에 서버가
/// 죽으면 안 된다.
Map<String, dynamic>? decodeRelay(Object? raw) {
  if (raw is! String) return null;
  try {
    final v = jsonDecode(raw);
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}

/// 릴레이에 태우지 않는 경로.
///
/// 자료 올리기·내려받기는 한 사람이 30MB, 방 하나가 1GB 다. 실시간
/// 프레임(참가자당 2KB)과 **네 자릿수 차이**라, 이것까지 날라 주는 순간
/// 릴레이는 "가벼운 서버" 가 아니게 된다. 같은 망일 때만 쓰는 기능으로
/// 두고, 릴레이로 들어온 참가자에게는 화면에서 아예 감춘다.
bool isRelayRefused(String path) {
  final p = path.startsWith('/') ? path.substring(1) : path;
  return p == 'api/upload' || p.startsWith('file/');
}
