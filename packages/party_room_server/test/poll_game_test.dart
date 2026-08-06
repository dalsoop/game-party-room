import 'package:party_room_server/party_room_server.dart';
import 'package:party_room_server/testing.dart';
import 'package:test/test.dart';

/// 익명 투표 — 다섯 종목 중 **유일하게 테스트가 없던 게임**.
///
/// 규칙은 단순하지만 지켜야 할 것이 셋이다: 누가 뭘 골랐는지는 **끝까지
/// 비밀**이고(그래서 익명 투표다), 전원이 고르면 저절로 마감되고, 마감한
/// 뒤에는 표가 안 바뀐다.
void main() {
  /// 판을 세우고, 각자 폰이 받은 것과 호스트가 받은 이벤트를 모아 준다.
  ({
    PollGame game,
    GameContext ctx,
    Map<String, List<Map<String, dynamic>>> inbox,
    List<Map<String, dynamic>> broadcasts,
    List<(String, Map<String, dynamic>)> events,
    List<Player> players,
  })
  table({int people = 3}) {
    // 접속 판정은 채널 유무다 — 안 물리면 "아무도 없음" 이 되어
    // 전원 투표 자동 마감을 시험할 수 없다.
    final players = [
      for (var i = 0; i < people; i++)
        Player(sessionToken: 'S$i', nickname: '손님$i', tag: 'T$i')
          ..link = RecordingLink(),
    ];
    final inbox = <String, List<Map<String, dynamic>>>{
      for (final p in players) p.sessionToken: [],
    };
    final broadcasts = <Map<String, dynamic>>[];
    final events = <(String, Map<String, dynamic>)>[];

    final ctx = GameContext(
      // 접속 판정은 채널 유무라, 테스트에서는 앞의 [live] 명만 접속으로 친다.
      players: () => players,
      broadcast: (m) {
        broadcasts.add(m);
        for (final l in inbox.values) {
          l.add(m);
        }
      },
      sendTo: (s, m) => inbox[s]?.add(m),
      onGameEvent: (e, d) => events.add((e, d)),
    );
    final game = PollGame()
      ..setup(question: '오늘 뭐 먹지', options: ['치킨', '피자', '족발']);
    return (
      game: game,
      ctx: ctx,
      inbox: inbox,
      broadcasts: broadcasts,
      events: events,
      players: players,
    );
  }

  test('시작하면 질문과 선택지가 전원에게 간다', () {
    final t = table();
    t.game.start(t.ctx);
    final scene = t.broadcasts.singleWhere((m) => m['scene'] == 'poll');
    expect(scene['question'], '오늘 뭐 먹지');
    expect(scene['options'], ['치킨', '피자', '족발']);
  });

  test('고르면 자기에게만 확인이 온다 — 남에게는 안 간다', () {
    // 익명 투표의 존재 이유다. 누가 뭘 골랐는지가 새면 게임이 아니다.
    final t = table();
    t.game.start(t.ctx);
    t.game.onMessage(t.ctx, t.players[0], {'type': 'poll_vote', 'option': 1});

    expect(
      t.inbox['S0']!.any((m) => m['type'] == 'poll_ack' && m['option'] == 1),
      isTrue,
    );
    for (final other in ['S1', 'S2']) {
      expect(
        t.inbox[other]!.any((m) => m['type'] == 'poll_ack'),
        isFalse,
        reason: '$other 가 남의 선택 확인을 받았다',
      );
    }
  });

  test('진행률은 숫자만 알린다 — 누가 골랐는지는 안 알린다', () {
    final t = table();
    t.game.start(t.ctx);
    t.game.onMessage(t.ctx, t.players[0], {'type': 'poll_vote', 'option': 0});

    final prog = t.events.lastWhere((e) => e.$1 == 'poll_progress').$2;
    expect(prog['voted'], 1);
    expect(prog['players'], 3);
    expect(
      prog.values.map((v) => '$v').join(),
      isNot(contains('S0')),
      reason: '진행률에 누가 냈는지가 실리면 익명이 아니다',
    );
  });

  test('전원이 고르면 저절로 마감된다', () {
    final t = table();
    t.game.start(t.ctx);
    for (final p in t.players) {
      t.game.onMessage(t.ctx, p, {'type': 'poll_vote', 'option': 0});
    }
    expect(t.game.closed, isTrue, reason: '호스트가 마감을 눌러야만 끝나면 흐름이 끊긴다');
    final result = t.broadcasts.lastWhere((m) => m['type'] == 'poll_result');
    expect(result['counts'], [3, 0, 0]);
    expect(result['total'], 3);
  });

  test('마감한 뒤에는 표가 안 바뀐다', () {
    final t = table();
    t.game.start(t.ctx);
    for (final p in t.players) {
      t.game.onMessage(t.ctx, p, {'type': 'poll_vote', 'option': 0});
    }
    final before = t.broadcasts.where((m) => m['type'] == 'poll_result').length;

    t.game.onMessage(t.ctx, t.players[0], {'type': 'poll_vote', 'option': 2});
    expect(
      t.broadcasts.where((m) => m['type'] == 'poll_result').length,
      before,
      reason: '결과를 본 뒤 바꿔 낼 수 있으면 발표가 뒤집힌다',
    );
  });

  test('마음을 바꾸면 마지막 것만 센다', () {
    final t = table();
    t.game.start(t.ctx);
    t.game.onMessage(t.ctx, t.players[0], {'type': 'poll_vote', 'option': 0});
    t.game.onMessage(t.ctx, t.players[0], {'type': 'poll_vote', 'option': 2});
    t.game.onMessage(t.ctx, t.players[1], {'type': 'poll_vote', 'option': 2});
    t.game.onMessage(t.ctx, t.players[2], {'type': 'poll_vote', 'option': 2});

    final result = t.broadcasts.lastWhere((m) => m['type'] == 'poll_result');
    expect(result['counts'], [0, 0, 3]);
  });

  test('없는 선택지는 무시한다', () {
    // 폰이 옛 화면을 들고 있거나 누가 손으로 프레임을 만들 수 있다.
    final t = table();
    t.game.start(t.ctx);
    for (final bad in [-1, 3, 99, 'ㅋ', null]) {
      t.game.onMessage(t.ctx, t.players[0], {
        'type': 'poll_vote',
        'option': bad,
      });
    }
    expect(t.game.closed, isFalse);
    expect(t.inbox['S0']!.any((m) => m['type'] == 'poll_ack'), isFalse);
  });

  test('재접속하면 화면과 내가 낸 표가 돌아온다', () {
    final t = table();
    t.game.start(t.ctx);
    t.game.onMessage(t.ctx, t.players[1], {'type': 'poll_vote', 'option': 2});
    t.inbox['S1']!.clear();

    t.game.onReconnect(t.ctx, t.players[1]);
    expect(t.inbox['S1']!.any((m) => m['scene'] == 'poll'), isTrue);
    expect(
      t.inbox['S1']!.any((m) => m['type'] == 'poll_ack' && m['option'] == 2),
      isTrue,
      reason: '낸 표를 못 보면 또 내려다가 이미 냈다는 것도 모른다',
    );
  });

  test('안 낸 사람이 재접속하면 표는 안 온다', () {
    final t = table();
    t.game.start(t.ctx);
    t.inbox['S2']!.clear();
    t.game.onReconnect(t.ctx, t.players[2]);
    expect(t.inbox['S2']!.any((m) => m['type'] == 'poll_ack'), isFalse);
  });

  test('진행 중이던 투표가 재시작을 넘어간다', () {
    final t = table();
    t.game.start(t.ctx);
    t.game.onMessage(t.ctx, t.players[0], {'type': 'poll_vote', 'option': 1});

    final revived = PollGame()..restore(t.ctx, t.game.toJson());
    expect(revived.question, '오늘 뭐 먹지');
    expect(revived.options, ['치킨', '피자', '족발']);
    expect(revived.closed, isFalse);

    // 남은 두 명이 마저 내면 그대로 마감된다 — 낸 표가 살아 있어야 한다.
    revived.onMessage(t.ctx, t.players[1], {'type': 'poll_vote', 'option': 1});
    revived.onMessage(t.ctx, t.players[2], {'type': 'poll_vote', 'option': 1});
    expect(revived.closed, isTrue, reason: '복구된 표를 안 세면 전원 투표를 못 알아챈다');
  });

  test('칸을 열지 않는다 — 즉석 투표는 물어보고 끝이다', () {
    expect(PollGame().ownsSection, isFalse, reason: '판마다 빈 칸이 열리면 단톡 탭만 채운다');
  });
}
