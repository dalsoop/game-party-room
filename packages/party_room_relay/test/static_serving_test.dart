import 'dart:convert';
import 'dart:io';

import 'package:party_room_relay/party_room_relay.dart';
import 'package:test/test.dart';

/// 릴레이가 **참가자 화면을 준다**.
///
/// 이게 이 서버의 존재 이유 절반이다. 다른 망에 있는 폰은 호스트에게서
/// 페이지를 받을 방법이 없다 — 릴레이가 https 로 주지 않으면 열 화면이
/// 아예 없다. 그리고 https 라야 브라우저가 secure context 를 열어 준다.
///
/// 나머지 절반은 **크기**다. 참가자 화면 자산이 6.3MB 고 그중 폰트 하나가
/// 2.45MB 다. 압축 없이 매 파티마다 사람 수만큼 내보내면, 실시간 프레임
/// (참가자당 2KB)이 아니라 **이쪽이** 릴레이 비용의 전부가 된다.
void main() {
  _healthz();

  late Directory base;
  late Directory web;
  late RelayServer relay;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('relay_root');
    web = await Directory('${base.path}/web').create();
    // 실제 SPA 처럼 — 잘 눌리는 것(html·js)과 이미 눌린 것(png)을 함께 둔다.
    await File(
      '${web.path}/index.html',
    ).writeAsString('<!doctype html>${'<p>파티룸</p>' * 400}');
    await File(
      '${web.path}/app.js',
    ).writeAsString('const x = 1;${'/* 주석 */' * 400}');
    await File('${web.path}/logo.png').writeAsBytes(List.filled(4096, 7));
    await File('${web.path}/inside.txt').writeAsString('여기 있어도 되는 것');
    // 뿌리 **바깥** — 여기 닿으면 탈출이다.
    await File('${base.path}/outside.txt').writeAsString('절대 나가면 안 되는 것');

    relay = RelayServer(port: 0, webRoot: web);
    await relay.start();
  });

  tearDown(() async {
    await relay.stop();
    await base.delete(recursive: true);
  });

  Future<HttpClientResponse> get(String path, {bool gzip = true}) async {
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final req = await http.getUrl(
      Uri.parse('http://127.0.0.1:${relay.actualPort}$path'),
    );
    // Dart 의 HttpClient 는 기본으로 gzip 을 요청하고 **투명하게 푼다**.
    // 그러면 압축이 됐는지 알 수 없으므로 헤더를 직접 다룬다.
    req.headers.set(
      HttpHeaders.acceptEncodingHeader,
      gzip ? 'gzip' : 'identity',
    );
    return req.close();
  }

  test('뿌리로 오면 참가자 화면을 준다', () async {
    final res = await get('/', gzip: false);
    expect(res.statusCode, 200);
    expect(res.headers.contentType?.mimeType, 'text/html');
    final body = await res.transform(utf8.decoder).join();
    expect(body, contains('파티룸'));
  });

  test('html·js 는 압축해서 보낸다', () async {
    final res = await get('/index.html');
    expect(res.headers.value('content-encoding'), 'gzip');

    final plain = await get('/index.html', gzip: false);
    final raw = plain.headers.contentLength;
    final zipped = res.headers.contentLength;
    expect(
      zipped,
      lessThan(raw ~/ 2),
      reason: '압축이 값어치를 못 한다 ($raw → $zipped)',
    );
  });

  test('이미 눌린 것은 다시 안 민다', () async {
    // png·jpg·woff2 를 또 밀면 CPU 만 쓰고 바이트는 안 준다.
    final res = await get('/logo.png');
    expect(res.headers.value('content-encoding'), isNull);
    await res.drain<void>();
  });

  test('gzip 을 못 받는다고 하면 안 보낸다', () async {
    final res = await get('/index.html', gzip: false);
    expect(res.headers.value('content-encoding'), isNull);
    await res.drain<void>();
  });

  test('자산은 오래 캐시하고 화면은 안 한다', () async {
    // 폰트·이미지는 파티마다 같은 것을 다시 받는다. html 은 판이 바뀌면
    // 곧바로 새것이어야 한다 — 낡은 화면이 새 서버에 붙으면 조용히 어긋난다.
    final html = await get('/index.html');
    expect(html.headers.value('cache-control'), contains('no-cache'));
    await html.drain<void>();

    final png = await get('/logo.png');
    expect(png.headers.value('cache-control'), contains('max-age'));
    await png.drain<void>();
  });

  group('경로 탈출', () {
    /// 요청 줄을 **날것 그대로** 보낸다.
    ///
    /// `HttpClient` 는 보내기 **전에** 경로를 정규화한다 — `/../x` 가 `/x` 로
    /// 바뀌어 나간다. 그래서 그걸로 쓴 탈출 테스트는 서버를 시험한 적이
    /// 없었다: 방어를 통째로 떼어 내도 통과했다(돌연변이가 살아남았다).
    /// 소켓에 직접 써야 서버가 진짜 `..` 를 본다.
    Future<String> raw(String target) async {
      final s = await Socket.connect('127.0.0.1', relay.actualPort);
      s.write(
        'GET $target HTTP/1.1\r\n'
        'Host: 127.0.0.1\r\n'
        'Connection: close\r\n\r\n',
      );
      await s.flush();
      final text = await s.cast<List<int>>().transform(latin1.decoder).join();
      await s.close();
      return text;
    }

    test('뿌리 밖으로 나가지 못한다', () async {
      for (final p in [
        '/../outside.txt',
        '/%2e%2e/outside.txt',
        '/%2e%2e%2foutside.txt',
        '/a/../../outside.txt',
        '/./../outside.txt',
        '/..%2f..%2foutside.txt',
      ]) {
        final res = await raw(p);
        expect(
          res.split('\r\n').first,
          isNot(contains('200')),
          reason: '$p 로 200 이 나왔다',
        );
        expect(
          res,
          isNot(contains('절대 나가면 안 되는 것')),
          reason: '$p 로 뿌리 밖 파일 내용이 나갔다',
        );
      }
    });

    test('뿌리 안의 파일은 그대로 준다', () async {
      // 위 테스트가 "무엇을 달라 해도 404" 라서 통과하는 것이 아님을
      // 여기서 못 박는다.
      final res = await get('/inside.txt', gzip: false);
      expect(res.statusCode, 200);
      await res.drain<void>();
    });

    // HTTP 로는 이 판정을 뚫는 요청을 **만들 수가 없다** — Dart 의
    // `HttpServer` 가 `..` 를 서버가 받기 전에 지우기 때문이다(소켓에 날것으로
    // 써도 그렇다. 실제로 확인했다). 그래서 위의 통합 테스트만으로는 방어가
    // 도는지 알 수 없었다: 방어를 통째로 떼어 내도 전부 통과했다.
    //
    // 판정을 함수로 꺼내 직접 먹인다. HTTP 스택을 바꾸거나 `%2F` 를 풀어
    // 주게 되는 날, 여기가 먼저 빨개진다.
    group('판정 자체', () {
      test('뿌리 밖을 가리키면 거절한다', () {
        for (final name in [
          '../outside.txt',
          '../../etc/passwd',
          'a/../../outside.txt',
          './../outside.txt',
          '..',
          '../',
        ]) {
          expect(
            RelayServer.resolveInside(web, name),
            isNull,
            reason: '"$name" 이 뿌리 밖으로 나갔다',
          );
        }
      });

      test('뿌리 자체를 파일로 내주지 않는다', () {
        expect(RelayServer.resolveInside(web, ''), isNull);
        expect(RelayServer.resolveInside(web, '.'), isNull);
      });

      test('뿌리 안이면 그 파일을 준다', () {
        for (final name in ['index.html', 'js/app.js', 'img/a/b.png']) {
          final f = RelayServer.resolveInside(web, name);
          expect(f, isNotNull, reason: '"$name" 은 정상 경로인데 막혔다');
          expect(f!.path, endsWith(name));
        }
      });
    });
  });

  test('참가자 화면이 없으면 랑데부만 한다', () async {
    final bare = RelayServer(port: 0);
    await bare.start();
    addTearDown(bare.stop);
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final res = await (await http.getUrl(
      Uri.parse('http://127.0.0.1:${bare.actualPort}/'),
    )).close();
    await res.drain<void>();
    expect(res.statusCode, 404);
  });
}

