/// 게임이 스스로 선언하는 규칙 항목.
///
/// 설정 화면이 종목을 알지 못해도 그릴 수 있게 한다 — 새 게임을 넣을 때
/// 설정 화면을 고치지 않는 것이 목적이다(로비 배너를 카탈로그로 옮긴 것과 같은 이유).
sealed class GameRuleSpec {
  const GameRuleSpec({required this.key, required this.label, this.help});

  /// 저장 키. 종목 안에서 유일해야 한다.
  final String key;
  final String label;
  final String? help;

  /// 저장된 값이 없을 때 쓰는 값.
  Object get defaultValue;
}

/// 켜고 끄는 규칙.
class ToggleRule extends GameRuleSpec {
  const ToggleRule({
    required super.key,
    required super.label,
    required this.initial,
    super.help,
  });

  final bool initial;

  @override
  Object get defaultValue => initial;
}

/// 몇 개 중 하나를 고르는 규칙.
class ChoiceRule extends GameRuleSpec {
  const ChoiceRule({
    required super.key,
    required super.label,
    required this.options,
    required this.initial,
    super.help,
  });

  /// 저장 값 → 사람이 읽는 이름.
  final Map<String, String> options;
  final String initial;

  @override
  Object get defaultValue => initial;
}

/// 여러 개를 켜는 규칙(카테고리 고르기 등). 최소 [minSelected] 개는 남겨야 한다.
class MultiChoiceRule extends GameRuleSpec {
  const MultiChoiceRule({
    required super.key,
    required super.label,
    required this.options,
    required this.initial,
    this.minSelected = 1,
    super.help,
  });

  final Map<String, String> options;
  final List<String> initial;
  final int minSelected;

  @override
  Object get defaultValue => initial;
}
