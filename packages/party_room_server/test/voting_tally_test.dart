import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';

/// 표를 세는 규칙 — **누가 죽는지를 정하는 자리**.
///
/// 마피아와 라이어가 같은 집계를 쓰되 동표 처리를 달리한다(마피아는 기본
/// 무처형, 라이어는 최다득표 공개). 그 갈림이 여기 [VoteTally.isTie] 하나에
/// 달려 있는데 직접 검증이 없었다 — 게임이 뒤집히는 자리라 못 박는다.
void main() {
  VoteBox boxOf(Map<String, String> votes) {
    final b = VoteBox();
    votes.forEach(b.cast);
    return b;
  }

  group('기본 집계', () {
    test('아무도 안 냈으면 뽑을 사람이 없다', () {
      final t = VoteBox().tally();
      expect(t.top, isNull, reason: '표가 없는데 누굴 처형하면 안 된다');
      expect(t.isTie, isFalse);
      expect(t.counts, isEmpty);
    });

    test('한 명에게 몰리면 그 사람이다', () {
      final t = boxOf({'가': 'X', '나': 'X', '다': 'Y'}).tally();
      expect(t.top, 'X');
      expect(t.isTie, isFalse);
      expect(t.counts, {'X': 2, 'Y': 1});
    });

    test('같은 사람이 다시 내면 마지막 것만 센다', () {
      // 폰에서 지목을 바꿀 수 있다 — 두 번 세면 한 사람이 두 표가 된다.
      final b = boxOf({'가': 'X'})..cast('가', 'Y');
      final t = b.tally();
      expect(t.counts, {'Y': 1});
      expect(b.length, 1);
    });
  });

  group('동표', () {
    test('최다가 둘이면 동표라고 알린다', () {
      final t = boxOf({'가': 'X', '나': 'Y'}).tally();
      expect(t.isTie, isTrue, reason: '이걸 놓치면 마피아가 동표에도 처형한다');
      expect(t.counts, {'X': 1, 'Y': 1});
    });

    test('동표여도 top 은 정해 준다 — 라이어는 결과를 반드시 공개한다', () {
      final t = boxOf({'가': 'X', '나': 'Y'}).tally();
      expect(t.top, isNotNull);
    });

    test('아래쪽이 동점인 것은 동표가 아니다', () {
      // 1등이 하나면 2·3등이 같아도 처형은 갈린다.
      final t = boxOf({'가': 'X', '나': 'X', '다': 'Y', '라': 'Z'}).tally();
      expect(t.top, 'X');
      expect(t.isTie, isFalse);
    });
  });

  group('같은 표에는 같은 결과', () {
    test('넣은 순서가 달라도 결과가 같다', () {
      // 예전에는 Map 순회 순서에 따라 동점자 중 누가 뽑힐지 달라졌다.
      // 같은 표로 두 번 돌렸을 때 다른 사람이 죽으면 아무도 납득 못 한다.
      final a = boxOf({'가': 'Y', '나': 'X'}).tally();
      final b = boxOf({'나': 'X', '가': 'Y'}).tally();
      expect(a.top, b.top);
      expect(a.top, 'X', reason: '동점이면 대상 토큰 오름차순으로 고정한다');
    });

    test('여러 번 세도 같은 답이다', () {
      final box = boxOf({'가': 'B', '나': 'A', '다': 'C'});
      final answers = {for (var i = 0; i < 20; i++) box.tally().top};
      expect(answers, hasLength(1), reason: '셀 때마다 답이 바뀌면 판정이 아니다');
    });
  });

  group('표 무게 (정치인)', () {
    test('무게를 주면 그만큼 세어 판을 뒤집는다', () {
      // 정치인은 2표다 — 1:1 이 2:1 이 되어 동표가 풀린다.
      final box = boxOf({'정치인': 'X', '시민': 'Y'});
      final plain = box.tally();
      expect(plain.isTie, isTrue);

      final weighted = box.tally(weightOf: (v) => v == '정치인' ? 2 : 1);
      expect(weighted.counts, {'X': 2, 'Y': 1});
      expect(weighted.top, 'X');
      expect(weighted.isTie, isFalse, reason: '무게로 갈렸는데 동표로 남으면 무처형이 된다');
    });

    test('무게를 안 주면 모두 1표다', () {
      final t = boxOf({'가': 'X', '나': 'X'}).tally();
      expect(t.counts['X'], 2);
    });
  });

  group('저장·복구', () {
    test('내던 표가 재시작을 넘어간다', () {
      // 투표 중에 앱이 꺼지면 처음부터 다시 시켜야 하는데, 그러면 이미 낸
      // 사람도 다시 내야 한다 — 누가 냈는지까지 살아야 이어서 마감한다.
      final a = boxOf({'가': 'X', '나': 'Y'});
      final b = VoteBox()..restore(a.toJson());
      expect(b.votes, a.votes);
      expect(b.tally().counts, a.tally().counts);
    });

    test('복구할 것이 없으면 빈 채로 시작한다', () {
      final b = VoteBox()..restore(null);
      expect(b.isEmpty, isTrue);
    });
  });
}
