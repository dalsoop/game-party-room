/// 파티룸 랑데부 서버.
///
/// 로컬 우선이 이 앱의 기본이다 — 같은 Wi-Fi 면 참가자는 호스트에게 곧장
/// 붙고 릴레이는 등장하지 않는다. 릴레이는 그게 안 될 때의 길이다:
/// 망이 다르거나, AP 격리가 걸렸거나, 방화벽이 막았거나.
///
/// 닌텐도 Pia 의 LDN·LAN·NEX 셋 중 NEX 자리에 해당한다.
library;

export 'protocol.dart';
export 'relay_server.dart';
