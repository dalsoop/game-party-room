import 'dart:io';
import 'package:game_party_room_app/server/app/bundle_assets.dart';
import 'package:party_room_server/party_room_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // rootBundle 을 쓰므로 바인딩이 필요하다.
  TestWidgetsFlutterBinding.ensureInitialized();

  const assets = WebAssets(BundleAssetSource());

  group('번들 자산 서빙', () {
    test('참가자 SPA 스크립트를 연다', () async {
      // index.html 이 <script src="/js/…"> 로 부르는 경로 — 막히면 참가자 화면이
      // 통째로 죽는다(연결 코드가 이 파일들에 있다).
      for (final name in ['endpoints.js', 'room-socket.js']) {
        final res = await assets.serve('js/$name');
        expect(res, isNotNull, reason: '$name 라우팅 누락');
        expect(res!.statusCode, 200, reason: '$name 를 찾지 못함');
        expect(res.headers['content-type'], contains('javascript'));
      }
    });

    test('스크립트 경로 탈출을 막는다', () async {
      for (final bad in [
        'js/../../secret.js',
        'js/nested/x.js',
        'js/x.dart',
        'js/',
      ]) {
        final res = await assets.serve(bad);
        expect(res?.statusCode, 404, reason: '$bad 가 열렸다');
      }
    });

    test('이미지 경로 탈출을 막는다', () async {
      for (final bad in ['img/../x.jpg', 'img/A.jpg', 'img/x.svg']) {
        final res = await assets.serve(bad);
        expect(res?.statusCode, 404, reason: '$bad 가 열렸다');
      }
    });

    test('모르는 경로는 null 을 준다 (방 서버가 이어받도록)', () async {
      // null 을 안 주면 /api/join 같은 방 API 가 자산 핸들러에 먹힌다.
      expect(await assets.serve('api/join'), isNull);
      expect(await assets.serve('ws'), isNull);
      expect(await assets.serve('liar-image'), isNull);
    });

    test('빈 경로는 index.html 이다', () async {
      final res = await assets.serve('');
      expect(res?.statusCode, 200);
      expect(res!.headers['content-type'], contains('text/html'));
    });
  });
  _sectionTabAffordance();
  _imagesDontCrowdContent();
}

/// 참가자 화면의 칸 탭 — 실제 브라우저에서 걸린 것을 잠근다.
///
/// 판이 몇 번 돌면 탭 줄이 넘치고, 선택된 칸을 보이게 스크롤하면서 맨 왼쪽의
/// '전체' 가 화면 밖으로 나갔다(실측 left=-222px). 하필 그게 **끝난 판을 보고
/// 있을 때 유일하게 쓸 수 있는 칸**이라, 스크롤바까지 숨겨 둔 탓에 닿을
/// 방법이 없었다. sticky 로 고정한다.
void _sectionTabAffordance() {
  group('칸 탭', () {
    late String html;
    late String chatJs;

    setUpAll(() {
      html = File('assets/web/index.html').readAsStringSync();
      chatJs = File('assets/web/js/chat.js').readAsStringSync();
    });

    test('전체 칸은 밀려나지 않게 고정돼 있다', () {
      expect(html, contains('button.sectab:first-child'));
      expect(
        RegExp(
          r'button\.sectab:first-child\s*\{[^}]*position:\s*sticky',
        ).hasMatch(html),
        isTrue,
        reason: '전체 탭이 스크롤로 화면 밖에 나가면 쓸 수 있는 칸에 닿을 길이 없다',
      );
    });

    test('끝난 판에서는 갈 곳을 알려준다', () {
      // 못 쓰는 이유만 말하고 끝내면 어디로 가야 할지 모른다.
      expect(chatJs, contains('[전체]에서 이야기하세요'));
    });

    test('화면이 한계값을 지어내지 않는다', () {
      // 서버가 내려 준 값만 쓴다 — 양쪽에 박아 두면 한쪽이 거짓말을 한다.
      expect(chatJs, contains('limits.uploadBytes'));
      expect(chatJs, contains('limits.chatTextLength'));
      expect(chatJs.contains('30 * 1024 * 1024'), isFalse);
    });
  });
}

/// 그림이 내용을 밀어내지 않는다.
///
/// 실측(폰 크기 뷰포트 561px)에서 역할 화면은 전체 586px 중 498px가 카드
/// 아트였다 — 화면을 넘겨서 정작 **"이 화면을 절대 다른 사람에게 보여주지
/// 마세요"** 경고가 스크롤 밖으로 밀렸다. 투표 화면도 58%가 그림이라 지목
/// 대상 목록이 밀렸다. 장식이 내용을 가리면 장식이 아니라 방해다.
void _imagesDontCrowdContent() {
  group('그림 크기', () {
    late String html;
    setUpAll(() => html = File('assets/web/index.html').readAsStringSync());

    test('씬 그림에 세로 상한이 있다', () {
      // width:100% 만 있으면 화면 높이와 무관하게 그려진다.
      expect(
        RegExp(r'\.banner img\s*\{[^}]*max-height:\s*\d+vh').hasMatch(html),
        isTrue,
        reason: '.banner img 에 뷰포트 기준 상한이 없다',
      );
    });

    test('역할 카드가 세로에 따라 줄어든다', () {
      expect(
        RegExp(r'\.rolecard\s*\{[^}]*max-width:\s*min\([^)]*vh').hasMatch(html),
        isTrue,
        reason: '카드 밑의 역할 이름·경고가 화면 밖으로 밀린다',
      );
    });

    test('제시어·승리 그림도 상한이 있다', () {
      for (final cls in ['.wordimg', '.winimg']) {
        expect(
          RegExp('\\$cls\\s*\\{[^}]*max-height:\\s*\\d+vh').hasMatch(html),
          isTrue,
          reason: '$cls 에 상한이 없다',
        );
      }
    });
  });
}
