import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/server/host_address.dart';
import 'package:game_party_room_app/server/hotspot/hotspot_support.dart';

void main() {
  group('플랫폼 안내', () {
    test('현재 플랫폼 안내가 비어 있지 않다', () {
      final g = HotspotGuide.forCurrentPlatform();
      expect(g.title, isNotEmpty);
      expect(g.steps, isNotEmpty);
    });

    test('맥에서는 Wi-Fi 를 Wi-Fi 로 나눌 수 없다는 제약을 반드시 알린다', () {
      if (!Platform.isMacOS) return;
      final g = HotspotGuide.forCurrentPlatform();
      expect(g.capability, HotspotCapability.guided);
      expect(g.caveat, isNotNull, reason: '이 제약을 모르면 온보딩을 따라가도 실패한다');
      expect(g.caveat, contains('Wi-Fi'));
    });

    test('앱이 켤 수 있는 플랫폼은 Android 뿐이다', () {
      // 다른 플랫폼에 appManaged 를 붙이면 UI 가 "핫스팟 켜기" 버튼을 잘못 띄운다.
      final g = HotspotGuide.forCurrentPlatform();
      if (g.capability == HotspotCapability.appManaged) {
        expect(Platform.isAndroid, isTrue);
      }
    });
  });

  group('macOS 인터넷 공유 인터페이스 인식', () {
    test('bridge100 이상은 핫스팟으로 본다', () {
      expect(
        HostAddressFinder.classify('bridge100', '192.168.2.1'),
        HostAddressKind.hotspot,
      );
      expect(
        HostAddressFinder.classify('bridge101', '192.168.5.1'),
        HostAddressKind.hotspot,
      );
    });

    test('bridge0(Thunderbolt Bridge)은 핫스팟이 아니다', () {
      // 늘 존재하는 인터페이스라 핫스팟으로 오인하면 엉뚱한 주소를 최우선으로 고른다.
      expect(
        HostAddressFinder.classify('bridge0', '192.168.2.1'),
        HostAddressKind.lan,
      );
    });
  });

  group('Wi-Fi 접속 QR', () {
    test('암호가 있으면 WPA 로 만든다', () {
      expect(
        WifiQr.build(ssid: 'PartyRoom', password: 'hunter22'),
        'WIFI:T:WPA;S:PartyRoom;P:hunter22;;',
      );
    });

    test('암호가 없으면 개방형이다', () {
      expect(WifiQr.build(ssid: 'PartyRoom'), 'WIFI:T:nopass;S:PartyRoom;P:;;');
    });

    test('구분자를 이스케이프한다', () {
      // 암호에 세미콜론이 들어가면 이스케이프 없이는 QR 이 조용히 깨진다.
      expect(
        WifiQr.build(ssid: 'a;b', password: r'p:q\r'),
        r'WIFI:T:WPA;S:a\;b;P:p\:q\\r;;',
      );
    });

    test('한글 SSID 도 그대로 담는다', () {
      expect(
        WifiQr.build(ssid: '파티룸', password: '1234'),
        'WIFI:T:WPA;S:파티룸;P:1234;;',
      );
    });
  });
}
