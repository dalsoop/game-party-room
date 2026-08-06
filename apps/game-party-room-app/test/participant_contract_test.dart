import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:party_room_server/party_room_server.dart';

/// 참가자 SPA 와 서버 사이의 계약 검사.
///
/// 이 앱에서 실제로 파티 도중 터진 버그(`ws://` 하드코딩으로 https 방에서 소켓만 조용히
/// 차단됨)는 서버 테스트로는 절대 잡히지 않는다. 참가자 쪽 코드가 500줄짜리 HTML 안에
/// 있고 테스트가 하나도 없었기 때문이다. 브라우저를 띄우지 않고도 확인할 수 있는 것들을
/// 여기서 고정한다.

/// index.html 안의 인라인 `<script>` 본문만 뽑는다.
///
/// 스타일시트·마크업까지 싸잡아 검사하면 "정적 자산 참조"와 "런타임 주소 조립"을
/// 구분하지 못해, 배경 그림 한 장 넣는 것도 계약 위반으로 잡힌다.
String inlineScript(String html) => RegExp(
  r'<script(?![^>]*\ssrc=)[^>]*>([\s\S]*?)</script>',
).allMatches(html).map((m) => m.group(1) ?? '').join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String html;
  late String endpointsJs;
  late String clientJs;
  late List<String> gameIds;
  late Map<String, String> dartSources;

  setUpAll(() async {
    html = await rootBundle.loadString('assets/web/index.html');
    endpointsJs = await rootBundle.loadString('assets/web/js/endpoints.js');
    // 종목 목록은 index.html 이 실제로 불러오는 것에서 뽑는다. 여기 손으로
    // 적어 두면 게임을 늘렸을 때 새 종목만 조용히 검사에서 빠진다.
    gameIds = RegExp(
      r'src="/js/games/([a-z0-9_]+)\.js"',
    ).allMatches(html).map((m) => m.group(1)!).toList();
    clientJs = [
      for (final f in gameIds)
        await rootBundle.loadString('assets/web/js/games/$f.js'),
    ].join('\n');
    dartSources = {
      // 서버는 순수 Dart 패키지로 분리됐다 — 계약의 원천은 그쪽이다.
      for (final f
          in Directory('../../packages/party_room_server/lib/src')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')))
        f.path: f.readAsStringSync(),
    };
  });

  group('주소 하드코딩 금지', () {
    test('SPA 에 평문 ws:// 가 없다', () {
      // 실제 사고: https 터널로 방을 열면 브라우저가 혼합 콘텐츠로 막아
      // 페이지·입장은 되는데 소켓만 안 붙고 화면이 멈춘다.
      expect(
        html.contains('ws://'),
        isFalse,
        reason: 'WebSocket 주소는 Endpoints 가 페이지 프로토콜에서 파생해야 한다',
      );
      expect(
        html.contains('wss://'),
        isFalse,
        reason: '스킴을 고정하면 로컬(http) 방이 깨진다',
      );
    });

    test('스킴 파생 로직이 endpoints.js 에 있다', () {
      expect(endpointsJs.contains("location.protocol === 'https:'"), isTrue);
      expect(endpointsJs.contains('wss:'), isTrue);
      expect(endpointsJs.contains('ws:'), isTrue);
    });

    test('실행 코드가 서버 경로를 직접 문자열로 쓰지 않는다', () {
      // 한 곳에 모아두지 않으면 경로가 바뀔 때 조용히 404 가 난다.
      //
      // 검사 대상은 **실행 코드**다. 스타일시트의 url(...) 이나 마크업의 src=
      // 는 같은 출처의 고정 자산이라 JS 를 거칠 수 없고, 거칠 이유도 없다.
      // 문제가 되는 건 런타임에 주소를 조립하는 쪽이다.
      final runtime = [inlineScript(html), clientJs].join('\n');
      for (final path in ['/api/', '/img/', '/liar-image']) {
        expect(
          runtime.contains("'$path") || runtime.contains('"$path'),
          isFalse,
          reason: '$path 는 Endpoints 를 거쳐야 한다',
        );
      }
    });

    test('참가자 SPA 가 연결 모듈을 불러온다', () {
      expect(html.contains('src="/js/endpoints.js"'), isTrue);
      expect(html.contains('src="/js/room-socket.js"'), isTrue);
      expect(html.contains('src="/js/game-client.js"'), isTrue);
      // 서버가 아는 종목이 전부 실려 있어야 한다.
      expect(gameIds.toSet(), GameRegistry.ids.toSet());
    });
  });

  group('선택은 두 단계다', () {
    // 지목·투표는 되돌릴 수 없는 조작이다. 손가락이 미끄러진 것과 마음을 정한
    // 것을 구분해야 해서, 누르면 표시만 되고 전송은 확정 버튼이 맡는다.
    test('선택지를 누르는 것만으로 전송되지 않는다', () {
      final runtime = [inlineScript(html), clientJs].join('\n');
      expect(
        runtime.contains('onclick="send('),
        isFalse,
        reason: '선택지는 pickTarget/pickOption 으로 표시만 하고, 전송은 confirmPick 이 한다',
      );
    });

    test('고르는 화면마다 확정 버튼이 있다', () {
      // 밤 행동 · 처형 투표 · 라이어 지목 · 익명 투표.
      expect(RegExp('class="confirm"').allMatches(html).length, 4);
      expect(html.contains('onclick="confirmPick()"'), isTrue);
    });

    test('화면이 바뀌면 이전 선택이 남지 않는다', () {
      // 남겨 두면 다음 화면에서 엉뚱한 대상이 확정된다.
      final script = inlineScript(html);
      final show = script.substring(script.indexOf('function show('));
      final body = show.substring(0, show.indexOf('\n}'));
      expect(body.contains('pending = null'), isTrue);
      expect(body.contains('sentKey = null'), isTrue);
    });
  });

  group('씬 계약 — 서버가 보내는 씬을 SPA 가 안다', () {
    /// 서버 소스에서 `'scene': 'xxx'` 로 보내는 씬 이름을 전부 긁는다.
    Set<String> serverScenes() {
      final re = RegExp(r"'scene':\s*'([a-z_]+)'");
      return {
        for (final src in dartSources.values)
          for (final m in re.allMatches(src)) m.group(1)!,
      };
    }

    test('서버가 보내는 모든 씬에 화면이 있다', () {
      // 없으면 그 참가자는 아무 반응 없는 흰 화면을 본다 — 서버는 정상으로 보인다.
      final missing = <String>[];
      for (final scene in serverScenes()) {
        if (!html.contains('id="scene-$scene"')) missing.add(scene);
      }
      expect(missing, isEmpty, reason: '화면이 없는 씬: $missing');
    });

    test('서버가 보내는 모든 씬을 라우터가 처리한다', () {
      final unrouted = <String>[];
      for (final scene in serverScenes()) {
        // 종목 모듈이 씬 이름을 키(`mafia_night(msg) {`)로 등록한다.
        // 방 골격 씬(lobby)만 index.html 이 직접 처리한다.
        final registered =
            clientJs.contains('$scene(') || html.contains("'$scene'");
        if (!registered) unrouted.add(scene);
      }
      expect(unrouted, isEmpty, reason: '라우팅 없는 씬: $unrouted');
    });

    test('서버 씬 목록이 비어 있지 않다 (정규식이 죽지 않았는지)', () {
      // 이 테스트가 없으면 위 두 개가 공집합으로 항상 통과한다.
      expect(serverScenes().length, greaterThanOrEqualTo(8));
    });
  });

  group('메시지 계약 — 서버가 보내는 타입을 SPA 가 안다', () {
    test('개별 전송 메시지 타입을 SPA 가 처리한다', () {
      // 종목 접두사는 등록된 게임 id 에서 만든다 — 새 종목이 검사에서 빠지지 않게.
      final re = RegExp("'type':\\s*'((?:${gameIds.join('|')})_[a-z_]+)'");
      final serverTypes = {
        for (final src in dartSources.values)
          for (final m in re.allMatches(src)) m.group(1)!,
      };
      expect(serverTypes, isNotEmpty);

      final unhandled = <String>[];
      for (final t in serverTypes) {
        // 참가자가 서버로 보내는 타입(mafia_vote 등)은 여기 대상이 아니다 —
        // SPA 가 send() 로 쓰는 것도 같은 이름이라 존재 여부로만 본다.
        final known =
            html.contains("'$t'") ||
            clientJs.contains('$t(') ||
            clientJs.contains("'$t'");
        if (!known) unhandled.add(t);
      }
      expect(unhandled, isEmpty, reason: 'SPA 가 모르는 메시지: $unhandled');
    });
  });
}
