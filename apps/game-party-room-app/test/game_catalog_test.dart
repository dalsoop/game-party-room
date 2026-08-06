import 'package:party_room_server/party_room_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/games/game_catalog.dart';
import 'package:game_party_room_app/settings/game_rule_spec.dart';

void main() {
  group('되살린 판의 상태 문구', () {
    // 상태 줄은 이벤트가 지날 때만 갱신된다. 재시작 직후에는 아무 이벤트도
    // 안 지나가므로, 종목마다 자기 상태에서 문구를 만들어야 한다 — 예전에는
    // 마피아만 있었고 나머지 넷은 판이 돌고 있는데도 빈 칸이었다.
    test('모든 종목이 되살린 판의 문구를 만든다', () {
      for (final e in GameCatalog.all) {
        final module = GameRegistry.create(e.id)!;
        final line = GameCatalog.restoredStatusFor(module);
        expect(line, isNotNull, reason: '${e.title} 은 재시작하면 상태 줄이 빈 칸이 된다');
        expect(line, isNotEmpty, reason: '${e.title} 의 문구가 비어 있다');
      }
    });

    test('갓 만든 모듈로도 터지지 않는다', () {
      // 복원 직후 모듈은 판이 한 번도 안 돈 상태일 수 있다(참가자 0명 등).
      // 여기서 예외가 나면 앱이 아예 안 열린다.
      for (final e in GameCatalog.all) {
        expect(
          () => GameCatalog.restoredStatusFor(GameRegistry.create(e.id)!),
          returnsNormally,
          reason: '${e.title} 의 복구 문구가 예외를 던진다',
        );
      }
    });
  });

  group('게임 카탈로그 ↔ 서버 레지스트리', () {
    test('카탈로그의 모든 종목이 서버에 등록돼 있다', () {
      // 어긋나면 로비에는 보이는데 누르면 못 만들거나, 저장된 방을 복원하지 못한다.
      for (final e in GameCatalog.all) {
        expect(
          GameRegistry.factories.containsKey(e.id),
          isTrue,
          reason: '${e.id} 가 GameRegistry 에 없다',
        );
        expect(GameRegistry.create(e.id), isNotNull);
      }
    });

    test('서버에 등록된 모든 종목이 로비에 걸린다', () {
      // 등록만 하고 카탈로그에 안 넣으면 아무도 시작할 수 없는 유령 게임이 된다.
      for (final id in GameRegistry.ids) {
        expect(GameCatalog.byId(id), isNotNull, reason: '$id 가 카탈로그에 없다');
      }
    });

    test('id 가 중복되지 않는다', () {
      final ids = GameCatalog.all.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('배너·문구가 비어 있지 않다', () {
      for (final e in GameCatalog.all) {
        expect(e.title, isNotEmpty, reason: e.id);
        expect(e.subtitle, isNotEmpty, reason: e.id);
        expect(e.bannerAsset, startsWith('assets/'), reason: e.id);
      }
    });

    test('모듈 메타를 읽을 수 있다', () {
      for (final e in GameCatalog.all) {
        final m = e.meta;
        expect(m.name, isNotEmpty, reason: e.id);
        expect(m.minPlayers, greaterThanOrEqualTo(2), reason: e.id);
        expect(m.maxPlayers, greaterThan(m.minPlayers), reason: e.id);
      }
    });
  });

  group('상태 문구 매핑', () {
    test('각 종목의 이벤트가 문구로 옮겨진다', () {
      expect(GameCatalog.statusFor('mafia_started', {'roles': {}}), '역할 배정 완료');
      expect(
        GameCatalog.statusFor('mafia_phase', {'phase': 'night', 'round': 2}),
        '2일차 밤',
      );
      expect(
        GameCatalog.statusFor('mafia_night_progress', {
          'done': 2,
          'total': 2,
          'allDone': true,
        }),
        contains('전원 완료'),
      );
      expect(GameCatalog.statusFor('liar_ended', {'caught': true}), '라이어 검거!');
      expect(
        GameCatalog.statusFor('poll_closed', {'total': 5}),
        contains('5표'),
      );
    });

    test('모르는 이벤트는 null 이라 기존 문구가 유지된다', () {
      expect(GameCatalog.statusFor('무슨_이벤트', {}), isNull);
    });

    test('종목끼리 이벤트 이름이 겹치지 않는다', () {
      // 겹치면 statusFor 가 먼저 등록된 종목의 문구를 잘못 돌려준다.
      const probes = [
        'mafia_started',
        'mafia_phase',
        'mafia_night_progress',
        'mafia_vote_progress',
        'mafia_ended',
        'liar_started',
        'liar_vote_progress',
        'liar_ended',
        'poll_progress',
        'poll_closed',
      ];
      for (final ev in probes) {
        final owners = GameCatalog.all
            .where((e) => e.status?.call(ev, _sample) != null)
            .length;
        expect(owners, 1, reason: '$ev 를 $owners 개 종목이 처리한다');
      }
    });
  });
  _ruleValuesMatchServer();
  _everyGameIsResumable();
}

/// 어떤 이벤트에 넣어도 예외가 안 나게 넉넉히 채운 표본 데이터.
const _sample = <String, dynamic>{
  'roles': <String, String>{},
  'phase': 'night',
  'round': 1,
  'done': 1,
  'total': 1,
  'allDone': false,
  'voted': 1,
  'players': 1,
  'winner': 'citizen',
  'caught': false,
  'liar': 'x',
  'category': 'c',
  'word': 'w',
};

/// 규칙이 선언한 선택지는 **서버가 실제로 아는 값**이어야 한다.
///
/// 설정 화면은 종목을 모른 채 규칙 선언만 보고 그린다. 그래서 앱이 적어 둔
/// 값과 서버가 받아들이는 값이 어긋나면, 사용자는 고른 대로 됐다고 믿는데
/// 서버는 조용히 기본값으로 굴린다 — 화면에도 로그에도 안 남는 고장이다.
void _ruleValuesMatchServer() {
  group('규칙 선택지와 서버가 어긋나지 않는다', () {
    test('구슬 룰렛 코스 목록이 서버 선언과 같다', () {
      final rule =
          GameCatalog.byId(
                MarbleGame.gameId,
              )!.rules.firstWhere((r) => r.key == 'course')
              as ChoiceRule;
      expect(
        rule.options.keys.toSet(),
        MarbleCourses.ids.toSet(),
        reason: '앱이 아는 코스와 서버가 아는 코스가 다르다',
      );
      expect(MarbleCourses.ids, contains(rule.initial));
    });

    test('고른 코스가 실제로 적용된다', () {
      for (final id in MarbleCourses.ids) {
        final g = MarbleGame()..applyRules({'course': id});
        expect(g.courseId, id);
      }
    });
  });
}

/// 로비는 종목을 몰라야 한다.
///
/// 예전에는 "복구된 판으로 돌아가기" 가 로비에 손으로 나열돼 있었다 —
/// 마피아·라이어·투표만. 그래서 구슬·사다리는 판이 돌고 있어도 돌아갈 길이
/// 없었고, 앱을 다시 켜면 로비에 떨어진 채 참가자만 기다렸다.
/// 이제 종목이 [GameEntry.livePage] 로 자기 화면을 선언한다.
void _everyGameIsResumable() {
  group('모든 종목이 진행 화면을 선언한다', () {
    test('빠진 종목이 없다', () {
      for (final e in GameCatalog.all) {
        expect(e.livePage, isNotNull, reason: '${e.id} 가 진행 중일 때 돌아갈 화면이 없다');
      }
    });

    test('서버에 등록된 모든 종목이 카탈로그에 있다', () {
      // 한쪽만 늘면 "판은 도는데 로비가 모르는" 상태가 생긴다.
      expect(
        GameCatalog.all.map((e) => e.id).toSet(),
        GameRegistry.ids.toSet(),
      );
    });
  });
}
