import 'dart:convert';
import 'dart:io';

import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

import 'support/memory_assets.dart';
import 'support/participant.dart';

/// 대화·자료의 칸(섹션).
///
/// '전체' 는 방이 열려 있는 내내 살고, 게임을 시작할 때마다 그 판의 칸이
/// 열린다. 판이 끝나도 칸은 남아 나중에 그 판만 펼쳐 볼 수 있어야 한다 —
/// 이게 이 구조의 존재 이유라, 여기가 깨지면 나눈 의미가 없다.
void main() {
  const limits = RoomLimits();

  group('칸 만들기', () {
    test('처음에는 전체 하나뿐이다', () {
      final c = RoomChannels();
      expect(c.sections, hasLength(1));
      expect(c.room.id, RoomChannels.roomId);
      expect(c.room.kind, SectionKind.room);
      expect(c.defaultId, RoomChannels.roomId);
    });

    test('판마다 칸이 열리고 종목별로 판수를 센다', () {
      final c = RoomChannels();
      // 서버는 "몇 번째 판" 이라는 사실만 센다 — '마피아 3판' 이라는 문구는
      // 화면이 붙인다.
      //
      // 회차는 **남는 칸**을 센다. 아무 말도 없던 판의 칸은 안 남으므로,
      // 여기서는 판마다 한 마디씩 남겨 실제 파티처럼 만든다.
      void say(ChatSection s) =>
          c.append(s.id, {'type': 'chat_msg', 'text': '한 마디'});

      final first = c.openGame('mafia', '마피아');
      expect(first.round, 1);
      say(first);
      final second = c.openGame('mafia', '마피아');
      expect(second.round, 2);
      say(second);
      final marble = c.openGame('marble', '구슬 룰렛');
      expect(marble.round, 1);
      expect(marble.gameName, '구슬 룰렛');
      say(marble);
      expect(c.openGame('mafia', '마피아').round, 3);
    });

    test('아무 말도 없던 판은 칸도 회차도 안 남긴다', () {
      // 실측: 구슬 룰렛 아홉 판을 돌리자 빈 칸이 열한 개 생겨 단톡 탭을
      // 채웠고, 그 안에는 아무것도 없었다.
      final c = RoomChannels();
      for (var i = 0; i < 5; i++) {
        c.openGame('marble', '구슬 룰렛');
        c.closeLiveGame();
      }
      expect(c.sections, hasLength(1), reason: '빈 칸이 탭을 채운다');

      final kept = c.openGame('marble', '구슬 룰렛');
      c.append(kept.id, {'type': 'chat_msg', 'text': '이번엔 말한다'});
      c.closeLiveGame();
      expect(c.sections, hasLength(2));
      expect(c.sections.last.round, 1, reason: '버린 판까지 세면 회차가 뻥튀기된다');
    });

    test('새 판이 열리면 이전 판은 쓰기가 닫힌다', () {
      final c = RoomChannels();
      final first = c.openGame('mafia', '마피아');
      // 한 마디 남겨 둔다 — 빈 칸이면 아예 사라져서 'live 가 꺼졌다' 를
      // 확인하는 의미가 없어진다.
      c.append(first.id, {'type': 'chat_msg', 'text': '있었다'});
      c.openGame('liar', '라이어');
      expect(first.live, isFalse, reason: '두 판이 동시에 열려 있으면 어디에 쓸지 알 수 없다');
      expect(c.liveGame!.gameId, 'liar');
    });

    test('판이 끝나도 칸과 기록은 남는다', () {
      final c = RoomChannels();
      final s = c.openGame('mafia', '마피아');
      c.append(s.id, {'text': '밤이 되었습니다'});
      c.closeLiveGame();
      expect(c.byId(s.id), isNotNull);
      expect(c.byId(s.id)!.messages, hasLength(1));
      expect(c.byId(s.id)!.live, isFalse);
    });

    test('끝난 판에 쓰려 하면 지금 열린 칸으로 흘러간다', () {
      final c = RoomChannels();
      final old = c.openGame('mafia', '마피아');
      c.closeLiveGame();
      // 조용히 거절하면 참가자 화면이 먹통이 된다 — 갈 곳을 준다.
      expect(c.writableId(old.id), RoomChannels.roomId);

      final live = c.openGame('liar', '라이어');
      expect(c.writableId(old.id), live.id);
      expect(c.writableId(null), live.id, reason: '판이 돌면 그 판이 기본이다');
      expect(
        c.writableId(RoomChannels.roomId),
        RoomChannels.roomId,
        reason: '전체는 게임 중에도 언제나 쓸 수 있다',
      );
    });

    test('모르는 칸을 지정해도 안전하게 떨어진다', () {
      final c = RoomChannels();
      expect(c.writableId('그런칸없음'), RoomChannels.roomId);
    });
  });

  group('칸이 무한정 쌓이지 않는다', () {
    test('오래된 판부터 버리고 전체는 남는다', () {
      final c = RoomChannels();
      // 빈 칸은 애초에 안 남으므로, 상한을 시험하려면 판마다 말이 있어야
      // 한다 — 실제로 상한까지 차오르는 파티가 그렇다.
      for (var i = 0; i < limits.sections + 6; i++) {
        final s = c.openGame('mafia', '마피아');
        c.append(s.id, {'type': 'chat_msg', 'text': '$i'});
      }
      expect(c.sections.length, lessThanOrEqualTo(limits.sections));
      expect(c.byId(RoomChannels.roomId), isNotNull, reason: '전체는 절대 안 버린다');
      expect(c.liveGame, isNotNull, reason: '진행 중인 판을 버리면 안 된다');
      // 남은 것 중 가장 마지막은 제일 최근 판이어야 한다.
      expect(c.sections.last.round, limits.sections + 6);
    });

    test('칸 하나의 기록도 상한이 있다', () {
      final c = RoomChannels();
      for (var i = 0; i < limits.messagesPerSection + 20; i++) {
        c.append(RoomChannels.roomId, {'text': '$i'});
      }
      expect(c.room.messages, hasLength(limits.messagesPerSection));
      expect(c.room.messages.last['text'], '${limits.messagesPerSection + 19}');
    });
  });

  group('저장·복구', () {
    test('칸·기록·판수가 그대로 돌아온다', () {
      final a = RoomChannels();
      a.append(RoomChannels.roomId, {'text': '로비 잡담'});
      final g = a.openGame('mafia', '마피아');
      a.append(g.id, {'text': '밤이 되었습니다'});
      a.closeLiveGame();

      final b = RoomChannels()
        ..restore(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect(b.sections.map((s) => s.kind), [
        SectionKind.room,
        SectionKind.game,
      ]);
      expect(b.sections.last.gameName, '마피아');
      expect(b.sections.last.round, 1);
      expect(b.byId(g.id)!.messages.single['text'], '밤이 되었습니다');
      expect(b.room.messages.single['text'], '로비 잡담');
      // 이어서 시작하는 판은 2판이어야 한다 — 1판이 또 나오면 기록이 헷갈린다.
      expect(b.openGame('mafia', '마피아').round, 2);
    });

    test('복구된 판은 진행 중이 아니다', () {
      final a = RoomChannels();
      a.openGame('mafia', '마피아'); // live 인 채로 저장
      final b = RoomChannels()
        ..restore(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect(b.liveGame, isNull, reason: '앱이 죽은 판을 진행 중으로 되살리면 안 된다');
      expect(b.defaultId, RoomChannels.roomId);
    });

    test('빈 저장분은 무시한다', () {
      final c = RoomChannels()..restore(null);
      expect(c.sections, hasLength(1));
    });
  });

  group('방 서버와 이어 붙였을 때', () {
    late RoomServer server;
    late Room room;
    late int port;

    setUp(() async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      port = probe.port;
      await probe.close();
      server = RoomServer(assets: MemoryAssets(), port: port);
      room = server.createRoom(token: 'TESTRM');
      await server.start();
    });
    tearDown(() => server.stop());

    Future<String> join(String nick) async {
      final c = HttpClient();
      final req = await c.post('127.0.0.1', port, '/api/join');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'room': 'TESTRM', 'nickname': nick}));
      final res = await req.close();
      final body =
          jsonDecode(await res.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      c.close();
      return body['session'] as String;
    }

    test('게임 중 대화는 그 판 칸에 남는다', () async {
      final session = await join('가');
      final ws = IOWebSocketChannel(
        await WebSocket.connect('ws://127.0.0.1:$port/ws?room=TESTRM'),
      );
      final inbox = <Map<String, dynamic>>[];
      ws.stream.listen(
        (m) => inbox.add(jsonDecode(m as String) as Map<String, dynamic>),
      );
      authAs(ws, session);
      // 고정 지연으로 기다리면 기계가 바쁠 때 밀린다 — 판이 열리기 전에
      // '판 안에서' 가 먼저 도착해 엉뚱한 칸에 남는다. 상태를 기다린다.
      await waitUntil(
        () => room.players.single.connected,
        reason: '소켓이 자리에 안 앉았다',
      );

      ws.sink.add(jsonEncode({'type': 'chat', 'text': '로비에서'}));
      await waitUntil(
        () => room.chatHistoryOf(RoomChannels.roomId).isNotEmpty,
        reason: '로비 대화가 안 남았다',
      );

      room.startGame(MarbleGame());
      await waitUntil(
        () => room.channels.liveGame != null,
        reason: '판 칸이 안 열렸다',
      );
      // 도배 억제 간격을 지나야 두 번째 발화가 받아들여진다. 예전 고정
      // 지연(150+150ms)이 우연히 이 문턱을 넘고 있었을 뿐이라, 기계가
      // 한가해 빨리 진행되면 오히려 실패하는 거꾸로 된 테스트였다.
      await Future<void>.delayed(
        Duration(milliseconds: room.limits.chatIntervalMs + 30),
      );
      ws.sink.add(jsonEncode({'type': 'chat', 'text': '판 안에서'}));
      await waitUntil(
        () => room.chatHistoryOf(room.channels.liveGame!.id).isNotEmpty,
        reason: '판 안 대화가 안 남았다',
      );

      final gameSection = room.channels.liveGame!;
      expect(gameSection.gameName, '구슬 룰렛');
      expect(gameSection.round, 1);
      expect(room.chatHistoryOf(RoomChannels.roomId).single['text'], '로비에서');
      expect(room.chatHistoryOf(gameSection.id).single['text'], '판 안에서');

      // 폰도 칸 목록을 받아야 화면을 그린다.
      expect(inbox.any((m) => m['type'] == 'sections'), isTrue);
      // 방에 남은 것과 폰에 도착한 것은 다른 시점이다 — 도착을 기다린다.
      await waitUntil(
        () => inbox.any((m) => m['type'] == 'chat_msg' && m['text'] == '판 안에서'),
        reason: '판 안 대화가 폰까지 안 갔다',
      );
      final chat = inbox.lastWhere((m) => m['type'] == 'chat_msg');
      expect(chat['section'], gameSection.id);

      await ws.sink.close();
    });

    test('전체 칸을 지정하면 게임 중에도 거기 남는다', () async {
      final session = await join('가');
      final ws = IOWebSocketChannel(
        await WebSocket.connect('ws://127.0.0.1:$port/ws?room=TESTRM'),
      );
      ws.stream.listen((_) {});
      ws.sink.add(jsonEncode({'type': 'auth', 'session': session}));
      await Future.delayed(const Duration(milliseconds: 150));
      room.startGame(MarbleGame());
      await Future.delayed(const Duration(milliseconds: 150));

      ws.sink.add(
        jsonEncode({'type': 'chat', 'text': '딴얘기', 'section': 'room'}),
      );
      await Future.delayed(const Duration(milliseconds: 200));
      expect(room.chatHistoryOf('room').single['text'], '딴얘기');
      expect(room.chatHistoryOf(room.channels.liveGame!.id), isEmpty);
      await ws.sink.close();
    });

    test('사회자 말은 그 판의 기록으로 남는다', () async {
      room.startGame(MarbleGame());
      room.mcChat('구슬이 출발합니다');
      final id = room.channels.liveGame!.id;
      expect(room.chatHistoryOf(id).single['speaker'], Speaker.mc);
      expect(room.chatHistoryOf('room'), isEmpty);
    });

    test('판이 끝나면 새 말은 전체로 간다', () async {
      room.startGame(MarbleGame());
      final id = room.channels.liveGame!.id;
      room.hostChat('굴러갑니다'); // 판 안에서
      room.endGame();
      room.hostChat('수고하셨습니다'); // 끝난 뒤

      expect(room.chatHistoryOf('room').single['text'], '수고하셨습니다');
      expect(
        room.chatHistoryOf(id).single['text'],
        '굴러갑니다',
        reason: '끝난 뒤의 말이 지난 판 칸으로 새면 안 된다',
      );
      expect(
        room.channels.byId(id),
        isNotNull,
        reason: '말이 오간 칸은 판이 끝나도 남아야 한다',
      );
    });

    test('자료도 칸을 따라간다', () async {
      final tmp = File(
        '${Directory.systemTemp.createTempSync('secfile').path}/사진.jpg',
      )..writeAsStringSync('x');
      addTearDown(() => tmp.parent.deleteSync(recursive: true));

      await room.shareFile(tmp.path); // 로비에서
      room.startGame(MarbleGame());
      final id = room.channels.liveGame!.id;
      await room.shareFile(tmp.path); // 판 안에서

      expect(room.sharedFilesIn('room'), hasLength(1));
      expect(room.sharedFilesIn(id), hasLength(1));
      expect(room.sharedFiles, hasLength(2));

      expect(await room.removeSectionFiles(id), 1);
      expect(room.sharedFilesIn(id), isEmpty);
      expect(room.sharedFilesIn('room'), hasLength(1), reason: '다른 칸은 그대로');
    });
  });

  _ownsSectionTests();
}

