import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/host_controller.dart';
import 'package:game_party_room_app/pages/rooms_page.dart';
import 'package:game_party_room_app/server/app/bundle_assets.dart';
import 'package:party_room_server/party_room_server.dart';
import 'package:party_room_server/testing.dart';

/// 방 목록 — 앱을 켜면 처음 보는 화면.
///
/// 방이 여러 개가 된 뒤로 **어느 방이 위에 오는가**가 곧 사용성이다. 파티
/// 중에는 지금 판이 도는 방을 찾아야 하고, 지난주 방은 아래에 있어야 한다.
/// 그 규칙이 코드에만 있고 검증이 없었다.
void main() {
  /// 방들을 세운 컨트롤러. 서버는 만들되 **포트는 안 연다** — 목록만 읽는다.
  HostController hostWith(void Function(RoomServer) build) {
    final ctrl = HostController();
    addTearDown(ctrl.dispose);
    // 이 파일은 **목록 위젯**을 시험한다 — 검색칸이 언제 나오는지, 정렬이
    // 맞는지. 방을 여럿 세워야 하므로 정원을 넉넉히 준다. 서버 기본값(2개)은
    // 정책이지 이 위젯의 계약이 아니다.
    final srv = RoomServer(assets: const BundleAssetSource(), maxRooms: 50);
    build(srv);
    ctrl.server = srv;
    ctrl.room = srv.rooms.firstOrNull;
    return ctrl;
  }

  Future<void> show(WidgetTester tester, HostController ctrl) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: RoomsPage(ctrl: ctrl)));
    await tester.pump();
  }

  /// 화면에 그려진 방 이름을 위에서부터.
  List<String> orderOf(WidgetTester tester, List<String> names) {
    final ys = <String, double>{};
    for (final n in names) {
      final f = find.text(n);
      if (f.evaluate().isEmpty) continue;
      ys[n] = tester.getTopLeft(f.first).dy;
    }
    final sorted = ys.keys.toList()..sort((a, b) => ys[a]!.compareTo(ys[b]!));
    return sorted;
  }

  testWidgets('판이 도는 방이 맨 위 — 닫힌 방은 맨 아래', (tester) async {
    final ctrl = hostWith((srv) {
      srv.createRoom(name: '닫힌방').open = false;
      srv.createRoom(name: '조용한방');
      final busy = srv.createRoom(name: '판도는방');
      busy.seat('가')!.link = RecordingLink();
      busy.startGame(MarbleGame());
      srv.createRoom(name: '사람있는방').seat('나')!.link = RecordingLink();
    });
    await show(tester, ctrl);

    expect(
      orderOf(tester, ['판도는방', '사람있는방', '조용한방', '닫힌방']),
      ['판도는방', '사람있는방', '조용한방', '닫힌방'],
      reason: '파티 중에 지금 판이 도는 방을 못 찾으면 목록이 쓸모없다',
    );
  });

  testWidgets('같은 처지면 최근에 만든 방이 위', (tester) async {
    final ctrl = hostWith((srv) {
      srv.createRoom(name: '먼저');
      srv.createRoom(name: '나중');
    });
    await show(tester, ctrl);
    expect(orderOf(tester, ['먼저', '나중']), ['나중', '먼저']);
  });

  testWidgets('방이 적으면 검색칸이 자리를 안 먹는다', (tester) async {
    final ctrl = hostWith((srv) {
      for (var i = 0; i < 3; i++) {
        srv.createRoom(name: '방$i');
      }
    });
    await show(tester, ctrl);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('방이 많아지면 검색칸이 나온다', (tester) async {
    final ctrl = hostWith((srv) {
      for (var i = 0; i < 6; i++) {
        srv.createRoom(name: '방$i');
      }
    });
    await show(tester, ctrl);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('검색은 이름과 방 코드 둘 다로 걸린다', (tester) async {
    final ctrl = hostWith((srv) {
      srv.createRoom(name: '금요 모임', token: 'AAA111');
      srv.createRoom(name: '회사 워크숍', token: 'BBB222');
      for (var i = 0; i < 4; i++) {
        srv.createRoom(name: '기타$i');
      }
    });
    await show(tester, ctrl);

    await tester.enterText(find.byType(TextField), '워크숍');
    await tester.pump();
    expect(find.text('회사 워크숍'), findsOneWidget);
    expect(find.text('금요 모임'), findsNothing);

    await tester.enterText(find.byType(TextField), 'aaa111');
    await tester.pump();
    expect(
      find.text('금요 모임'),
      findsOneWidget,
      reason: '대소문자가 달라도 방 코드로 찾아져야 한다',
    );
  });

  testWidgets('잠긴 방은 잠겼다고 보인다', (tester) async {
    // 안 보이면 호스트가 비밀번호를 걸어 둔 것을 잊고 친구에게 링크만 준다.
    final ctrl = hostWith((srv) {
      srv.createRoom(name: '잠긴방').setPin('4907');
      srv.createRoom(name: '열린방');
    });
    await show(tester, ctrl);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('방이 하나도 없어도 화면이 선다', (tester) async {
    // 전부 지운 직후의 상태 — 여기서 아무것도 못 하면 빠져나갈 길이 없다.
    final ctrl = hostWith((_) {});
    await show(tester, ctrl);
    expect(tester.takeException(), isNull);
  });
}
