import 'dart:convert';
import 'dart:io';

/// 방 서버가 앉을 포트 고르기.
///
/// 기본 포트가 막혀 있으면 예전에는 그냥 "이미 파티룸이 실행 중입니다" 를
/// 띄우고 끝이었다. 그런데 8765 를 쓰는 프로그램은 파티룸만이 아니다 —
/// 남의 개발 서버 하나 때문에 앱이 아예 안 열리고, 원인은 틀린 문구뿐이다.
/// 이제 **누가 물고 있는지 확인해서** 갈라진다: 파티룸이면 안내하고,
/// 남이면 옆 포트로 비켜 앉는다.
class RoomPort {
  const RoomPort._();

  /// [start] 부터 [tries] 개를 훑는다.
  /// 성공하면 (포트, null), 실패하면 (null, 사람이 읽을 이유).
  static Future<(int?, String?)> pick({
    required int start,
    int tries = 6,
  }) async {
    for (var port = start; port < start + tries; port++) {
      if (await _free(port)) return (port, null);
      if (port == start && await _looksLikePartyRoom(port)) {
        return (null, '이미 파티룸이 실행 중입니다.\n기존 창을 닫고 다시 시작하세요. (포트 $port 사용 중)');
      }
    }
    return (
      null,
      '$start~${start + tries - 1} 번 포트가 모두 사용 중입니다.\n'
          '다른 프로그램을 닫고 다시 시작하세요.',
    );
  }

  static Future<bool> _free(int port) async {
    try {
      final s = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      await s.close();
      return true;
    } on SocketException {
      return false;
    }
  }

  /// 그 포트에 앉은 것이 우리인가 — 참가자 화면을 받아 확인한다.
  static Future<bool> _looksLikePartyRoom(int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.get('127.0.0.1', port, '/');
      final res = await req.close().timeout(const Duration(seconds: 2));
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 2));
      return body.contains('<title>파티룸</title>');
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}

/// 참가자가 접속할 수 있는 호스트 주소 후보 하나.
class HostAddress {
  const HostAddress({
    required this.ip,
    required this.interfaceName,
    required this.kind,
  });

  final String ip;
  final String interfaceName;
  final HostAddressKind kind;

  /// 화면에 붙일 짧은 설명.
  String get label => switch (kind) {
    HostAddressKind.hotspot => '핫스팟',
    HostAddressKind.lan => 'Wi-Fi / 유선',
    HostAddressKind.tunnel => 'VPN (참가자는 접속 못 할 수 있음)',
  };
}

enum HostAddressKind { hotspot, lan, tunnel }

/// 방 주소로 쓸 후보를 찾아 좋은 순서로 준다.
///
/// 예전에는 `첫 번째 사설 IP` 하나만 골랐다. 호스트에 VPN 이 붙어 있으면
/// 터널 주소(10.x)가 먼저 잡혀, 참가자가 절대 닿을 수 없는 주소를 QR 로 뿌린다.
/// 이제 후보를 전부 모아 순위를 매기고, 호스트가 바꿀 수 있게 한다.
class HostAddressFinder {
  /// 터널·가상 인터페이스 접두사 — 여기 붙은 주소는 같은 자리 참가자가 닿지 못한다.
  static const _tunnelPrefixes = [
    'utun',
    'tun',
    'tap',
    'ppp',
    'ipsec',
    'wg',
    'gif',
    'stf',
  ];

  static Future<List<HostAddress>> candidates() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final found = <HostAddress>[];
    for (final ni in interfaces) {
      for (final addr in ni.addresses) {
        final kind = classify(ni.name, addr.address);
        if (kind == null) continue;
        found.add(
          HostAddress(ip: addr.address, interfaceName: ni.name, kind: kind),
        );
      }
    }
    found.sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return found;
  }

  /// 이 주소를 방 주소로 쓸 수 있는지, 쓸 수 있다면 어떤 종류인지.
  /// 쓸 수 없으면 null.
  static HostAddressKind? classify(String interfaceName, String ip) {
    if (!isPrivateIPv4(ip)) return null;

    // 핫스팟 대역 — 참가자가 호스트에 직접 붙은 상태라 가장 확실하다.
    // 172.20.10.x = iOS 개인용 핫스팟, 192.168.43.x = Android 테더링,
    // 192.168.49.x = Wi-Fi Direct.
    if (ip.startsWith('172.20.10.') ||
        ip.startsWith('192.168.43.') ||
        ip.startsWith('192.168.49.')) {
      return HostAddressKind.hotspot;
    }

    final name = interfaceName.toLowerCase();

    // macOS 인터넷 공유는 bridge100 부터 올려 붙인다(bridge0 은 Thunderbolt Bridge 로
    // 늘 존재하니 제외). 기본 대역은 192.168.2.x 지만 충돌 시 바뀌므로 이름으로 본다.
    if (_isSharingBridge(name)) return HostAddressKind.hotspot;

    if (_tunnelPrefixes.any(name.startsWith)) return HostAddressKind.tunnel;

    return HostAddressKind.lan;
  }

  static bool _isSharingBridge(String name) {
    if (!name.startsWith('bridge')) return false;
    final n = int.tryParse(name.substring('bridge'.length));
    return n != null && n >= 100;
  }

  /// RFC1918 사설 대역. `172.` 전체를 사설로 보면 172.32~172.255 같은 **공인** 주소까지
  /// 방 주소로 골라 참가자가 붙지 못한다 — 172 는 16~31 만이다.
  /// 링크로컬(169.254.x)도 제외한다 — DHCP 실패 시 붙는 주소라 통신이 안 된다.
  static bool isPrivateIPv4(String ip) {
    if (ip.startsWith('169.254.')) return false;
    if (ip.startsWith('192.168.') || ip.startsWith('10.')) return true;
    if (!ip.startsWith('172.')) return false;
    final parts = ip.split('.');
    if (parts.length < 2) return false;
    final second = int.tryParse(parts[1]);
    return second != null && second >= 16 && second <= 31;
  }
}
