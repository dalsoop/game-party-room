import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/host_controller.dart';
import 'package:game_party_room_app/pages/hotspot_page.dart';
import 'package:game_party_room_app/pages/lobby/address_and_internet.dart';
import 'package:game_party_room_app/pages/rooms_page.dart';
import 'package:game_party_room_app/server/app/bundle_assets.dart';
import 'package:game_party_room_app/server/host_address.dart';
import 'package:game_party_room_app/server/hotspot/hotspot_support.dart';
import 'package:party_room_server/party_room_server.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 전용 Wi-Fi 안내로 **가는 길**.
///
/// 안내문 자체는 `hotspot_support_test.dart` 가 본다. 여기서 보는 것은
/// 그것과 다른 문제다 — 아무리 좋은 안내도 **닿지 못하면 없는 것**이다.
///
/// 실제로 그랬다: 로비의 주소 줄은 `ctrl.address == null` 이면 통째로
/// 사라졌고(그 안에 "안 붙어요 · 전용 Wi-Fi" 링크가 있었다), 홈 화면이 여는
/// 주소 선택 시트에는 핫스팟 항목이 아예 없었다. 그래서 **주소가 하나도 안
/// 잡힐 때** — 전용 Wi-Fi 가 정확히 필요한 그 상황에 — 안내로 가는 길이 앱
/// 어디에도 없었다. 호스트는 "아무도 못 들어와" 앞에서 할 수 있는 게 없다.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  HostController hostWith(List<HostAddress> addresses) {
    final ctrl = HostController();
    addTearDown(ctrl.dispose);
    final srv = RoomServer(assets: const BundleAssetSource());
    srv.createRoom(name: '금요 모임');
    ctrl.server = srv;
    ctrl.room = srv.rooms.first;
    ctrl.addresses = addresses;
    return ctrl;
  }

  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pump();
  }

  const wifi = HostAddress(
    ip: '192.168.0.183',
    interfaceName: 'en0',
    kind: HostAddressKind.lan,
  );

  const guidedHotspot = HotspotGuide(
    capability: HotspotCapability.guided,
    platformName: '테스트',
    title: '전용 Wi-Fi 만들기',
    steps: [],
  );

  testWidgets('주소가 하나도 없어도 전용 Wi-Fi 로 가는 길이 보인다', (tester) async {
    await show(tester, AddressPicker(ctrl: hostWith([])));

    expect(
      find.textContaining('전용 Wi-Fi'),
      findsWidgets,
      reason: '주소가 없을 때가 이 안내가 필요한 바로 그 순간인데 길이 사라졌다',
    );
  });

  testWidgets('그 길로 누르면 안내 화면이 뜬다', (tester) async {
    await show(tester, AddressPicker(ctrl: hostWith([])));
    await tester.tap(find.text('전용 Wi-Fi 만들기'));
    await tester.pumpAndSettle();

    expect(find.byType(HotspotPage), findsOneWidget);
  });

  testWidgets('홈에서 여는 주소 시트에도 전용 Wi-Fi 항목이 있다', (tester) async {
    // 홈 화면의 주소 줄은 이 시트를 연다. 여기 없으면 방에 들어가기 전에는
    // 안내에 닿을 방법이 없다.
    final ctrl = hostWith([wifi]);
    await tester.pumpWidget(MaterialApp(home: RoomsPage(ctrl: ctrl)));
    await tester.pump();

    await tester.tap(find.textContaining('192.168.0.183'));
    await tester.pumpAndSettle();

    expect(find.text('전용 Wi-Fi 만들기'), findsOneWidget);
  });

  group('Wi-Fi 접속 QR', () {
    testWidgets('이름을 적으면 QR 이 나온다', (tester) async {
      // 실린 문자열이 표준 `WIFI:` 스킴인지는 `hotspot_support_test` 가 본다
      // (`QrImageView` 는 담고 있는 값을 밖에 안 보여준다). 여기서 볼 것은
      // **언제 나타나는가** 다 — 이름 없이 QR 을 그리면 못 쓰는 QR 이 뜬다.
      final ctrl = hostWith([]);
      await show(tester, HotspotPage(ctrl: ctrl, guide: guidedHotspot));
      await tester.pump();

      expect(find.byType(QrImageView), findsNothing);

      await tester.enterText(find.byType(TextField).first, '파티룸');
      await tester.pump();

      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('이름은 다음 파티에도 기억한다', (tester) async {
      // 플랫폼이 자기 핫스팟 이름을 앱에 안 알려줘서 호스트가 옮겨 적어야
      // 하는데, 그 값은 파티마다 그대로다. 매번 다시 치게 두지 않는다.
      final ctrl = hostWith([]);
      await show(tester, HotspotPage(ctrl: ctrl, guide: guidedHotspot));
      await tester.enterText(find.byType(TextField).first, '파티룸');
      await tester.pump();

      expect(ctrl.settings.hotspotSsid, '파티룸');
    });

    testWidgets('암호는 저장하지 않는다', (tester) async {
      // 평문 설정 파일에 Wi-Fi 암호를 남기지 않는다 — 방 비밀번호가 저장
      // 파일 밖으로 안 나가는 것과 같은 기준이다.
      final ctrl = hostWith([]);
      await show(tester, HotspotPage(ctrl: ctrl, guide: guidedHotspot));
      await tester.enterText(find.byType(TextField).at(1), 'hunter22');
      await tester.pump();

      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        expect(
          prefs.getString(k) ?? '',
          isNot(contains('hunter22')),
          reason: 'Wi-Fi 암호가 설정 파일에 남았다',
        );
      }
    });
  });
}
