import 'package:flutter/material.dart';
import 'package:party_room_server/party_room_server.dart';

/// 판을 그리는 종목이 함께 쓰는 색 — 구슬 룰렛과 사다리타기.
///
/// 예전에는 이것이 `MarbleTheme` 이라는 이름으로 구슬 화면 안에 있었고,
/// 사다리 화면이 거기를 참조했다. **사다리가 구슬 테마에 의존하는 모양**이
/// 되어, 구슬 화면을 건드릴 때마다 사다리가 딸려 왔다.
///
/// 게다가 그 안의 절반은 [HostHud] 색을 그대로 베낀 별칭이었다 — 바탕·글자
/// 색의 정본은 하나여야 한다. 그래서 여기는 **판 위에 놓이는 것들**만 갖고,
/// 나머지는 [HostHud] 를 직접 쓴다.
abstract final class BoardPalette {
  /// 벽·기둥처럼 구슬이 부딪히는 것.
  static const wall = Color(0xFFE8EEFF);

  /// 핀밭.
  static const peg = Color(0xFFFFD34D);

  /// 바람개비.
  static const spinner = Color(0xFF41E0E8);

  /// 도착선.
  static const goal = Color(0xFF2ED573);

  /// 참가자 n번째의 색. 폰 화면과 같은 팔레트를 쓴다 — 내 구슬이 어느
  /// 것인지 두 화면에서 같은 색이어야 알아본다.
  static Color of(int index) {
    final hex = MarbleGame.palette[index % MarbleGame.palette.length];
    return Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
  }
}
