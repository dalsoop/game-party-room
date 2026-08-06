import 'dart:convert';
import 'dart:io';

import 'package:party_room_server/party_room_server.dart';
import 'package:party_room_server/testing.dart';
import 'package:test/test.dart';

import 'support/memory_assets.dart';

/// 적대적 감사가 짚은 자리들.
///
/// 이 파일의 테스트는 하나하나가 "이렇게 하면 실제로 깨진다" 는 재현 절차다.
/// 대부분 파티 중에 조용히 일어나서 아무도 원인을 모르는 종류다 — 친구가
/// 안 들어와지고, 사진이 사라지고, 용량이 이유 없이 찼다고 나오는 것들.
void main() {
  final assets = MemoryAssets();

  group('비밀번호 잠금', () {
    test('비밀번호를 바꾸면 연타 잠금도 함께 풀린다', () {
      final room = Room()..setPin('1234');
      for (var i = 0; i < 5; i++) {
        room.admits('0000');
      }
      expect(room.admits('1234').error, 'pin_locked', reason: '연타 차단이 안 걸렸다');

      // 호스트가 "안 들어와져?" 하고 비밀번호를 바꿔 준 상황.
      room.setPin('9999');
      expect(
        room.admits('9999').error,
        isNull,
        reason: '바꿔 준 비밀번호로도 30초를 더 튕기면 호스트는 원인을 못 찾는다',
      );
    });

    test('비밀번호를 풀어도 잠금이 안 남는다', () {
      final room = Room()..setPin('1234');
      for (var i = 0; i < 5; i++) {
        room.admits('0000');
      }
      room.setPin(null);
      expect(room.admits(null).error, isNull);
    });
  });

  group('닫으면 정말 닫힌다', () {
    // `dispose()`·`clear()` 가 소켓 닫힘을 안 기다리면, "다 닫았다" 고
    // 돌아온 뒤에도 옛 소켓이 살아 있다. 바로 이어지는 판단(아무도 없다)이
    // 틀리고, 지운 방의 소켓이 잠깐 더 말할 수 있다.
    test('지우고 나면 붙어 있던 소켓이 남지 않는다', () async {
      final room = Room();
      final sockets = [
        for (final n in ['민서', '태윤', '지우'])
          (room.seat(n)!..link = RecordingLink()).link! as RecordingLink,
      ];
      expect(room.players.where((p) => p.connected), hasLength(3));

      await room.dispose();
      for (final s in sockets) {
        expect(s.closed, isTrue, reason: 'dispose 가 돌아왔는데 소켓이 안 닫혔다');
      }
    });

    test('비우고 나면 쫓겨난 소켓이 남지 않는다', () async {
      final room = Room();
      final s =
          (room.seat('민서')!..link = RecordingLink()).link! as RecordingLink;
      await room.clear();
      expect(s.closed, isTrue, reason: 'clear 가 돌아왔는데 소켓이 안 닫혔다');
      expect(
        s.sent.any((m) => m.contains('kicked')),
        isTrue,
        reason: '닫기 전에 왜 나가는지 알려야 한다',
      );
    });
  });

  group('지운 방', () {
    test('지운 뒤에는 업로드를 받지 않는다', () async {
      final room = Room();
      final p = room.seat('민서')!;
      await room.dispose();

      final r = await room.saveUpload(
        name: 'a.png',
        bytes: [1, 2, 3],
        uploader: p,
        sectionId: 'room',
      );
      expect(r.file, isNull, reason: '지운 방이 파일을 받으면 임시 폴더가 남는다');
      expect(room.sharedFiles, isEmpty);
    });

    test('비우는 중 도착한 업로드가 비운 방을 되살리지 않는다', () async {
      final room = Room();
      final p = room.seat('태윤')!;
      final slow = room.saveUpload(
        name: 'b.png',
        bytes: List.filled(2048, 7),
        uploader: p,
        sectionId: 'room',
      );
      await room.clear();
      final r = await slow;

      expect(r.file, isNull, reason: '비운 방에 옛 참가자의 파일이 다시 앉았다');
      expect(room.sharedFiles, isEmpty);
      expect(room.players, isEmpty);
    });
  });

  group('쿼터', () {
    test('동시 업로드가 같은 몫을 두 번 쓰지 못한다', () async {
      // 검사와 등록 사이에 파일 쓰기(await)가 있어서, 그 틈에 들어온 두
      // 번째가 똑같이 "아직 0개" 를 보고 통과했다.
      final room = Room(limits: const RoomLimits(filesPerOwner: 1));
      final p = room.seat('지우')!;
      final both = await Future.wait([
        for (var i = 0; i < 2; i++)
          room.saveUpload(
            name: '$i.png',
            bytes: List.filled(64, i),
            uploader: p,
            sectionId: 'room',
          ),
      ]);
      addTearDown(room.dispose);

      expect(both.where((r) => r.file != null), hasLength(1));
      expect(room.sharedFiles, hasLength(1), reason: '1개 제한에 2개가 들어앉았다');
      expect(both.firstWhere((r) => r.file == null).refusal, isNotNull);
    });

    test('거절 문구에 실제 숫자가 들어간다', () async {
      // 예전에는 `'$limits.filesPerOwner개'` 라 사람이 읽을 자리에
      // "RoomLimits instance.filesPerOwner개" 가 찍혔다.
      final room = Room(limits: const RoomLimits(filesPerOwner: 1));
      final p = room.seat('하준')!;
      await room.saveUpload(
        name: 'a.png',
        bytes: [1],
        uploader: p,
        sectionId: 'room',
      );
      addTearDown(room.dispose);

      final refusal = room.quotaRefusal('room', p.tag, 1);
      expect(refusal, contains('1개'));
      expect(refusal, isNot(contains('RoomLimits')));
      expect(refusal, isNot(contains(r'$')));
    });

    test('호스트가 올린 파일도 방 전체 용량을 쓴다', () async {
      final dir = Directory.systemTemp.createTempSync('hostfile');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/big.bin')
        ..writeAsBytesSync(List.filled(64, 1));

      final room = Room(limits: const RoomLimits(totalBytes: 32));
      expect(
        await room.shareFile(f.path),
        isNull,
        reason: '호스트 파일이 용량을 안 세면 그 뒤 손님 업로드가 이유 없이 거절된다',
      );
      expect(room.sharedFiles, isEmpty);
    });

    test('밀려난 칸의 자료는 용량도 함께 놓아 준다', () async {
      // 예전에는 칸만 사라지고 파일은 목록에 남아, 화면에서 열 수도 없는
      // 파일이 방 용량을 계속 먹었다.
      final room = Room(limits: const RoomLimits(sections: 2));
      addTearDown(room.dispose);
      final p = room.seat('서준')!;
      room.startGame(MarbleGame());
      final live = room.channels.liveGame!.id;
      await room.saveUpload(
        name: 'shot.png',
        bytes: List.filled(128, 3),
        uploader: p,
        sectionId: live,
      );
      expect(room.sharedFilesIn(live), hasLength(1));
      final was = room.totalFileBytes;

      // 칸 상한을 넘겨 위 칸을 밀어낸다.
      room.startGame(MarbleGame());
      room.startGame(MarbleGame());

      expect(room.channels.sections.any((s) => s.id == live), isFalse);
      expect(room.sharedFilesIn(live), isEmpty, reason: '못 여는 파일이 용량을 물고 있다');
      expect(room.totalFileBytes, lessThan(was));
    });
  });

  group('저장·복구', () {
    test('자료함이 재시작을 넘어간다', () async {
      final dir = Directory.systemTemp.createTempSync('sharefile');
      addTearDown(() => dir.deleteSync(recursive: true));
      final doc = File('${dir.path}/발표.pdf')..writeAsStringSync('hello');

      final store = MemoryStateStore();
      final a = RoomServer(assets: assets);
      final room = a.createRoom(name: '금요 모임', token: 'KEEPF1');
      expect(await room.shareFile(doc.path), isNotNull);

      final p = RoomPersistence(store, assets);
      await p.save(a);

      final b = RoomServer(assets: assets);
      await p.restoreInto(b);
      expect(
        b.byToken('KEEPF1')!.sharedFiles.map((f) => f.name),
        ['발표.pdf'],
        reason: '방과 대화는 돌아오는데 자료만 사라졌다',
      );
    });

    test('사라진 파일은 되살리지 않는다', () async {
      // 참가자 업로드 사본은 임시 폴더에 살고 그 폴더는 재시작 청소에
      // 사라진다 — 메타데이터만 살리면 누르면 404 나는 항목이 남는다.
      final dir = Directory.systemTemp.createTempSync('gonefile');
      final doc = File('${dir.path}/사라짐.pdf')..writeAsStringSync('x');

      final store = MemoryStateStore();
      final a = RoomServer(assets: assets);
      await a.createRoom(token: 'GONE01').shareFile(doc.path);
      final p = RoomPersistence(store, assets);
      await p.save(a);
      dir.deleteSync(recursive: true);

      final b = RoomServer(assets: assets);
      await p.restoreInto(b);
      expect(b.byToken('GONE01')!.sharedFiles, isEmpty);
    });

    test('되살린 판은 자기 칸도 함께 연다', () async {
      // 예전에는 판만 살아나고 칸은 전부 닫힌 채였다 — 이어지는 사회자
      // 대사와 업로드가 그 판이 아니라 '전체' 칸에 쌓였다.
      final store = MemoryStateStore();
      final a = RoomServer(assets: assets);
      a.createRoom(token: 'LIVE01').startGame(MarbleGame());
      final p = RoomPersistence(store, assets);
      await p.save(a);

      final b = RoomServer(assets: assets);
      await p.restoreInto(b);
      final room = b.byToken('LIVE01')!;
      expect(room.activeGame, isNotNull);
      expect(
        room.channels.liveGame,
        isNotNull,
        reason: '판은 도는데 열린 판 칸이 없으면 기록이 엉뚱한 칸에 쌓인다',
      );
      expect(room.channels.liveGame!.gameId, 'marble');
    });

    test('방 하나가 깨져도 나머지는 살린다', () async {
      // 예전에는 catch 가 저장소를 통째로 지웠다 — 두 번째 방의 필드 하나가
      // 이상하다고 멀쩡한 첫 방까지, 그것도 영구히 날아갔다.
      final store = MemoryStateStore();
      final now = DateTime.now().millisecondsSinceEpoch;
      await store.write(
        jsonEncode({
          'schemaVersion': 2,
          'rooms': [
            {
              'savedAt': now,
              'roomToken': 'GOOD01',
              'name': '금요 모임',
              'open': true,
              'players': const [],
              'game': null,
            },
            // roomToken 이 없다 — 이 항목만 못 읽는다.
            {'savedAt': now, 'name': '깨진 방', 'players': const []},
            {
              'savedAt': now,
              'roomToken': 'GOOD02',
              'name': '회사 워크숍',
              'open': true,
              'players': const [],
              'game': null,
            },
          ],
        }),
      );

      final server = RoomServer(assets: assets);
      final outcome = await RoomPersistence(store, assets).restoreInto(server);
      expect(server.rooms.map((r) => r.name), [
        '금요 모임',
        '회사 워크숍',
      ], reason: '뒤쪽 멀쩡한 방까지 잃었다');
      expect(outcome.rooms, 2, reason: '실제 방 수와 보고가 어긋나면 안내가 거짓말이 된다');
    });
  });

  group('빈 판 칸', () {
    // 실측: 구슬 룰렛 아홉 판을 돌리자 빈 칸이 열한 개 생겨 단톡 탭을
    // 채웠고, 그 안에는 아무것도 없었다. 파티 한 번에 상한까지 차오른다.
    test('아무 말도 없던 판의 칸은 안 남는다', () {
      final room = Room();
      room.seat('민서');
      for (var i = 0; i < 5; i++) {
        room.startGame(MarbleGame());
        room.endGame();
      }
      expect(room.channels.sections.map((s) => s.kind), [
        SectionKind.room,
      ], reason: '아무도 말 안 한 판의 칸이 탭을 채운다');
    });

    test('말이 오간 판의 칸은 남는다', () {
      final room = Room();
      room.seat('민서');
      room.startGame(MarbleGame());
      room.hostChat('자 굴립니다');
      room.endGame();
      expect(room.channels.sections, hasLength(2));
      expect(room.chatHistoryOf(room.channels.sections.last.id), hasLength(1));
    });

    test('자료만 올라온 판의 칸도 남는다', () async {
      final room = Room();
      addTearDown(room.dispose);
      final p = room.seat('태윤')!;
      room.startGame(MarbleGame());
      final live = room.channels.liveGame!.id;
      await room.saveUpload(
        name: 'shot.png',
        bytes: [1, 2, 3],
        uploader: p,
        sectionId: live,
      );
      room.endGame();
      expect(room.channels.sections.any((s) => s.id == live), isTrue);
    });

    test('빈 칸을 버리면 회차 번호도 되돌린다', () {
      // 안 그러면 남은 칸이 '구슬 5라운드' 하나뿐인데 1~4 가 어디에도 없다.
      final room = Room();
      room.seat('지우');
      for (var i = 0; i < 3; i++) {
        room.startGame(MarbleGame());
        room.endGame();
      }
      room.startGame(MarbleGame());
      room.hostChat('이번엔 말한다');
      room.endGame();
      final kept = room.channels.sections.last;
      expect(kept.round, 1, reason: '버린 판까지 세면 회차가 뻥튀기된다');
    });
  });

  group('판 진행이 저장된다', () {
    // 실측으로 잡았다: 3줄 공개한 사다리가 재시작 후 0줄로 돌아왔다.
    // 게임 이벤트가 방을 "바뀐 것" 으로 표시하지 않아, 판 진행은 저장된
    // 적이 없었다 — 채팅 같은 다른 일이 우연히 저장을 부를 때만 얹혀 남았다.
    test('게임 이벤트가 저장 신호를 낸다', () {
      final room = Room();
      var touched = 0;
      room.onStateChanged = () => touched++;
      room.seat('민서');
      room.seat('태윤');

      final before = touched;
      room.startGame(LadderGame()..rawOutcomes = ['꽝', '당첨']);
      expect(touched, greaterThan(before), reason: '판이 움직였는데 아무도 저장하라고 안 했다');
    });

    test('사다리 공개가 저장분에 남는다', () async {
      final assets = MemoryAssets();
      final store = MemoryStateStore();
      final a = RoomServer(assets: assets);
      final room = a.createRoom(token: 'LAD001');
      room.seat('민서');
      room.seat('태윤');
      final g = LadderGame()..rawOutcomes = ['꽝', '당첨'];
      room.startGame(g);
      g.reveal(room.gameCtx, 0);

      final p = RoomPersistence(store, assets);
      await p.save(a);
      final b = RoomServer(assets: assets);
      await p.restoreInto(b);

      final revived = b.byToken('LAD001')!.activeGame as LadderGame;
      expect(
        revived.revealed.length,
        g.revealed.length,
        reason: '공개한 줄이 재시작에 사라졌다',
      );
    });
  });

  group('정원이 찬 방', () {
    // 이름 붙인 방은 파티마다 다시 쓴다. 지난주 손님이 명단을 다 채우면
    // 실제로는 비어 있는 방인데 아무도 못 들어온다 — 테스트 중 실제로
    // 걸렸다(명단 20 · 접속 1). 문 앞에서 막히면 앱이 고장 난 것으로 보인다.
    Room fullRoom({required Duration seenAgo}) {
      final room = Room(limits: const RoomLimits(players: 3));
      final now = DateTime.now();
      for (var i = 0; i < 3; i++) {
        room.seat('지난주손님$i')!.lastSeen = now.subtract(seenAgo);
      }
      return room;
    }

    test('지난 파티 손님은 자리를 비켜 준다', () {
      final room = fullRoom(seenAgo: const Duration(days: 7));
      final p = room.seat('새손님');
      expect(p, isNotNull, reason: '비어 있는 방인데 아무도 못 들어온다');
      expect(room.players, hasLength(3), reason: '정원을 넘겨 받으면 안 된다');
      expect(room.players.map((x) => x.nickname), contains('새손님'));
    });

    test('방금 끊긴 사람의 자리는 안 뺏는다', () {
      // 폰이 잠기거나 지하철에 들어간 사람이다 — 돌아올 자리를 남긴다.
      final room = fullRoom(seenAgo: const Duration(minutes: 2));
      expect(room.seat('새손님'), isNull);
      expect(room.players, hasLength(3));
    });

    test('판이 도는 중에는 자리를 안 건드린다', () {
      // 명단은 판 시작 시점에 고정돼 있다 — 지우면 게임이 없는 사람을 본다.
      final room = fullRoom(seenAgo: const Duration(days: 7));
      room.startGame(MarbleGame());
      expect(room.seat('새손님'), isNull);
      expect(room.players, hasLength(3));
    });

    test('막 들어온 사람의 자리는 절대 안 뺏는다', () {
      // `/api/join` 을 마치고 소켓을 여는 중인 사람은 lastSeen 이 없다.
      // 이것을 '떠난 자리' 로 보면, 여럿이 동시에 QR 을 찍었을 때 서로를
      // 쫓아낸다 — 파티 시작 5분이 그런 순간이다.
      final room = Room(limits: const RoomLimits(players: 2));
      room.seat('가');
      room.seat('나');
      expect(room.players.every((p) => p.lastSeen == null), isTrue);
      expect(room.seat('다'), isNull, reason: '들어오는 중인 사람을 밀어냈다');
      expect(room.players.map((p) => p.nickname), ['가', '나']);
    });
  });

  group('끝난 판', () {
    // 실제로 굴려 보다 잡았다. 승패가 갈린 뒤에도 페이즈 명령이 그대로
    // 먹혀서, 남은 2명이 1명이 될 때까지 계속 죽었다. 파티에서 호스트가
    // 버튼을 한 번 더 누르면 승리 화면이 덮여 씌워진다.
    test('마피아 — 끝난 판은 더 사람을 죽이지 않는다', () {
      final room = Room();
      for (final n in ['민서', '태윤', '지우', '서준']) {
        room.seat(n);
      }
      final g = MafiaGame();
      room.startGame(g);

      // 끝날 때까지 굴린다.
      for (var i = 0; i < 12 && !g.isOver; i++) {
        g.beginNight(room.gameCtx);
        g.beginDay(room.gameCtx);
        if (g.isOver) break;
        g.beginVote(room.gameCtx);
        g.closeVote(room.gameCtx);
      }
      expect(g.isOver, isTrue, reason: '판이 안 끝나면 이 테스트가 무의미하다');

      final aliveWhenOver = g.aliveCount;
      final roundWhenOver = g.round;
      for (var i = 0; i < 3; i++) {
        g.beginNight(room.gameCtx);
        g.beginDay(room.gameCtx);
        g.beginVote(room.gameCtx);
        g.closeVote(room.gameCtx);
      }
      expect(g.aliveCount, aliveWhenOver, reason: '끝난 판에서 사람이 더 죽었다');
      expect(g.round, roundWhenOver);
      expect(g.phase, MafiaPhase.ended, reason: '끝난 판이 되살아났다');
    });

    test('라이어 — 정답을 공개한 뒤 투표를 다시 열지 않는다', () {
      final room = Room();
      for (final n in ['민서', '태윤', '지우']) {
        room.seat(n);
      }
      final g = LiarGame();
      room.startGame(g);
      g.beginVote(room.gameCtx);
      g.closeVote(room.gameCtx);
      expect(g.isOver, isTrue);

      // 라이어와 제시어가 이미 전원에게 갔다 — 다시 지목해도 뜻이 없다.
      g.beginVote(room.gameCtx);
      expect(g.voteOpen, isFalse, reason: '답을 다 본 사람들이 한 번 더 지목하게 된다');
    });

    test('라이어 — 끝난 판은 재시작을 넘어가도 끝난 채다', () {
      final g = LiarGame();
      final revived = LiarGame();
      final room = Room()..seat('민서');
      room.startGame(g);
      g.beginVote(room.gameCtx);
      g.closeVote(room.gameCtx);

      revived.restore(room.gameCtx, g.toJson());
      expect(revived.isOver, isTrue, reason: '재시작에 끝난 판이 되살아났다');
    });
  });

  group('업로드 임시 폴더', () {
    test('첫 업로드가 동시에 와도 폴더는 하나만 생긴다', () async {
      // `_uploadDir ??= await …` 은 둘 다 null 을 보고 각자 만든다 —
      // 늦게 끝난 것만 남아서 먼저 것은 dispose 가 못 찾고 쌓인다.
      final room = Room();
      final p = room.seat('하준')!;
      final r = await Future.wait([
        for (var i = 0; i < 4; i++)
          room.saveUpload(
            name: '$i.bin',
            bytes: [i],
            uploader: p,
            sectionId: 'room',
          ),
      ]);

      // 방이 아는 폴더는 하나뿐이다. 올린 파일이 전부 **그 폴더 안**에
      // 있어야 dispose 가 하나도 안 남기고 치울 수 있다.
      final dir = Directory(room.uploadDirPath!);
      expect(
        r.map((x) => File(x.file!.path).parent.path).toSet(),
        {dir.path},
        reason: '방이 모르는 폴더에 올라간 파일이 있다 — 그 폴더는 영영 안 지워진다',
      );

      await room.dispose();
      expect(dir.existsSync(), isFalse, reason: '치우고 나서도 폴더가 남았다');
    });

    test('살아 있는 방의 폴더는 청소가 건드리지 않는다', () async {
      // 이 패키지는 혼자서도 돌 수 있어 방 서버가 둘일 수 있다. 접두사만
      // 보고 지우면 남의 참가자가 올린 사진이 사라지고 다운로드가 404 가 된다.
      final room = Room();
      final p = room.seat('민서')!;
      final r = await room.saveUpload(
        name: 'keep.png',
        bytes: [1, 2, 3],
        uploader: p,
        sectionId: 'room',
      );
      expect(r.file, isNotNull);

      RoomFiles.sweepStale();
      expect(
        File(r.file!.path).existsSync(),
        isTrue,
        reason: '살아 있는 방의 업로드가 청소에 지워졌다',
      );
      await room.dispose();
    });
  });
}
