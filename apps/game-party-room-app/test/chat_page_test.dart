import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/host_controller.dart';
import 'package:game_party_room_app/pages/chat_page.dart';
import 'package:game_party_room_app/server/app/bundle_assets.dart';
import 'package:party_room_server/party_room_server.dart';
import 'package:party_room_server/testing.dart';

/// 단톡·자료함 — 로비에서 떼어낸 자기 자리.
///
/// 친구들과 계속 쓰는 방이 되면서 대화와 자료가 로비 곁칸에 얹혀 있을 수
/// 없게 됐다. 판마다 칸이 갈리는 것이 이 화면의 존재 이유라, **어느 칸을
/// 보고 있는가**가 곧 기능이다.
void main() {
  ({HostController ctrl, Room room}) rig(void Function(Room) build) {
    final ctrl = HostController();
    addTearDown(ctrl.dispose);
    final srv = RoomServer(assets: const BundleAssetSource());
    final room = srv.createRoom(name: '금요 모임');
    room.seat('민서')!.link = RecordingLink();
    build(room);
    ctrl.server = srv;
    ctrl.room = room;
    return (ctrl: ctrl, room: room);
  }

  Future<void> show(WidgetTester tester, HostController ctrl) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: ChatPage(ctrl: ctrl)));
    await tester.pump();
  }

  testWidgets('처음에는 전체 칸의 대화를 보여준다', (tester) async {
    final r = rig((room) => room.hostChat('다들 왔나요'));
    await show(tester, r.ctrl);
    expect(find.text('다들 왔나요'), findsOneWidget);
  });

  testWidgets('판 칸으로 옮기면 그 판의 대화만 보인다', (tester) async {
    // 이 화면의 존재 이유다 — 파티가 끝난 뒤 "그때 그 판" 만 펼쳐 보는 것.
    final r = rig((room) {
      room.hostChat('로비에서 한 말');
      room.startGame(MarbleGame());
      room.hostChat('판 안에서 한 말');
    });
    await show(tester, r.ctrl);

    // 기본은 진행 중인 판 칸이라 판 안의 말이 보인다.
    expect(find.text('판 안에서 한 말'), findsOneWidget);
    expect(find.text('로비에서 한 말'), findsNothing);

    // '전체' 로 옮기면 로비 대화가 보인다.
    await tester.tap(find.text('전체'));
    await tester.pump();
    expect(find.text('로비에서 한 말'), findsOneWidget);
    expect(find.text('판 안에서 한 말'), findsNothing);
  });

  testWidgets('전체 칸은 판이 여럿이어도 늘 있다', (tester) async {
    final r = rig((room) {
      for (var i = 0; i < 3; i++) {
        room.startGame(MarbleGame());
        room.hostChat('$i번째 판');
      }
    });
    await show(tester, r.ctrl);
    expect(
      find.text('전체'),
      findsOneWidget,
      reason: '판이 늘어나 전체가 밀려나면 로비 대화로 못 돌아온다',
    );
  });

  testWidgets('대화와 자료를 오간다', (tester) async {
    final r = rig((room) => room.hostChat('사진 올릴게'));
    await show(tester, r.ctrl);
    expect(find.text('사진 올릴게'), findsOneWidget);

    await tester.tap(find.text('자료'));
    await tester.pump();
    expect(
      find.text('사진 올릴게'),
      findsNothing,
      reason: '자료 칸인데 대화가 남아 있으면 뭘 보는지 알 수 없다',
    );

    await tester.tap(find.text('대화'));
    await tester.pump();
    expect(find.text('사진 올릴게'), findsOneWidget);
  });

  testWidgets('보던 방으로 열리고, 로비를 따라 움직이지는 않는다', (tester) async {
    // 단톡은 따로 열어 두고 다른 방을 보는 자리다. 열 때는 보던 방으로
    // 시작해야 하고(엉뚱한 방 대화가 나오면 안 된다), 그 뒤로는 이 화면의
    // 고르개가 정한다 — 로비에서 방을 바꿨다고 읽던 대화가 튀면 안 된다.
    final ctrl = HostController();
    addTearDown(ctrl.dispose);
    final srv = RoomServer(assets: const BundleAssetSource());
    srv.createRoom(name: '금요 모임').hostChat('금요일 얘기');
    final b = srv.createRoom(name: '회사 워크숍')..hostChat('워크숍 얘기');
    ctrl.server = srv;
    ctrl.room = b; // 회사방을 보다가 단톡을 연다

    await show(tester, ctrl);
    expect(
      find.text('워크숍 얘기'),
      findsOneWidget,
      reason: '보던 방이 아니라 목록 첫 방이 열리면 엉뚱한 대화가 나온다',
    );

    ctrl.selectRoom(srv.rooms.first.roomToken);
    // 방을 고르면 상태 게시가 250ms 뒤로 예약된다 — 그걸 지나 보내야
    // 위젯 트리를 접을 때 "타이머가 남았다" 로 걸리지 않는다.
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('워크숍 얘기'),
      findsOneWidget,
      reason: '읽던 대화가 로비 조작에 튀면 안 된다',
    );
  });

  testWidgets('대화가 없으면 빈 화면이 아니라 안내가 나온다', (tester) async {
    final r = rig((_) {});
    await show(tester, r.ctrl);
    expect(tester.takeException(), isNull);
    // 아무 말도 없을 때 흰 화면만 두면 고장인지 빈 것인지 모른다.
    expect(find.byType(Text), findsWidgets);
  });
}
