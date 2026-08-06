import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 코드가 부르는 그림이 실제로 있는가.
///
/// 없는 그림은 **조용히 사라진다**. 홈 화면의 앱 마크는 `errorBuilder` 로
/// 빈 자리를 돌려주게 돼 있어서, `assets/img/appicon.png` 가 없는 채로도
/// 아무 오류 없이 그냥 아이콘만 안 보였다 — 스크린샷을 찍어 보기 전까지
/// 아무도 몰랐다. 참가자 화면 쪽은 더 나빠서, 깨진 그림이 폰에 그대로 뜬다.
///
/// 그래서 이름을 눈으로 맞추지 말고 여기서 대조한다.
void main() {
  final root = Directory.current.path;

  /// 파일들에서 `<prefix>/<이름>.jpg|png` 꼴을 전부 긁는다.
  Set<String> referenced(Iterable<File> files, String prefix) {
    final pat = RegExp('$prefix/([a-z_0-9]+\\.(?:jpg|png))');
    return {
      for (final f in files)
        for (final m in pat.allMatches(f.readAsStringSync())) m.group(1)!,
    };
  }

  Set<String> filesIn(String dir) {
    final d = Directory('$root/$dir');
    if (!d.existsSync()) return {};
    return {
      for (final e in d.listSync())
        if (e is File) e.uri.pathSegments.last,
    };
  }

  Iterable<File> dartSources() => Directory('$root/lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  Iterable<File> webSources() => [
    File('$root/assets/web/index.html'),
    ...Directory('$root/assets/web/js')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.js')),
  ];

  test('맥 앱이 부르는 그림이 전부 있다', () {
    final need = referenced(dartSources(), 'assets/img');
    final have = filesIn('assets/img');
    expect(
      need.difference(have),
      isEmpty,
      reason: '없는 그림은 errorBuilder 뒤에 숨어 아무도 모른다',
    );
  });

  test('참가자 화면이 부르는 그림이 전부 있다', () {
    // 폰에서는 깨진 그림 아이콘이 그대로 보인다 — 파티 중에 제일 눈에 띈다.
    final need = referenced(webSources(), '/img');
    final have = filesIn('assets/web/img');
    expect(need.difference(have), isEmpty);
  });

  test('역할 그림이 서버의 역할과 하나씩 맞는다', () {
    // 역할이 하나 늘었는데 그림을 안 넣으면, 그 역할을 받은 사람의 폰에만
    // 깨진 그림이 뜬다 — 다섯 판에 한 번 나오는 식이라 재현도 어렵다.
    final js = File('$root/assets/web/js/games/mafia.js').readAsStringSync();
    final mapped = RegExp(r"(\w+): *'(role_[a-z]+\.png)'").allMatches(js);
    expect(mapped, isNotEmpty, reason: '역할→그림 표를 못 찾았다');
    final have = filesIn('assets/web/img');
    for (final m in mapped) {
      expect(have, contains(m.group(2)), reason: '${m.group(1)} 역할의 그림이 없다');
    }
  });
}