/// 살아 있나 · 뭐가 돌고 있나.
///
/// 이게 없으면 "지금 뭐가 돌고 있지" 에 답할 수 없고, 그 질문은 **뭔가 이상할
/// 때** 나온다 — 그때 답을 못 하면 되돌릴 지점도 못 찾는다.
void _healthz() {
  group('healthz', () {
    late Directory web;
    late RelayServer relay;

    setUp(() async {
      web = await Directory.systemTemp.createTemp('relay_h');
      await File('${web.path}/index.html').writeAsString('<p>화면</p>');
      relay = RelayServer(port: 0, webRoot: web, version: '1.2.3-abcdef');
      await relay.start();
    });

    tearDown(() async {
      await relay.stop();
      await web.delete(recursive: true);
    });

    Future<Map<String, dynamic>> health() async {
      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      final res = await (await http.getUrl(
        Uri.parse('http://127.0.0.1:${relay.actualPort}/healthz'),
      )).close();
      return jsonDecode(await res.transform(utf8.decoder).join())
          as Map<String, dynamic>;
    }

    test('무엇이 돌고 있는지 말한다', () async {
      final h = await health();
      expect(h['ok'], isTrue);
      expect(h['version'], '1.2.3-abcdef');
      expect(h['hosts'], 0);
      expect(h['uptimeSeconds'], isA<int>());
    });

    test('참가자 화면의 지문을 낸다', () async {
      // 화면은 이미지에 구워져 있어서, 앱이 화면을 고쳐도 이미지를 다시
      // 굽지 않으면 참가자는 조용히 옛 화면을 받는다. 지문이 밖으로 나와야
      // 호스트가 먼저 알아챈다.
      final before = (await health())['assets'] as String;
      expect(before, hasLength(16));

      await relay.stop();
      await File('${web.path}/새화면.js').writeAsString('console.log(1)');
      await relay.start();

      expect(
        (await health())['assets'],
        isNot(before),
        reason: '화면이 바뀌었는데 지문이 그대로다',
      );
    });

    test('화면이 없으면 지문도 없다', () async {
      final bare = RelayServer(port: 0);
      await bare.start();
      addTearDown(bare.stop);
      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      final res = await (await http.getUrl(
        Uri.parse('http://127.0.0.1:${bare.actualPort}/healthz'),
      )).close();
      final h = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
      expect(h['assets'], isNull);
      expect(h['ok'], isTrue, reason: '랑데부만 하는 모드도 살아 있는 것은 맞다');
    });
  });
}
