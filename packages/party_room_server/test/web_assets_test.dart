import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';

import 'support/memory_assets.dart';

/// 참가자 폰이 받는 정적 자산 — 화이트리스트가 새면 앱 번들 전체가 열린다.
///
/// 방 토큰만 알면 누구나 `GET /js/...`, `GET /img/...` 를 두드릴 수 있다.
/// 경로는 그대로 파일 경로가 되고, 화이트리스트가 느슨하면 `../` 한 방으로
/// 앱 안의 다른 자산·설정까지 읽힌다. 이 테스트는 그 문을 실제로 민다.
void main() {
  // 정상 자산 — 경로·content-type·cache-control 이 계약이다.
  final assets = MemoryAssets(
    strings: {
      'assets/web/index.html': '<html>ok</html>',
      'assets/web/js/app.js': '/* app */',
      'assets/web/js/games/ladder.js': '/* ladder */',
    },
    bytes: {
      'assets/fonts/NEXONLv2Gothic-Regular.ttf': [0x00, 0x01, 0x02],
      'assets/web/img/cover.jpg': [0xFF, 0xD8, 0xFF],
      'assets/web/img/logo_1.png': [0x89, 0x50, 0x4E, 0x47],
    },
  );
  final web = WebAssets(assets);

  group('정상 경로 서빙', () {
    test('빈 경로와 index.html 은 HTML 을 준다', () async {
      // 참가자가 방 URL 만 열면 path 가 비어 온다. index 로 떨어지지 않으면
      // 폰에 빈 화면만 뜬다.
      for (final path in ['', 'index.html']) {
        final res = await web.serve(path);
        expect(res, isNotNull, reason: 'path="$path" 가 자산으로 안 잡혔다');
        expect(res!.statusCode, 200);
        expect(res.headers['content-type'], 'text/html; charset=utf-8');
        expect(await res.readAsString(), '<html>ok</html>');
      }
      expect(
        assets.stringLoads,
        containsAll(['assets/web/index.html', 'assets/web/index.html']),
      );
    });

    test('js/*.js 는 스크립트 + no-store 로 나간다', () async {
      // 게임 중 JS 를 고치는 일이 잦다. 캐시가 붙으면 새로고침해도 옛
      // 스크립트가 남아서 "고쳤는데 안 바뀌어요" 가 된다.
      final res = await web.serve('js/app.js');
      expect(res, isNotNull);
      expect(res!.statusCode, 200);
      expect(
        res.headers['content-type'],
        'application/javascript; charset=utf-8',
      );
      expect(res.headers['cache-control'], 'no-store');
      expect(await res.readAsString(), '/* app */');
      expect(assets.stringLoads, contains('assets/web/js/app.js'));
    });

    test('js/games/*.js 한 단계까지는 연다', () async {
      // 종목 스크립트는 games/ 아래 한 단. 여기까지는 정상 계약이다.
      final res = await web.serve('js/games/ladder.js');
      expect(res, isNotNull);
      expect(res!.statusCode, 200);
      expect(
        res.headers['content-type'],
        'application/javascript; charset=utf-8',
      );
      expect(res.headers['cache-control'], 'no-store');
      expect(await res.readAsString(), '/* ladder */');
      expect(assets.stringLoads, contains('assets/web/js/games/ladder.js'));
    });

    test('img/*.jpg · img/*.png 는 그림 + no-cache 로 나간다', () async {
      // 파일 이름에 판번호가 없다. max-age 를 걸면 지난 파티 그림이 남는다.
      // no-cache 로 "매번 물어보되, 한 판 도는 동안은 메모리에 둔다".
      final jpg = await web.serve('img/cover.jpg');
      expect(jpg, isNotNull);
      expect(jpg!.statusCode, 200);
      expect(jpg.headers['content-type'], 'image/jpeg');
      expect(jpg.headers['cache-control'], 'no-cache');
      expect(await jpg.read().expand((c) => c).toList(), [0xFF, 0xD8, 0xFF]);

      final png = await web.serve('img/logo_1.png');
      expect(png, isNotNull);
      expect(png!.statusCode, 200);
      expect(png.headers['content-type'], 'image/png');
      expect(png.headers['cache-control'], 'no-cache');
      expect(await png.read().expand((c) => c).toList(), [
        0x89,
        0x50,
        0x4E,
        0x47,
      ]);
    });

    test('fonts/nexon.ttf 는 폰트 + 하루 캐시로 나간다', () async {
      // 폰트는 파티마다 안 바뀐다. 매 접속마다 받으면 모바일 데이터가 아깝다.
      final res = await web.serve('fonts/nexon.ttf');
      expect(res, isNotNull);
      expect(res!.statusCode, 200);
      expect(res.headers['content-type'], 'font/ttf');
      expect(res.headers['cache-control'], 'max-age=86400');
      expect(await res.read().expand((c) => c).toList(), [0x00, 0x01, 0x02]);
      expect(
        assets.byteLoads,
        contains('assets/fonts/NEXONLv2Gothic-Regular.ttf'),
      );
    });
  });

  group('경로 탈출·화이트리스트 우회', () {
    // 아래 케이스는 "막혔다" 를 못으로 박는다. 만약 어느 하나가 200 을
    // 주거나 load* 에 이상한 번들 경로가 찍히면 화이트리스트가 샌 것이다 —
    // 그때는 이 테스트를 고치지 말고 구현을 의심한다(이번 작업은 보고만).

    Future<void> expectBlocked(
      String path, {
      required String why,
      bool mustBeNotFound = true,
    }) async {
      final beforeStrings = assets.stringLoads.length;
      final beforeBytes = assets.byteLoads.length;
      final res = await web.serve(path);

      if (mustBeNotFound) {
        // js/·img/ 접두를 탄 뒤 이름이 거절되면 404. 자산이 아예 아니면 null.
        // 둘 다 "내용을 안 준다" 는 뜻이다. 200 만 아니면 된다.
        expect(
          res == null || res.statusCode == 404,
          isTrue,
          reason: '$why — path="$path" 가 status=${res?.statusCode} 로 열렸다',
        );
        if (res != null) {
          expect(
            res.statusCode,
            isNot(200),
            reason: '$why — path="$path" 가 200 으로 열렸다',
          );
        }
      }

      // 화이트리스트가 거절했다면 load 자체를 부르면 안 된다.
      // (거절 전에 load 를 부르는 구현이면 여기가 터지고, 그게 곧 구멍 신호다.)
      final newStrings = assets.stringLoads.sublist(beforeStrings);
      final newBytes = assets.byteLoads.sublist(beforeBytes);
      for (final p in [...newStrings, ...newBytes]) {
        expect(
          p.contains('..'),
          isFalse,
          reason: '$why — load 경로에 ".." 가 실렸다: $p (path="$path")',
        );
        // 번들 루트 밖으로 나가려는 절대·상위 경로 흔적.
        expect(
          p.startsWith('/') || p.contains('\\'),
          isFalse,
          reason: '$why — load 경로가 절대/윈도 경로처럼 보인다: $p',
        );
      }
    }

    test('../ 로 상위 디렉터리를 못 짚는다', () async {
      // 가장 흔한 경로 탈출. 화이트리스트 정규식이 이름만 보면 여기서 막혀야 한다.
      await expectBlocked('js/../index.html', why: 'js 경로에서 ../ 탈출');
      await expectBlocked('js/games/../../index.html', why: 'games 아래 ../ 탈출');
      await expectBlocked('img/../js/app.js', why: 'img 경로에서 ../ 탈출');
      await expectBlocked(
        'js/../../assets/fonts/NEXONLv2Gothic-Regular.ttf',
        why: 'js 로 폰트 파일 탈출',
      );
      // **확장자까지 맞춘 탈출** — 화이트리스트가 느슨해지면 이 모양이
      // 제일 먼저 뚫린다. 위의 것들은 `.js` 로 안 끝나서, `.js` 검사만
      // 헐거워져도 안 걸린다(실제로 정규식을 느슨하게 해 보니 이 경로만
      // 로더까지 갔다 — 목이 아니라 파일시스템이었으면 읽혔다).
      await expectBlocked('js/../secret.js', why: 'js 확장자를 맞춘 ../ 탈출');
      await expectBlocked('js/../../secret.js', why: 'js 확장자를 맞춘 두 단계 탈출');
      await expectBlocked(
        'js/games/../../../secret.js',
        why: 'games 아래에서 확장자를 맞춘 탈출',
      );
      await expectBlocked('img/../cover.jpg', why: 'img 확장자를 맞춘 ../ 탈출');
    });

    test('인코딩된 슬래시(..%2f) 도 이름이 안 된다', () async {
      // HTTP 계층이 이미 디코드해 넘기면 `../` 와 같고, 그대로 오면 리터럴
      // `%2f` 가 이름에 들어 정규식에 걸린다. 어느 쪽이든 열리면 안 된다.
      await expectBlocked('js/..%2findex.html', why: 'js 에 %2f 인코딩 탈출');
      await expectBlocked('img/..%2fjs%2fapp.js', why: 'img 에 %2f 인코딩 탈출');
      await expectBlocked('js/%2e%2e/%2e%2e/secret', why: '이중 인코딩 형태');
    });

    test('절대 경로는 자산으로 안 잡히거나 거절된다', () async {
      // `/etc/passwd` 같은 값이 path 로 들어오면 어느 접두에도 안 걸려 null
      // (방 서버가 이어받음). 절대 경로가 200 으로 열리면 치명적이다.
      final absolute = await web.serve('/etc/passwd');
      expect(absolute, isNull, reason: '절대 경로가 자산 응답으로 나왔다');

      await expectBlocked('js//etc/passwd', why: 'js 접두 + 절대 형태');
      await expectBlocked('js/C:/Windows/win.ini', why: '윈도 드라이브 경로');
    });

    test('js/games 보다 깊은 중첩은 거절한다', () async {
      // 계약은 games/ 한 단계. a/b/c 를 열면 임의 트리를 읽는 것과 같다.
      await expectBlocked('js/a/b/c.js', why: 'js 아래 임의 중첩');
      await expectBlocked('js/games/nested/deep.js', why: 'games 아래 두 단계');
      await expectBlocked('img/sub/cover.jpg', why: 'img 아래 하위 디렉터리');
    });

    test('확장자 바꿔치기는 거절한다', () async {
      // .js 가 아닌 것을 js/ 로, .png 가 아닌 것을 img/ 로 열면 번들의
      // 설정·원본 자산이 나간다.
      await expectBlocked('js/app.txt', why: 'js 가 아닌 확장자');
      await expectBlocked('js/app.js.map', why: 'source map 위장');
      await expectBlocked('js/app.html', why: 'html 을 js 경로로');
      await expectBlocked('img/cover.gif', why: '허용 안 된 그림 확장자');
      await expectBlocked('img/cover.jpeg', why: 'jpeg 는 jpg 만 받는다');
      await expectBlocked('img/cover.webp', why: 'webp 는 화이트리스트 밖');
      await expectBlocked('img/cover.png.exe', why: '이중 확장자');
    });

    test('대문자·혼용 이름은 거절한다', () async {
      // 정규식은 [a-z0-9_]. 대문자를 열어 주면 케이스만 다른 실파일·다른
      // 플랫폼 경로가 새어 나올 수 있다. 폰트 공개 이름도 소문자 고정이다.
      await expectBlocked('js/App.js', why: 'JS 파일명 대문자');
      await expectBlocked('js/games/Ladder.js', why: 'games 파일명 대문자');
      await expectBlocked('img/Cover.jpg', why: '그림 파일명 대문자');
      await expectBlocked('img/cover.JPG', why: '확장자 대문자');
      await expectBlocked('img/cover.PNG', why: 'PNG 대문자');

      // 접두 자체가 다르면 자산이 아니라 null — 방 서버 몫.
      expect(await web.serve('JS/app.js'), isNull);
      expect(await web.serve('IMG/cover.jpg'), isNull);
      expect(await web.serve('Fonts/nexon.ttf'), isNull);
      expect(await web.serve('fonts/NEXON.TTF'), isNull);
      expect(await web.serve('fonts/other.ttf'), isNull);
    });

    test('널바이트·공백·특수문자는 거절한다', () async {
      // 일부 스택은 널에서 문자열을 자른다. 공백·쿼리 흉내는 이름 위장이다.
      await expectBlocked('js/app\x00.js', why: '널바이트가 끼인 js 이름');
      await expectBlocked('img/co\x00ver.jpg', why: '널바이트가 끼인 그림 이름');
      await expectBlocked('js/app .js', why: '공백이 있는 이름');
      await expectBlocked('js/app.js?x=1', why: '쿼리처럼 보이는 접미');
      await expectBlocked('js/app.js#frag', why: '프래그먼트처럼 보이는 접미');
      await expectBlocked('js/app;js', why: '세미콜론 위장');
      await expectBlocked('img/cover.jpg%00.png', why: '인코딩 널 + 확장자 위장');
    });

    test('거절된 js/img 이름은 404 이고 load 를 부르지 않는다', () async {
      // "bad asset" 404 와 "자산 아님 null" 을 가르는 지점. 접두는 맞지만
      // 이름이 틀리면 404 를 주고, 원본 load 는 한 번도 안 해야 한다.
      final beforeS = assets.stringLoads.length;
      final beforeB = assets.byteLoads.length;

      final badJs = await web.serve('js/../secret.js');
      expect(badJs, isNotNull, reason: 'js/ 접두인데 null 이면 방 서버로 넘어간다');
      expect(badJs!.statusCode, 404);
      expect(await badJs.readAsString(), 'bad asset');

      final badImg = await web.serve('img/../secret.jpg');
      expect(badImg, isNotNull);
      expect(badImg!.statusCode, 404);
      expect(await badImg.readAsString(), 'bad asset');

      expect(
        assets.stringLoads.length,
        beforeS,
        reason: '거절된 js 이름인데 loadString 이 호출됐다',
      );
      expect(
        assets.byteLoads.length,
        beforeB,
        reason: '거절된 img 이름인데 loadBytes 가 호출됐다',
      );
    });
  });

  group('자산 없음은 404', () {
    test('loadString 이 null 이면 500 이 아니라 404', () async {
      // 번들에서 파일이 빠졌을 때 500 을 주면 폰·프록시가 재시도 폭풍을
      // 일으키고, 호스트는 "서버가 죽었다" 로 읽는다. 없는 자원은 404.
      final empty = MemoryAssets();
      final bare = WebAssets(empty);

      final index = await bare.serve('index.html');
      expect(index, isNotNull);
      expect(index!.statusCode, 404, reason: '없는 index 가 ${index.statusCode}');
      expect(index.statusCode, isNot(500));

      final js = await bare.serve('js/app.js');
      expect(js, isNotNull);
      expect(js!.statusCode, 404, reason: '없는 js 가 ${js.statusCode}');
      expect(js.statusCode, isNot(500));
      expect(await js.readAsString(), 'no asset');
    });

    test('loadBytes 가 null 이면 그림·폰트도 404', () async {
      final empty = MemoryAssets();
      final bare = WebAssets(empty);

      final img = await bare.serve('img/cover.jpg');
      expect(img, isNotNull);
      expect(img!.statusCode, 404);
      expect(img.statusCode, isNot(500));
      expect(await img.readAsString(), 'no asset');

      final font = await bare.serve('fonts/nexon.ttf');
      expect(font, isNotNull);
      expect(font!.statusCode, 404);
      expect(font.statusCode, isNot(500));
      expect(await font.readAsString(), 'no font');
    });
  });

  group('자산이 아닌 경로', () {
    test('모르는 경로는 null 을 돌려 방 서버가 이어받는다', () async {
      // null 이 계약이다. 404 를 여기서 닫아 버리면 /api/join·/ws·/file/…
      // 이 전부 자산 404 에 먹힌다.
      final paths = [
        'api/join',
        'ws',
        'file/abc',
        'liar-image',
        'robots.txt',
        'favicon.ico',
        'css/app.css',
        'games/ladder.js', // js/ 접두 없음
        'nexon.ttf', // fonts/ 접두 없음
        'cover.jpg',
      ];
      for (final path in paths) {
        final res = await web.serve(path);
        expect(res, isNull, reason: 'path="$path" 가 자산 응답으로 잡혔다');
      }
    });
  });
}