/// 칸을 여는 주체는 **종목**이다.
///
/// 예전에는 방 서버가 "게임이 시작되면 무조건 칸을 연다" 고 정했다. 그러면
/// 칸 쓸 일이 없는 종목까지 빈 칸을 남긴다 — minPlayers 처럼 모듈이 스스로
/// 밝히는 값이어야 한다.
void _ownsSectionTests() {
  group('칸 소유는 종목이 선언한다', () {
    test('선언한 종목만 칸을 연다', () {
      for (final id in GameRegistry.ids) {
        final m = GameRegistry.create(id)!;
        expect(m.ownsSection, isA<bool>(), reason: '$id 가 칸 소유를 밝히지 않았다');
      }
      expect(
        GameRegistry.create('poll')!.ownsSection,
        isFalse,
        reason: '즉석 투표는 물어보고 끝이라 빈 칸만 쌓인다',
      );
      expect(GameRegistry.create('mafia')!.ownsSection, isTrue);
    });

    test('칸을 안 쓰는 종목은 칸을 만들지 않는다', () {
      final c = RoomChannels();
      final before = c.sections.length;
      final poll = GameRegistry.create('poll')!;
      if (poll.ownsSection) c.openGame(poll.id, poll.name);
      expect(c.sections.length, before);
      expect(c.defaultId, RoomChannels.roomId, reason: '말은 전체로 가야 한다');
    });
  });
}
