import 'dart:async';
import 'dart:convert';

import 'participant_link.dart';
import 'room.dart';

/// 붙은 통로 하나를 방에 편입시킨다.
///
/// WS 로 곧장 오든 랑데부가 물어다 주든, 참가자가 방에 들어오는 절차는
/// **한 곳**이어야 한다: 인증 프레임을 기다리고, 자리를 잇고, 끊기면 정리한다.
/// 길마다 이 절차를 따로 쓰면 한쪽에만 고쳐진 구멍이 생긴다 — 세션 토큰을
/// 주소에서 빼낸 것이 정확히 그런 종류의 수정이었고, 그때 고칠 자리가
/// 둘이었다면 하나는 지금도 열려 있었을 것이다.
///
/// [inbound] 는 이 통로로 들어오는 원문 프레임. 스트림이 끝나면 정리한다.
/// 돌려주는 구독은 부르는 쪽이 취소할 수 있다(릴레이가 통로를 접을 때).
StreamSubscription<dynamic> serveParticipant({
  required Room room,
  required ParticipantLink link,
  required Stream<dynamic> inbound,
  Duration authTimeout = const Duration(seconds: 10),
}) {
  Player? player;
  Timer? deadline;

  void disconnect() {
    deadline?.cancel();
    room.unwatchPending(link);
    final p = player;
    if (p != null) room.detach(p, link);
  }

  bool authenticate(String? session) {
    final p = room.bySession(session);
    if (p == null) return false;
    // 방이 지워졌으면 참가자 맵이 아직 메모리에 남아 있어도 붙이지 않는다.
    if (room.closed) return false;
    deadline?.cancel();
    player = p;
    room.attach(p, link);
    return true;
  }

  // 아직 누구인지 모르는 통로 — 방이 지워질 때 같이 닫으려면 방이 이것을
  // 알고 있어야 한다. 예전에는 `Player.channel` 에만 달려 있어서, 인증 전
  // 통로는 방 삭제를 살아남았다.
  room.watchPending(link);

  // 세션 토큰은 **주소에 담지 않는다** — 붙은 뒤 첫 프레임으로 받는다.
  // URL 은 어디에나 남는다: 브라우저 방문기록, 중간 프록시 로그, 그리고
  // 인터넷으로 열었을 때는 터널 제공자의 접속 로그.
  link.sendJson({'type': 'auth_required'});
  deadline = Timer(authTimeout, () {
    // 인증 프레임이 안 오면 자리를 물고 있을 이유가 없다.
    if (player == null) link.close();
  });

  return inbound.listen(
    (raw) {
      if (player != null) {
        room.handleMessage(player!, raw);
        return;
      }
      if (raw is! String || raw.length > room.limits.messageBytes) {
        link.close();
        return;
      }
      Map<String, dynamic> msg;
      try {
        msg = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      if (msg['type'] != 'auth') return;
      if (!authenticate(msg['session'] as String?)) {
        link.sendJson({'type': 'auth_failed'});
        link.close();
      }
    },
    onDone: disconnect,
    // 비정상 종료(네트워크 끊김 등)는 onDone 없이 onError 로 온다.
    onError: (_) => disconnect(),
    cancelOnError: true,
  );
}
