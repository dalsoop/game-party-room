import 'dart:convert';
import 'dart:io';

import 'package:party_room_server/party_room_server.dart';
import 'package:party_room_server/testing.dart';
import 'package:test/test.dart';

import 'support/memory_assets.dart';

/// 화면 없이 방을 굴린다.
///
/// 상시로 도는 방 서버(k3s)는 **사람은 모이는데 판을 못 여는** 상태였다.
/// 제어가 앱에만 있었기 때문이다. 여기 있는 것들은 그 문이 지켜야 할 약속이다.
///
/// 앱의 `ControlService` 와 이름·응답 모양을 맞춘다 — 같은 CLI 가 두 서버를
/// 다 조종할 수 있어야 하고, 갈리면 손에 익은 명령이 한쪽에서만 통한다.
void main() {
  final assets = MemoryAssets();

  ({RoomServer server, RoomControl control}) make({int maxRooms = 2}) {
    final s = RoomServer(assets: assets, port: 0, maxRooms: maxRooms);
    return (server: s, control: RoomControl(s));
  }

  group('방', () {
    test('열고 고르고 지운다', () async {
      final m = make();
      final a = await m.control.run('room', {'action': 'new', 'name': '금요 모임'});
      expect(a['name'], '금요 모임');
      expect(m.server.rooms, hasLength(1));

      await m.control.run('room', {'action': 'rename', 'name': '토요 모임'});
      expect(m.server.rooms.single.name, '토요 모임');

      await m.control.run('room', {'action': 'delete', 'confirm': true});
      expect(m.server.rooms, isEmpty);
    });

    test('지우기는 confirm 없이는 안 된다', () async {
      final m = make();
      await m.control.run('room', {'action': 'new'});
      await expectLater(
        m.control.run('room', {'action': 'delete'}),
        throwsA(isA<ControlUsageError>()),
      );
      expect(m.server.rooms, hasLength(1));
    });

    test('정원이 차면 왜 안 되는지 말한다', () async {
      final m = make(maxRooms: 1);
      await m.control.run('room', {'action': 'new'});
      await expectLater(
        m.control.run('room', {'action': 'new'}),
        throwsA(
          isA<ControlFailure>().having((e) => e.message, '메시지', contains('최대')),
        ),
      );
    });

    test('비밀번호 해제는 off 라고 적어야 한다', () async {
      // 빈 값을 해제로 읽으면 자물쇠가 조용히 풀린다 — 앱에서 겪은 실사고.
      final m = make();
      await m.control.run('room', {'action': 'new'});
      await m.control.run('room', {'action': 'pin', 'pin': '1234'});
      expect(m.server.rooms.single.hasPin, isTrue);

      await expectLater(
        m.control.run('room', {'action': 'pin', 'pin': '  '}),
        throwsA(isA<ControlUsageError>()),
      );
      expect(m.server.rooms.single.hasPin, isTrue, reason: '거절했는데 풀렸다');

      final r = await m.control.run('room', {'action': 'pin', 'pin': 'off'});
      expect(r['hasPin'], isFalse);
    });

    test('비밀번호 원문은 안 돌려준다', () async {
      final m = make();
      await m.control.run('room', {'action': 'new'});
      final r = await m.control.run('room', {'action': 'pin', 'pin': '1234'});
      expect(jsonEncode(r), isNot(contains('1234')));
    });

    test('방을 옮겨 다닌다', () async {
      final m = make();
      final a = await m.control.run('room', {'action': 'new', 'name': 'A'});
      final b = await m.control.run('room', {'action': 'new', 'name': 'B'});
      expect((await m.control.run('status', const {}))['selected'], b['token']);

      await m.control.run('room', {'action': 'use', 'token': a['token']});
      expect((await m.control.run('status', const {}))['selected'], a['token']);
    });
  });

  group('판', () {
    test('인원이 모자라면 시작하지 않고 이유를 말한다', () async {
      // 시작해 놓고 안 굴러가는 것보다 왜 안 되는지 말하는 편이 낫다.
      final m = make();
      await m.control.run('room', {'action': 'new'});
      await expectLater(
        m.control.run('start', {'game': 'mafia'}),
        throwsA(
          isA<ControlFailure>().having((e) => e.message, '메시지', contains('명')),
        ),
      );
    });

    test('인원이 차면 시작하고 끝낸다', () async {
      final m = make();
      await m.control.run('room', {'action': 'new'});
      final room = m.server.rooms.single;
      for (var i = 0; i < 8; i++) {
        room.seat('손님$i')!.link = RecordingLink();
      }

      final r = await m.control.run('start', {'game': 'mafia'});
      expect(r['game'], 'mafia');
      expect(room.activeGame, isNotNull);

      await m.control.run('end', const {});
      expect(room.activeGame, isNull);
    });

    test('모르는 게임은 가능한 것을 알려준다', () async {
      final m = make();
      await m.control.run('room', {'action': 'new'});
      await expectLater(
        m.control.run('start', {'game': 'zzz'}),
        throwsA(
          isA<ControlUsageError>().having(
            (e) => e.message,
            '메시지',
            contains('가능'),
          ),
        ),
      );
    });

    test('안 도는 판을 끝내려 하면 거절한다', () async {
      final m = make();
      await m.control.run('room', {'action': 'new'});
      await expectLater(
        m.control.run('end', const {}),
        throwsA(isA<ControlFailure>()),
      );
    });
  });

  group('참가자', () {
    test('태그로 내보낸다', () async {
      final m = make();
      await m.control.run('room', {'action': 'new'});
      final p = m.server.rooms.single.seat('민서')!..link = RecordingLink();

      final r = await m.control.run('kick', {'tag': p.tag});
      expect(r['nickname'], '민서');
      expect(p.kicked, isTrue);
    });

    test('없는 태그는 거절한다', () async {
      final m = make();
      await m.control.run('room', {'action': 'new'});
      await expectLater(
        m.control.run('kick', {'tag': 'ZZZZ'}),
        throwsA(isA<ControlFailure>()),
      );
    });
  });

  test('방이 없으면 무엇을 하라고 말한다', () async {
    final m = make();
    await expectLater(
      m.control.run('players', const {}),
      throwsA(
        isA<ControlFailure>().having(
          (e) => e.message,
          '메시지',
          contains('room new'),
        ),
      ),
    );
  });

  test('capabilities 가 세부 진행을 지원한다고 밝힌다', () async {
    final m = make();
    final c = await m.control.run('capabilities', const {});
    expect(c['surface'], 'headless');
    expect((c['actions'] as Map).keys, contains('start'));
    expect(
      (c['actions'] as Map).keys,
      containsAll(['mafia', 'liar', 'marble', 'ladder']),
    );
    expect(jsonEncode(c['missing']), isNot(contains('세부 진행')));
  });

  group('HTTP 문', () {
    late RoomServer server;
    late ControlEndpoint endpoint;
    const token = 'testtoken0123456789abcdefghij';

    setUp(() async {
      server = RoomServer(assets: assets, port: 0);
      endpoint = ControlEndpoint(control: RoomControl(server), token: token);
      server.extraRoutes = endpoint.route;
      await server.start();
    });

    tearDown(() => server.stop());

    Future<(int, Map<String, dynamic>)> call(
      Map<String, dynamic> body, {
      String? auth = token,
    }) async {
      final http = HttpClient();
      try {
        final req = await http.postUrl(
          Uri.parse('http://127.0.0.1:${server.boundPort}/api/control'),
        );
        req.headers.contentType = ContentType.json;
        if (auth != null) req.headers.set('x-party-control', auth);
        req.write(jsonEncode(body));
        final res = await req.close();
        final text = await res.transform(utf8.decoder).join();
        return (res.statusCode, jsonDecode(text) as Map<String, dynamic>);
      } finally {
        http.close(force: true);
      }
    }

    test('토큰이 없으면 안 들여보낸다', () async {
      final (status, body) = await call({'command': 'status'}, auth: null);
      expect(status, 403);
      expect(body['ok'], isFalse);
    });

    test('틀린 토큰도 안 들여보낸다', () async {
      // 헤더 값은 Latin-1 만 실린다 — 한글을 넣으면 테스트가 서버가 아니라
      // 클라이언트에서 터진다(실제로 그렇게 한 번 헛짚었다).
      final (status, _) = await call({
        'command': 'status',
      }, auth: 'wrong-token');
      expect(status, 403);
    });

    test('맞으면 {ok, result} 봉투로 돌려준다', () async {
      final (status, body) = await call({'command': 'status'});
      expect(status, 200);
      expect(body['ok'], isTrue);
      expect((body['result'] as Map)['surface'], 'headless');
    });

    test('사용법 오류는 400, 못 하는 것은 409', () async {
      // CLI 의 exit code(64/1)가 이 구분을 그대로 쓴다.
      await call({
        'command': 'room',
        'args': {'action': 'new'},
      });
      final (usage, u) = await call({
        'command': 'room',
        'args': {'action': 'delete'},
      });
      expect(usage, 400);
      expect((u['error'] as Map)['kind'], 'usage');

      final (fail, f) = await call({'command': 'end'});
      expect(fail, 409);
      expect((f['error'] as Map)['kind'], 'failure');
    });

    test('깨진 본문에 500 을 뱉지 않는다', () async {
      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      final req = await http.postUrl(
        Uri.parse('http://127.0.0.1:${server.boundPort}/api/control'),
      );
      req.headers.set('x-party-control', token);
      // 본문도 마찬가지라 ASCII 로 깨뜨린다.
      req.write('{not json at all');
      final res = await req.close();
      await res.drain<void>();
      expect(res.statusCode, 400);
    });

    test('토큰이 비어 있으면 문을 아예 안 연다', () async {
      final bare = RoomServer(assets: assets, port: 0);
      bare.extraRoutes = ControlEndpoint(
        control: RoomControl(bare),
        token: '',
      ).route;
      await bare.start();
      addTearDown(bare.stop);

      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      final req = await http.postUrl(
        Uri.parse('http://127.0.0.1:${bare.boundPort}/api/control'),
      );
      req.write('{"command":"status"}');
      final res = await req.close();
      await res.drain<void>();
      expect(res.statusCode, 503, reason: '토큰 없는 제어 API 를 열어 두면 안 된다');
    });
  });
}
