import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/pages/help_page.dart';

/// 도움말은 "이미 뭔가 안 되는 중인 사람"이 여는 화면이라, **막히는 지점의 답이
/// 실제로 적혀 있는지**가 유일하게 중요한 검사다. 문구는 바뀌어도 되지만
/// 아래 답들이 사라지면 도움말은 있으나 마나다.
void main() {
  /// ListView 는 화면에 걸치는 것만 만든다 — 기본 800×600 으로 띄우면 아래
  /// 절반이 존재하지 않아 "문구가 없다" 는 거짓 실패가 난다. 전체를 한 번에
  /// 세우려고 세로를 길게 잡는다.
  Future<void> pump(WidgetTester t, {Size size = const Size(900, 2600)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(const MaterialApp(home: HelpPage()));
    await t.pumpAndSettle();
  }

  testWidgets('막히는 지점 네 갈래가 모두 있다', (t) async {
    await pump(t);
    for (final section in const [
      '시작하기',
      '참가자가 접속을 못 할 때',
      '진행 중에',
      '방을 여러 개 쓰기',
      '더 재미있게',
    ]) {
      expect(find.text(section), findsOneWidget, reason: section);
    }
  });

  testWidgets('접속 실패의 실제 원인들을 짚는다', (t) async {
    await pump(t);
    // 같은 Wi-Fi → AP 격리 → 인터넷 개방. 사용성 테스트에서 걸린 순서 그대로.
    expect(find.textContaining('같은 Wi-Fi'), findsWidgets);
    expect(find.textContaining('AP 격리'), findsOneWidget);
    // 인터넷 개방은 접속 실패의 답이자 암호화의 답이라 두 번 나온다.
    expect(find.textContaining('인터넷으로 열기'), findsWidgets);
  });

  testWidgets('평문 구간과 방 수명을 지금 규칙대로 밝힌다', (t) async {
    await pump(t);
    // 팔 물건이면 안 되는 것도 적어야 한다 — 같은 Wi-Fi 안은 암호화가 없다.
    expect(find.textContaining('암호화되지 않습니다'), findsOneWidget);
    // 방 수명 규칙이 바뀌었다 — 도움말이 옛 규칙을 말하면 거짓말이 된다.
    expect(find.textContaining('12시간'), findsNothing);
    expect(find.textContaining('지울 때까지 남습니다'), findsOneWidget);
  });

  testWidgets('호스트 화면 노출 경고가 있다', (t) async {
    await pump(t);
    // 역할표·제시어가 뜬 화면을 그대로 TV 에 띄우면 게임이 끝난다.
    expect(find.textContaining('호스트 화면'), findsOneWidget);
    expect(find.textContaining('꾹 누르는 동안만'), findsOneWidget);
  });

  testWidgets('좁은 창에서도 오버플로하지 않는다', (t) async {
    await pump(t, size: const Size(560, 2600));
    expect(t.takeException(), isNull);
  });
}
