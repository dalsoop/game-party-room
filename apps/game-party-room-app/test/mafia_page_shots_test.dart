import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/host_controller.dart';
import 'package:game_party_room_app/pages/mafia_page.dart';
import 'package:party_room_server/party_room_server.dart';
import 'package:party_room_server/testing.dart';

/// 마피아 진행 화면을 **그림으로 뽑는다**.
///
/// 이 창은 다른 Space 에 있으면 스크린샷조차 안 찍힌다(이 저장소가 CLI 를
/// 만든 바로 그 이유). 눈으로 확인할 것이 있을 때는 실제 위젯을 여기서
/// 렌더해 PNG 로 떨군다 — /tmp/mafia_page_<폭>.png
///
/// 판정이 아니라 눈으로 볼 거리를 만드는 테스트다. 배치 규칙 자체는
/// `mafia_page_layout_test.dart` 가 좌표로 잰다.
///
/// **평소에는 안 돈다.** 아무것도 검사하지 않으면서 매 실행마다 파일을
/// 쓰고 시간을 먹기 때문이다. 그림이 필요할 때만 켠다:
///
/// ```
/// PARTY_SHOTS=1 flutter test test/mafia_page_shots_test.dart
/// ```
void main() {
  // 켜지 않으면 통째로 건너뛴다.
  final wanted = Platform.environment['PARTY_SHOTS'] == '1';

  // 폭 · 높이 · 인원 — 마지막 것은 "정원 가까이 + 낮은 창" 으로,
  // 명단이 화면 밖으로 넘치지 않고 안에서 굴러야 한다.
  const cases = {
    'wide1400': (1400.0, 720.0, 7),
    'mid900': (900.0, 720.0, 7),
    'narrow700': (700.0, 720.0, 7),
    'crowded20': (900.0, 560.0, 20),
  };

  for (final e in cases.entries) {
    final (w, h, people) = e.value;
    // skip 은 bool 만 받는다 — 이유는 위 문서 주석에 적혀 있다.
    testWidgets('화면 ${e.key}', skip: !wanted, (tester) async {
      final ctrl = HostController();
      addTearDown(ctrl.dispose);
      final room = Room();
      ctrl.room = room;
      // 판은 **접속한 사람**으로만 짜인다. 소켓을 띄우지 않고 그림만
      // 뽑으려는 것이라, 아무 데도 안 닿는 빈 채널을 물려 준다.
      for (var i = 0; i < people; i++) {
        room.seat('손님$i')!.link = RecordingLink();
      }
      final game = MafiaGame();
      room.startGame(game);
      // 몇 명 탈락시켜 생사 표시를 확인한다.
      game.members[2].alive = false;
      game.members[5].alive = false;
      ctrl.games.mafiaPhase = 'night';
      ctrl.games.gameStatus = '2일차 밤 · 밤 행동 1/3';

      tester.view.physicalSize = Size(w, h);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: MafiaPage(ctrl: ctrl),
          ),
        ),
      );
      // HUD 에 계속 도는 애니메이션이 있어 pumpAndSettle 은 안 끝난다.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '/tmp/mafia_page_${e.key}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }
}
