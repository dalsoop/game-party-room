import 'dart:convert';

import 'package:party_room_server/party_room_server.dart';
import 'package:party_room_server/testing.dart';
import 'package:test/test.dart';

/// 앱과 헤드리스가 함께 쓰는 게임 명령 계약.
void main() {
  ({Room room, RoomGameControl control, GameControlCommands commands}) rig(
    int people,
  ) {
    final room = Room();
    for (var i = 0; i < people; i++) {
      room.seat('손님$i')!.link = RecordingLink();
    }
    final control = RoomGameControl(room: room);
    addTearDown(control.dispose);
    return (
      room: room,
      control: control,
      commands: GameControlCommands(control),
    );
  }

  test('마피아 페이즈를 한 라운드 끝까지 조종한다', () {
    final r = rig(8);
    r.commands.run('start', {'game': 'mafia'});
    expect(
      r.commands.run('mafia', {'action': 'day'}),
      containsPair('phase', 'day'),
    );
    expect(
      r.commands.run('mafia', {'action': 'vote'}),
      containsPair('phase', 'vote'),
    );
    final players = r.room.players;
    for (var i = 0; i < players.length; i++) {
      r.room.handleMessage(
        players[i],
        jsonEncode({
          'type': 'mafia_vote',
          'target': players[(i + 1) % players.length].tag,
        }),
      );
    }
    final closed = r.commands.run('mafia', {'action': 'close'});
    expect(closed['phase'], 'vote');
    expect(closed['round'], 2, reason: '투표 마감 뒤 다음 라운드로 넘어가야 한다');
  });

  test('라이어 투표를 열고 마감한다', () {
    final r = rig(4);
    r.commands.run('start', {'game': 'liar'});
    expect(
      r.commands.run('liar', {'action': 'vote'}),
      containsPair('voteOpen', true),
    );
    expect(
      r.commands.run('liar', {'action': 'close'}),
      containsPair('voteOpen', false),
    );
    expect((r.room.activeGame! as LiarGame).isOver, isTrue);
  });

  test('구슬을 출발시키고 결과를 낸다', () {
    final r = rig(5);
    r.commands.run('start', {
      'game': 'marble',
      'rules': {'winnerRank': 'last', 'course': 'sprint'},
    });
    r.commands.run('marble', {'action': 'launch'});
    final result = r.commands.run('marble', {'action': 'skip'});
    expect(result, containsPair('finished', true));
    final game = r.room.activeGame! as MarbleGame;
    expect(game.winnerRank, 'last');
    expect(game.courseId, 'sprint');
  });

  test('사다리 남은 줄을 모두 공개한다', () async {
    final r = rig(2);
    r.commands.run('start', {
      'game': 'ladder',
      'outcomes': ['당첨', '꽝'],
    });
    r.commands.run('ladder', {'action': 'all'});

    final game = r.room.activeGame! as LadderGame;
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!game.finished && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(game.finished, isTrue, reason: '화면 없이도 자동 공개가 끝나야 한다');
    expect(game.revealed, hasLength(2));
  });

  test('판이 도는 중 새 판으로 조용히 갈아치우지 않는다', () {
    final r = rig(5);
    r.commands.run('start', {'game': 'mafia'});

    expect(
      () => r.commands.run('start', {'game': 'liar'}),
      throwsA(isA<ControlFailure>()),
    );
    expect(r.room.activeGame, isA<MafiaGame>());
  });
}
