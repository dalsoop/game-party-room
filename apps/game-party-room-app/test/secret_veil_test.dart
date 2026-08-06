import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/pages/secret_veil.dart';

/// 비밀을 가리는 막.
///
/// 호스트 화면은 참가자에게 노출되기 쉽다 — 라이어 게임은 한때 상태줄에
/// 라이어와 제시어를 그대로 띄우고 "보여주지 마세요" 경고문 하나로 버텼다.
/// 그래서 이 막은 **꺼져 있지 않은 한 반드시 덮여 있어야** 한다.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool enabled,
    String label = '꾹 눌러 확인',
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            height: 120,
            child: SecretVeil(
              enabled: enabled,
              label: label,
              child: const Text('마피아'),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('꺼 두면 그냥 보인다', (tester) async {
    await pump(tester, enabled: false);
    expect(find.text('마피아'), findsOneWidget);
    expect(find.text('꾹 눌러 확인'), findsNothing);
  });

  testWidgets('켜 두면 안내가 덮는다', (tester) async {
    await pump(tester, enabled: true);
    expect(find.text('꾹 눌러 확인'), findsOneWidget);
  });

  testWidgets('누르는 동안만 열리고 떼면 다시 덮인다', (tester) async {
    await pump(tester, enabled: true);
    final veil = find.text('꾹 눌러 확인');

    final gesture = await tester.startGesture(tester.getCenter(veil));
    await tester.pump();
    // 막은 투명해질 뿐 자리에 남는다 — 보이는지는 투명도로 판정한다.
    double opacity() =>
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
    expect(opacity(), 0, reason: '눌렀는데 안 열렸다');

    await gesture.up();
    await tester.pump();
    expect(opacity(), 1, reason: '손을 뗐는데 계속 열려 있다');
  });

  testWidgets('안내를 안 적으면 줄무늬만 남는다', (tester) async {
    // 안내가 이미 위에 한 번 적혀 있는 자리(명단 카드)를 위한 것이다.
    // 좁다고 문구를 잘라 쓰면("꾹") 조각난 말이 되어 더 나쁘다 —
    // 그 길로 되돌아가지 못하게 막는다.
    await pump(tester, enabled: true, label: '');
    expect(find.byType(Text), findsOneWidget, reason: '가린 자리에 글자가 생겼다');
    expect(find.text('마피아'), findsOneWidget, reason: '남은 하나는 가려진 본문이어야 한다');

    // 눈에 안 보여도 스크린리더에는 안내가 간다.
    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(RegExp('꾹 눌러 확인')),
      findsOneWidget,
      reason: '글자를 지우면서 스크린리더 안내까지 지우면 안 된다',
    );
    handle.dispose();
  });
}
