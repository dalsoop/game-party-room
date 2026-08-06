import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/server/mc_service.dart';
import 'package:llm_cli_runtime/llm_cli_runtime.dart';

/// LLM 사회자의 안전 계약.
///
/// 사회자는 **참가자가 이미 아는 사실만** 말한다. 게임 모듈이 이벤트에 실어
/// 보내는 payload 에는 역할표·라이어 제시어처럼 게임을 즉시 끝내는 정보가
/// 들어 있는데, 그걸 프롬프트에 담으면 모델이 언젠가 흘린다.
/// 여기서 "프롬프트에 비밀이 없다" 를 못박는다.
void main() {
  // 프롬프트 생성기는 private 이라 narrate 경로로는 네트워크가 필요하다.
  // 대신 McService 가 노출하는 동작으로 확인할 수 있게, 테스트는 프롬프트
  // 문자열을 직접 만드는 공개 헬퍼를 쓴다.
  String? beat(String event, Map<String, dynamic> data) =>
      McService.beatForTest(event, data);

  group('비밀 누설 금지', () {
    test('마피아 시작 프롬프트에 역할표가 없다', () {
      final text = beat('mafia_started', {
        'players': 6,
        'roles': {'지환': '마피아', '민서': '시민', '태윤': '의사'},
      });
      expect(text, isNotNull);
      expect(text, contains('6'));
      for (final leak in ['마피아', '의사', '지환', '민서', '태윤']) {
        // '마피아 게임' 이라는 종목명은 허용 — 역할 배정 정보만 금지한다.
        if (leak == '마피아') continue;
        expect(text, isNot(contains(leak)), reason: '$leak 이(가) 샜다');
      }
      expect(
        RegExp(r'지환|민서|태윤').hasMatch(text!),
        isFalse,
        reason: '참가자 이름과 역할이 붙어 나가면 안 된다',
      );
    });

    test('라이어 시작 프롬프트에 제시어와 라이어가 없다', () {
      final text = beat('liar_started', {
        'liar': '민서',
        'category': '음식',
        'word': '치킨',
      });
      expect(text, isNotNull);
      for (final leak in ['민서', '치킨', '음식']) {
        expect(text, isNot(contains(leak)), reason: '$leak 이(가) 샜다');
      }
    });

    test('공개된 사실은 그대로 전달한다', () {
      final day = beat('mafia_phase', {
        'phase': 'day',
        'round': 2,
        'announcement': '지난 밤, 태윤 님이 희생되었습니다.',
      });
      // 낮 발표는 이미 전원에게 브로드캐스트된 문구다 — 넣어야 사회자가 말한다.
      expect(day, contains('태윤 님이 희생되었습니다'));

      final marble = beat('marble_done', {'winner': '서연', 'rank': 1});
      expect(marble, contains('서연'));
    });

    test('사회자가 말할 것이 없는 이벤트는 null', () {
      expect(beat('mafia_night_progress', {'done': 1, 'total': 3}), isNull);
      expect(beat('poll_progress', {'voted': 2, 'players': 5}), isNull);
      expect(beat('알수없는이벤트', {}), isNull);
    });
  });

  group('실제 호출 (OpenAI 호환 목 서버)', () {
    late HttpServer server;
    late String base;
    final requests = <Map<String, dynamic>>[];

    setUp(() async {
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}/v1';
      server.listen((req) async {
        final body = await utf8.decodeStream(req);
        requests.add(jsonDecode(body) as Map<String, dynamic>);
        // 느린 제공자 흉내 — 경로가 비동기인지도 함께 본다.
        req.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': '"밤이 내려앉았습니다."'},
                },
              ],
            }),
          );
        await req.response.close();
      });
    });

    tearDown(() async => server.close(force: true));

    test('요청 규격이 OpenAI 호환이고, 응답의 따옴표는 벗겨서 준다', () async {
      final mc = McService(
        source: McHttpSource(
          baseUrl: base,
          model: 'mock-model',
          apiKey: 'sk-test',
        ),
        persona: McPersona.hype,
      );
      final line = await mc.narrate('mafia_phase', {
        'phase': 'night',
        'round': 1,
      });

      expect(line, '밤이 내려앉았습니다.', reason: '앞뒤 따옴표는 벗겨야 한다');
      expect(requests, hasLength(1));
      final r = requests.single;
      expect(r['model'], 'mock-model');
      expect(r['max_tokens'], 120);
      final messages = r['messages'] as List;
      expect((messages.first as Map)['role'], 'system');
      expect(
        (messages.first as Map)['content'],
        contains('과장되게 신난'),
        reason: '고른 성격이 시스템 프롬프트에 실려야 한다',
      );
      expect((messages.last as Map)['content'], contains('1일차 밤'));
    });

    test('말할 것이 없는 이벤트는 호출조차 하지 않는다', () async {
      final mc = McService(
        source: McHttpSource(baseUrl: base, model: 'm'),
      );
      final line = await mc.narrate('mafia_night_progress', {'done': 1});
      expect(line, isNull);
      expect(requests, isEmpty, reason: '쓸데없는 토큰을 태우면 안 된다');
    });

    test('서버가 죽어 있으면 조용히 null 이고 잠시 쉰다', () async {
      final mc = McService(
        source: const McHttpSource(
          baseUrl: 'http://127.0.0.1:1/v1', // 아무도 안 듣는 포트
          model: 'm',
        ),
      );
      final line = await mc.narrate('mafia_phase', {
        'phase': 'night',
        'round': 1,
      });
      expect(line, isNull, reason: '실패가 게임을 막으면 안 된다');
      expect(mc.muted, isTrue, reason: '연달아 타임아웃을 기다리지 않는다');
    });
  });

  group('터미널 구독 (실제 CLI)', () {
    // 이 맥에 로그인된 CLI 를 실제로 부른다. 없으면 건너뛴다 —
    // 구독·로그인 상태에 의존하므로 CI 에서는 자동으로 skip 된다.
    test('설치된 CLI 로 사회자 한 문장을 받아온다', () async {
      final runtime = LlmCliRuntime();
      final backend = runtime.available.isEmpty
          ? null
          : runtime.available.first;
      if (backend == null) {
        markTestSkipped('설치된 LLM CLI 없음');
        return;
      }

      final mc = McService(
        source: McCliSource(backendId: backend.id, runtime: runtime),
        persona: McPersona.classic,
      );
      final line = await mc.narrate('mafia_phase', {
        'phase': 'day',
        'round': 2,
        'announcement': '지난 밤, 태윤 님이 희생되었습니다.',
      });

      if (line == null) {
        // 잔액 소진·미로그인 등은 기능 결함이 아니다 — 조용히 넘어가는 것이
        // 설계대로인지만 확인하고 끝낸다.
        expect(mc.muted, isTrue, reason: '실패했으면 잠시 쉬어야 한다');
        markTestSkipped('${backend.id} 응답 없음(로그인·잔액 확인)');
        return;
      }
      expect(line, isNotEmpty);
      expect(line, isNot(contains('\n')), reason: '한 줄로 정리돼야 한다');
      expect(line.startsWith('"'), isFalse, reason: '따옴표는 벗겨야 한다');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('시스템 프롬프트', () {
    test('모든 성격이 추측 금지와 길이 제한을 담는다', () {
      for (final p in McPersona.values) {
        expect(p.systemPrompt, contains('추측'));
        expect(p.systemPrompt, contains('문장'));
        expect(p.label, isNotEmpty);
      }
    });
  });
}
