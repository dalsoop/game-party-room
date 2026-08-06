import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/pages/host_hud.dart';

/// 호스트 HUD 위젯의 계약.
///
/// 이 어법의 모든 조각이 `ClipPath` 로 모서리를 잘라 만들어진다. 클리핑은
/// 히트테스트에도 영향을 주기 때문에, "보이는데 안 눌리는" 버튼이 나오기
/// 쉽다 — 진행 버튼이 안 눌리면 사회자가 게임을 못 넘긴다.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  group('HudButton', () {
    testWidgets('가운데를 누르면 콜백이 온다', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: HudButton(label: '밤 시작', onPressed: () => taps++),
          ),
        ),
      );
      await tester.tap(find.text('밤 시작'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('잘린 모서리 근처를 눌러도 콜백이 온다', (tester) async {
      // 노치(13px) 안쪽은 그려지지 않지만, 사용자는 버튼 사각형을 보고 누른다.
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: HudButton(label: '투표 시작', onPressed: () => taps++),
          ),
        ),
      );
      final box = tester.getRect(find.byType(HudButton));
      await tester.tapAt(Offset(box.right - 6, box.bottom - 6));
      await tester.pump();
      expect(taps, 1, reason: '오른아래 잘린 모서리에서 탭이 새면 안 된다');
    });

    testWidgets('onPressed 가 null 이면 눌리지 않고 흐리게 그려진다', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 400,
            child: HudButton(label: '대기', onPressed: null),
          ),
        ),
      );
      await tester.tap(find.text('대기'));
      await tester.pump();
      final text = tester.widget<Text>(find.text('대기'));
      expect(text.style?.color, HostHud.dim);
    });
  });

  group('HudMcLine', () {
    testWidgets('대사가 비면 자리를 차지하지 않는다', (tester) async {
      await tester.pumpWidget(wrap(const HudMcLine(line: '')));
      expect(find.byType(Icon), findsNothing);
      expect(tester.getSize(find.byType(HudMcLine)), Size.zero);
    });

    testWidgets('대사가 있으면 그대로 보여준다', (tester) async {
      await tester.pumpWidget(wrap(const HudMcLine(line: '밤이 내려앉았습니다')));
      expect(find.text('밤이 내려앉았습니다'), findsOneWidget);
    });
  });

  group('HudCommandBar', () {
    testWidgets('제목·부제·상태를 함께 보여주고 종료를 부른다', (tester) async {
      var ended = 0;
      await tester.pumpWidget(
        wrap(
          HudCommandBar(
            title: '마피아',
            subtitle: '밤',
            status: '2일차',
            onEnd: () => ended++,
          ),
        ),
      );
      expect(find.text('마피아'), findsOneWidget);
      expect(find.text('밤'), findsOneWidget);
      expect(find.text('2일차'), findsOneWidget);
      await tester.tap(find.text('게임 종료'));
      await tester.pump();
      expect(ended, 1);
    });
  });
}
