import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/host_controller.dart';
import 'package:game_party_room_app/pages/relay_page.dart';
import 'package:game_party_room_app/pages/rooms_page.dart';
import 'package:game_party_room_app/server/app/bundle_assets.dart';
import 'package:game_party_room_app/server/host_address.dart';
import 'package:party_room_server/party_room_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 밖에 있는 사람을 들이는 길 — 화면 쪽.
///
/// 프로토콜과 서버는 `party_room_relay` 와 `relay_e2e_test` 가 본다.
/// 여기서 보는 것은 **호스트가 이걸 발견하고 켜고 끌 수 있는가** 다.
/// 아무리 잘 도는 기능도 화면에서 못 찾으면 없는 것이다 — 전용 Wi-Fi 안내가
/// 정확히 그랬다(주소가 없을 때 링크가 통째로 사라졌다).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  HostController host() {
    final ctrl = HostController();
    addTearDown(ctrl.dispose);
    final srv = RoomServer(assets: const BundleAssetSource(), port: 0);
    srv.createRoom(name: '금요 모임');
    ctrl.server = srv;
    ctrl.room = srv.rooms.first;
    ctrl.addresses = const [
      HostAddress(
        ip: '192.168.0.183',
        interfaceName: 'en0',
        kind: HostAddressKind.lan,
      ),
    ];
    return ctrl;
  }

  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pump();
  }

  testWidgets('주소 시트에서 이 길을 찾을 수 있다', (tester) async {
    final ctrl = host();
    await tester.pumpWidget(MaterialApp(home: RoomsPage(ctrl: ctrl)));
    await tester.pump();

    await tester.tap(find.textContaining('192.168.0.183'));
    await tester.pumpAndSettle();

    expect(find.text('밖에 있는 사람 들이기'), findsOneWidget);
    await tester.tap(find.text('밖에 있는 사람 들이기'));
    await tester.pumpAndSettle();
    expect(find.byType(RelayPage), findsOneWidget);
  });

  testWidgets('꺼져 있으면 그렇게 말하고, 로컬만 된다고 알린다', (tester) async {
    await show(tester, RelayPage(ctrl: host()));
    expect(find.text('꺼져 있습니다'), findsOneWidget);
    expect(find.textContaining('같은 Wi-Fi'), findsWidgets);
  });

  testWidgets('서버 주소가 없으면 켤 수 없다', (tester) async {
    // 주소 없이 켜면 조용히 아무 일도 안 일어난다 — 그 상태를 버튼이
    // 먼저 보여줘야 호스트가 무엇을 해야 할지 안다.
    await show(tester, RelayPage(ctrl: host()));
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '켜기'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('자료가 안 된다는 것을 미리 알린다', (tester) async {
    // "왜 사진이 안 올라가?" 는 파티에서 반드시 나온다. 겪은 뒤에 알면 늦다.
    await show(tester, RelayPage(ctrl: host()));
    expect(find.textContaining('자료'), findsWidgets);
    expect(find.textContaining('대화와 게임은 다 됩니다'), findsOneWidget);
  });

  testWidgets('서버 주소는 다음에도 기억한다', (tester) async {
    // 켜지 않고 나가도 남아야 한다. 랑데부 서버 주소는 한 번 정하면
    // 계속 같은 값이라, 파티마다 다시 치게 두지 않는다.
    final ctrl = host();
    await show(tester, RelayPage(ctrl: ctrl));
    await tester.enterText(find.byType(TextField), 'https://party.example.com');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(ctrl.settings.relayBase, 'https://party.example.com');
  });

  testWidgets('주소를 적으면 켤 수 있게 된다', (tester) async {
    final ctrl = host();
    await show(tester, RelayPage(ctrl: ctrl));
    await tester.enterText(find.byType(TextField), 'https://party.example.com');
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '켜기'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('아직 코드가 없으면 QR 을 안 보여준다', (tester) async {
    // 코드 없이 만든 QR 은 아무 데도 안 닿는다. 그걸 참가자에게 들이대는
    // 것이 제일 나쁘다.
    final ctrl = host();
    await show(tester, RelayPage(ctrl: ctrl));
    expect(find.textContaining('밖에 있는 사람에게 보여줄 QR'), findsNothing);
  });
}
