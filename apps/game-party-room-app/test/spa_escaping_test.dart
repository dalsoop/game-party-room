import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 참가자 화면이 남의 글자를 그릴 때 **HTML 로 해석하지 않는다.**
///
/// 닉네임·채팅·파일 이름은 전부 다른 참가자가 정한 문자열이다. 그걸
/// `innerHTML` 에 그대로 꽂으면, 한 사람이 이름을 `<img onerror=…>` 로
/// 지어 방에 들어오는 것만으로 **모두의 폰에서 스크립트가 돈다.** 파티용
/// 앱이라 서로 아는 사이겠지만, 링크는 단톡방을 타고 어디로든 간다.
///
/// 지금은 열두 자리 모두 `esc()`·`nameHtml()` 을 지난다. 문제는 SPA 에
/// 린트가 없다는 것이다 — 다음에 누가 한 줄을 그냥 꽂아도 아무도 안
/// 알려준다. 그래서 원본을 훑어 **막지 않은 보간**을 찾는다.
void main() {
  final root = Directory.current.path;

  /// 이 껍데기를 지나면 안전하다고 본다.
  ///
  /// - `esc(…)` 가 정본 이스케이퍼
  /// - `nameHtml`·`targetBtn`·`choiceBtn` 은 그 안에서 `esc` 를 쓴다
  /// - `Icon.svg`·`Endpoints.*` 는 우리가 만든 값이지 남의 글자가 아니다
  final safeWrapper = RegExp(
    r'^\s*(esc\(|Icon\.|Endpoints\.|nameHtml\(|targetBtn\(|choiceBtn\(|svg\(|fmtSize\(|OPT_MARK|MAFIA_TEAM|ABILITY\[)',
  );

  /// 숫자·불리언에서 온 값. HTML 이 될 수 없다.
  final harmless = RegExp(
    r'^\s*[\w.\[\]]*(rank|size|count|total|column|width|left|top|i|c|n)\s*$',
  );

  /// 삼항이 **리터럴만** 고르는 경우 — `cond ? '<b>' : ''` 처럼.
  /// 안쪽에 변수가 섞이면 안전하지 않으므로 그때는 걸러지지 않는다.
  bool literalTernary(String e) {
    if (!e.contains('?')) return false;
    final branches = e.split('?').last;
    final vars = RegExp(r"(?<!')\b[a-z_]\w*\.\w+").allMatches(branches);
    for (final v in vars) {
      if (!v.group(0)!.contains('esc(')) {
        // 분기에 변수 접근이 있는데 esc 가 없으면 사람이 봐야 한다.
        return branches.contains('esc(');
      }
    }
    return true;
  }

  List<File> spaSources() => [
    File('$root/assets/web/index.html'),
    ...Directory('$root/assets/web/js')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.js')),
  ];

  /// **HTML 을 만드는 템플릿 리터럴** 안의 `${…}` 를 전부 캔다.
  ///
  /// 처음에는 `innerHTML = …;` 를 정규식으로 쫓았는데, 그 대입이 여러 줄이고
  /// 안에 `;` 가 섞여 있어서 첫 세미콜론에서 끊겼다 — 정작 템플릿을 못 보고
  /// **아무것도 못 잡는 테스트**가 됐다(esc 를 빼도 통과했다). 태그를 여는
  /// 템플릿을 직접 찾는 편이 훨씬 튼튼하다.
  List<({String file, int line, String expr})> interpolations() {
    final out = <({String file, int line, String expr})>[];
    // 백틱으로 열고 닫는 템플릿 리터럴 하나.
    final template = RegExp(r'`([^`]*)`', dotAll: true);
    final opensTag = RegExp(r'<(div|li|span|button|a|b|img|ul|ol|p)\b');
    for (final f in spaSources()) {
      final src = f.readAsStringSync();
      for (final t in template.allMatches(src)) {
        final body = t.group(1)!;
        if (!opensTag.hasMatch(body)) continue; // HTML 을 안 만드는 템플릿
        final line = '\n'.allMatches(src.substring(0, t.start)).length + 1;
        for (final e in RegExp(r'\$\{([^{}]*)\}').allMatches(body)) {
          out.add((
            file: f.uri.pathSegments.last,
            line: line,
            expr: e.group(1)!.trim(),
          ));
        }
      }
    }
    return out;
  }

  /// 눈으로 확인하고 남긴 예외 — **남의 글자가 아닌 것만** 여기 온다.
  ///
  /// 새 보간이 생기면 이 목록에 없으므로 테스트가 터진다. 그때 실제로
  /// 남의 글자인지 보고, 아니라면 근거와 함께 여기 더한다.
  const reviewed = {
    // 서버가 센 표 수(정수). PollGame 이 만든다.
    'msg.counts[i]',
    // 막대 너비 — 위 정수로 계산한 백분율.
    '(msg.counts[i] / max) * 100',
    // 아래는 **바로 앞줄에서 이미 esc 를 지난 지역변수**다. 원본을 열어
    // 하나씩 확인했다 — 여기 이름만 보고 넘기지 말고, 그 줄을 다시 볼 것.
    'tag', // index.html nameHtml: `<span class="ptag">${esc(p.tag)}</span>`
    'who', // chat.js renderLog: esc(speakerName) 또는 nameHtml 결과
    // 아래는 우리 코드가 고르는 CSS 클래스·이벤트 이름이다. 남의 글자가 아니다.
    'cls',
    'type',
    'team',
  };

  test('innerHTML 에 남의 글자를 막지 않고 꽂는 곳이 없다', () {
    final risky = [
      for (final i in interpolations())
        if (!safeWrapper.hasMatch(i.expr) &&
            !harmless.hasMatch(i.expr) &&
            !literalTernary(i.expr) &&
            !reviewed.contains(i.expr) &&
            !RegExp(r'^\s*\d').hasMatch(i.expr))
          i,
    ];
    expect(
      risky,
      isEmpty,
      reason:
          '막지 않은 보간: ${risky.map((r) => "${r.file}:${r.line} \${${r.expr}}").join(", ")}\n'
          'esc() 로 감싸거나, 남의 글자가 아니라면 이 테스트의 안전 목록에 근거와 함께 더하세요.',
    );
  });

  test('이스케이퍼가 다섯 글자를 모두 막는다', () {
    // `<`·`>` 만 막고 따옴표를 놔두면 속성 안에서 빠져나간다
    // (`<button data-tag="${…}">` 자리가 실제로 있다).
    //
    // 정의 전체에서 글자를 찾으면 안 된다 — 치환표(`'&':'&amp;'`)에 그 글자가
    // 그대로 들어 있어서, 문자 클래스에서 빼도 검사가 통과한다(실제로 그렇게
    // 헛돌았다). **무엇을 잡는지**를 정하는 문자 클래스만 본다.
    final html = File('$root/assets/web/index.html').readAsStringSync();
    final klass = RegExp(
      r'const esc\s*=[^\n]*?/\[([^\]]*)\]/g',
    ).firstMatch(html)?.group(1);
    expect(klass, isNotNull, reason: '이스케이퍼의 문자 클래스를 못 찾았다');
    for (final ch in ['&', '<', '>', '"', "'"]) {
      expect(
        klass,
        contains(ch),
        reason: '$ch 를 안 막으면 속성이나 태그를 빠져나갈 수 있다 (클래스: $klass)',
      );
    }
  });

  test('참가자가 넣는 값이 HTML 로 들어갈 때는 반드시 막는다', () {
    // 닉네임·태그·채팅·파일 이름 — 남이 정하는 네 가지.
    //
    // `textContent` 로 넣는 자리는 브라우저가 글자로만 다루므로 상관없다
    // (마피아 경찰 결과가 그렇다). **HTML 이 되는 자리**만 본다.
    for (final field in ['nickname', 'm.text', 'f.name', '.tag']) {
      for (final i in interpolations()) {
        if (!i.expr.contains(field)) continue;
        expect(
          i.expr,
          contains('esc('),
          reason: '${i.file}:${i.line} 에서 $field 를 안 막고 HTML 에 넣었다',
        );
      }
    }
  });
}
