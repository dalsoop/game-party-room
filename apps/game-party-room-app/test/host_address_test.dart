import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/server/host_address.dart';

void main() {
  group('사설 대역 판정', () {
    test('RFC1918 만 사설로 본다', () {
      expect(HostAddressFinder.isPrivateIPv4('192.168.3.19'), isTrue);
      expect(HostAddressFinder.isPrivateIPv4('10.87.40.2'), isTrue);
      expect(HostAddressFinder.isPrivateIPv4('172.16.0.1'), isTrue);
      expect(HostAddressFinder.isPrivateIPv4('172.31.255.254'), isTrue);
    });

    test('172 대역 밖의 공인 주소를 사설로 오인하지 않는다', () {
      // 예전 구현은 `startsWith('172.')` 라 172.217.x(구글) 까지 사설로 봤다.
      expect(HostAddressFinder.isPrivateIPv4('172.15.0.1'), isFalse);
      expect(HostAddressFinder.isPrivateIPv4('172.32.0.1'), isFalse);
      expect(HostAddressFinder.isPrivateIPv4('172.217.31.14'), isFalse);
      expect(HostAddressFinder.isPrivateIPv4('8.8.8.8'), isFalse);
    });

    test('링크로컬은 제외한다 (DHCP 실패 주소)', () {
      expect(HostAddressFinder.isPrivateIPv4('169.254.1.2'), isFalse);
    });
  });

  group('주소 분류', () {
    test('핫스팟 대역을 알아본다', () {
      expect(
        HostAddressFinder.classify('en0', '172.20.10.1'),
        HostAddressKind.hotspot,
      ); // iOS 개인용 핫스팟
      expect(
        HostAddressFinder.classify('wlan0', '192.168.43.1'),
        HostAddressKind.hotspot,
      ); // Android 테더링
      expect(
        HostAddressFinder.classify('p2p0', '192.168.49.1'),
        HostAddressKind.hotspot,
      ); // Wi-Fi Direct
    });

    test('VPN 터널 인터페이스를 뒤로 민다', () {
      expect(
        HostAddressFinder.classify('utun6', '10.87.40.2'),
        HostAddressKind.tunnel,
      );
      expect(
        HostAddressFinder.classify('wg0', '10.0.0.2'),
        HostAddressKind.tunnel,
      );
      expect(
        HostAddressFinder.classify('ppp0', '10.1.2.3'),
        HostAddressKind.tunnel,
      );
    });

    test('일반 Wi-Fi 는 lan 이다', () {
      expect(
        HostAddressFinder.classify('en0', '192.168.3.19'),
        HostAddressKind.lan,
      );
    });

    test('공인 주소는 후보에서 뺀다', () {
      expect(HostAddressFinder.classify('en0', '203.0.113.5'), isNull);
    });

    test('핫스팟 > LAN > 터널 순으로 정렬된다', () {
      // enum 순서가 곧 우선순위 — candidates() 가 이 순서로 정렬한다.
      expect(
        HostAddressKind.hotspot.index,
        lessThan(HostAddressKind.lan.index),
      );
      expect(HostAddressKind.lan.index, lessThan(HostAddressKind.tunnel.index));
    });
  });
}
