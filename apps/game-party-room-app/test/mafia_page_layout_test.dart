import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/host_controller.dart';
import 'package:game_party_room_app/pages/host_hud.dart';
import 'package:game_party_room_app/pages/mafia_page.dart';
import 'package:party_room_server/party_room_server.dart';
import 'package:party_room_server/testing.dart';

/// 마피아 진행 화면이 **뭘 먼저 보여주는가**.
///
/// 이 화면은 사회자가 판을 굴리는 조종석이다. 예전에는 맨 위 150px 이
/// 장식 사진이었고 — 화면에서 제일 밝고 제일 큰 것이 눌러야 할 버튼이
/// 아니라 사진이었다 — 정작 "누가 살아 있나" 는 어디에도 없었다. 이름→역할
/// 사본만 좁은 곁칸에 가려 둔 채라, "남은 사람은…" 을 말해야 하는 사람이
/// 죽은 사람을 못 봤다.
///
/// 눈으로 보기 어려운 화면이라(창이 다른 Space 에 있으면 캡처도 안 된다)
/// 여기서 좌표로 잰다. 그림이 필요하면 `mafia_page_shots_test.dart`.
void main() {
  Future<HostController> cockpit(
    WidgetTester tester,
    Size window, {
    int people = 5,
    int dead = 1,
  }) async {
    final ctrl = HostController();
    addTearDown(ctrl.dispose);
    final room = Room();
    ctrl.room = room;
    // 판은 접속한 사람으로만 짜인다 — 소켓 없이 세우려고 빈 채널을 문다.
    for (var i = 0; i < people; i++) {
      room.seat('손님$i')!.link = RecordingLink();
    }
    final game = MafiaGame();
    room.startGame(game);
    for (var i = 0; i < dead; i++) {
      game.members[i].alive = false;
    }
    ctrl.games.mafiaPhase = 'night';
    ctrl.games.gameStatus = '2일차 밤';

    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: MafiaPage(ctrl: ctrl)));
    await tester.pump();
    return ctrl;
  }

  testWidgets('장식 사진이 조종석 맨 위를 차지하지 않는다', (tester) async {
    await cockpit(tester, const Size(1400, 720));
    expect(
      find.byType(HudBanner),
      findsNothing,
      reason: '눌러야 할 것보다 사진이 위에 있으면 안 된다',
    );
  });

  testWidgets('명단이 누가 죽었는지 보여준다', (tester) async {
    await cockpit(tester, const Size(1400, 720), people: 5, dead: 2);
    expect(find.text('5명 중 3명 생존'), findsOneWidget);
    expect(
      find.text('탈락'),
      findsNWidgets(2),
      reason: '사회자가 "남은 사람은…" 을 말하려면 이게 화면에 있어야 한다',
    );
  });

  testWidgets('진행 버튼은 어느 폭에서든 화면 아래쪽에 있다', (tester) async {
    // 어두운 방에서 사회자가 안 보고도 누른다 — 자리가 흔들리면 안 된다.
    for (final w in [1400.0, 900.0, 700.0]) {
      await cockpit(tester, Size(w, 720));
      final btn = tester.getTopLeft(find.byType(HudButton).first).dy;
      expect(
        btn,
        greaterThan(720 * 0.6),
        reason: '${w.toInt()}px 에서 버튼이 위쪽에 있다 (y=$btn)',
      );
    }
  });

  testWidgets('인원이 정원 가까워도 화면 밖으로 넘치지 않는다', (tester) async {
    // 낮은 창 + 20명. 넘치면 Flutter 가 오류를 기록한다.
    await cockpit(tester, const Size(900, 560), people: 20, dead: 3);
    expect(tester.takeException(), isNull);
    expect(find.byType(HudButton), findsWidgets, reason: '조작이 밀려 사라졌다');
  });
}
