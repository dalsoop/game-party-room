import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/host_controller.dart';
import 'package:game_party_room_app/pages/rooms_page.dart';
import 'package:game_party_room_app/server/app/bundle_assets.dart';
import 'package:game_party_room_app/server/host_address.dart';
import 'package:party_room_server/party_room_server.dart';

/// 홈 화면의 주소 줄.
///
/// 파티에서 제일 먼저 나오는 말이 "뭐로 들어가?" 이고, 안 붙을 때 제일 먼저
/// 볼 것도 "내가 어느 망에 있나" 다. 그걸 보려고 방을 하나 열어야 했다.
///
/// 특히 **VPN 이 붙어 있으면** 참가자가 절대 닿을 수 없는 주소가 잡힐 수
/// 있다. 그건 조용히 두면 안 된다 — 호스트는 QR 을 뿌려 놓고 왜 아무도
/// 못 들어오는지 모른 채 파티를 시작한다.
void main() {
  HostController hostWith(List<HostAddress> addresses, {int index = 0}) {
    final ctrl = HostController();
    addTearDown(ctrl.dispose);
    final srv = RoomServer(assets: const BundleAssetSource());
    srv.createRoom(name: '금요 모임');
    ctrl.server = srv;
    ctrl.room = srv.rooms.first;
    ctrl.addresses = addresses;
    ctrl.addressIndex = index;
    return ctrl;
  }

  Future<void> show(WidgetTester tester, HostController ctrl) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: RoomsPage(ctrl: ctrl)));
    await tester.pump();
  }

  const wifi = HostAddress(
    ip: '192.168.0.183',
    interfaceName: 'en0',
    kind: HostAddressKind.lan,
  );
  const vpn = HostAddress(
    ip: '10.87.40.2',
    interfaceName: 'utun6',
    kind: HostAddressKind.tunnel,
  );

  testWidgets('홈에서 바로 접속 주소가 보인다', (tester) async {
    await show(tester, hostWith([wifi]));
    expect(
      find.textContaining('192.168.0.183'),
      findsOneWidget,
      reason: '"뭐로 들어가?" 에 답하려고 방을 열어야 하면 순서가 거꾸로다',
    );
    expect(find.text('Wi-Fi / 유선'), findsOneWidget);
  });

  testWidgets('VPN 주소가 잡히면 경고로 보인다', (tester) async {
    // 이걸 조용히 두면 호스트는 QR 을 뿌려 놓고 왜 아무도 못 들어오는지
    // 모른 채 파티를 시작한다.
    await show(tester, hostWith([vpn]));
    expect(find.textContaining('10.87.40.2'), findsOneWidget);
    expect(
      find.byIcon(Icons.warning_amber_rounded),
      findsOneWidget,
      reason: '참가자가 못 닿는 주소인데 평범하게 보이면 안 된다',
    );
  });

  testWidgets('쓸 수 있는 주소가 없으면 무엇을 하라고 알려준다', (tester) async {
    await show(tester, hostWith([]));
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(
      find.textContaining('Wi-Fi'),
      findsWidgets,
      reason: '"주소 없음" 만 띄우면 무엇을 해야 할지 모른다',
    );
  });

  testWidgets('주소가 여럿이면 바꿀 수 있다는 표시가 있다', (tester) async {
    await show(tester, hostWith([wifi, vpn]));
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('인터넷으로 열려 있으면 그 주소를 보여준다', (tester) async {
    final ctrl = hostWith([wifi])
      ..externalBase = 'https://abc.trycloudflare.com';
    await show(tester, ctrl);
    expect(find.textContaining('trycloudflare.com'), findsOneWidget);
    expect(find.text('인터넷으로 열려 있음'), findsOneWidget);
    expect(
      find.byIcon(Icons.warning_amber_rounded),
      findsNothing,
      reason: '터널이 열려 있으면 로컬 주소 경고는 뜻이 없다',
    );
  });
}
