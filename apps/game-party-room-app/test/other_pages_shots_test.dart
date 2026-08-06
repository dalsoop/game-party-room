import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/host_controller.dart';
import 'package:game_party_room_app/pages/liar_page.dart';
import 'package:game_party_room_app/pages/poll_page.dart';
import 'package:party_room_server/party_room_server.dart';
import 'package:party_room_server/testing.dart';

/// 라이어·투표 진행 화면을 그림으로 뽑는다 (마피아와 같은 이유).
///
/// ```
/// PARTY_SHOTS=1 flutter test test/other_pages_shots_test.dart
/// ```
void main() {
  final wanted = Platform.environment['PARTY_SHOTS'] == '1';

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget Function(HostController) page,
    void Function(Room) setup, {
    Size size = const Size(1100, 700),
  }) async {
    final ctrl = HostController();
    addTearDown(ctrl.dispose);
    final room = Room();
    ctrl.room = room;
    for (final n in ['민서', '태윤', '지우', '서준', '하준']) {
      room.seat(n)!.link = RecordingLink();
    }
    setup(room);

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(debugShowCheckedModeBanner: false, home: page(ctrl)),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('/tmp/page_$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('라이어 — 지목 투표 중', skip: !wanted, (tester) async {
    await shoot(tester, 'liar', (c) => LiarPage(ctrl: c), (room) {
      final g = LiarGame();
      room.startGame(g);
      g.beginVote(room.gameCtx);
    });
  });

  testWidgets('투표 — 진행 중', skip: !wanted, (tester) async {
    await shoot(tester, 'poll', (c) => PollPage(ctrl: c), (room) {
      room.startGame(
        PollGame()..setup(question: '오늘 뭐 먹을까', options: ['치킨', '피자', '족발']),
      );
    });
  });
}
