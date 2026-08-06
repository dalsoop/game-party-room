import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';

void main() {
  group('VoteBox', () {
    test('표가 없으면 top 은 null 이고 동표도 아니다', () {
      expect(VoteBox().tally().top, isNull);
      expect(VoteBox().tally().isTie, isFalse);
    });

    test('최다 득표를 고른다', () {
      final box = VoteBox()
        ..cast('a', 'x')
        ..cast('b', 'x')
        ..cast('c', 'y');
      final t = box.tally();
      expect(t.top, 'x');
      expect(t.isTie, isFalse);
      expect(t.counts, {'x': 2, 'y': 1});
    });

    test('동표를 알린다', () {
      final box = VoteBox()
        ..cast('a', 'x')
        ..cast('b', 'y');
      expect(box.tally().isTie, isTrue);
    });

    test('표 무게를 반영한다 (정치인 2표)', () {
      final box = VoteBox()
        ..cast('politician', 'x')
        ..cast('a', 'y')
        ..cast('b', 'y');
      // 무게 없으면 y 승, politician 2표면 동표.
      expect(box.tally().top, 'y');
      final weighted = box.tally(weightOf: (v) => v == 'politician' ? 2 : 1);
      expect(weighted.isTie, isTrue);
      expect(weighted.counts, {'x': 2, 'y': 2});
    });

    test('같은 표에서는 항상 같은 결과가 나온다', () {
      // 예전 구현은 Map 순회 순서에 기대 동표에서 결과가 흔들렸다.
      String? first;
      for (var i = 0; i < 20; i++) {
        final box = VoteBox()
          ..cast('a', 'zzz')
          ..cast('b', 'aaa');
        first ??= box.tally().top;
        expect(box.tally().top, first);
      }
    });

    test('한 사람의 표는 마지막 것만 센다', () {
      final box = VoteBox()
        ..cast('a', 'x')
        ..cast('a', 'y');
      expect(box.tally().counts, {'y': 1});
      expect(box.length, 1);
    });

    test('저장·복구를 왕복한다', () {
      final box = VoteBox()
        ..cast('a', 'x')
        ..cast('b', 'y');
      final restored = VoteBox()..restore(box.toJson());
      expect(restored.votes, box.votes);
    });
  });
}
