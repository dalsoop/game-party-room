import 'package:party_room_server/party_room_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_room_app/games/game_catalog.dart';
import 'package:game_party_room_app/settings/game_rule_spec.dart';

void main() {
  group('마피아 규칙', () {
    test('확장 역할을 끄면 기본 4역할만 나온다', () {
      for (var n = 4; n <= 20; n++) {
        final roles = MafiaComposition.forPlayerCount(n, extended: false);
        const basic = {
          MafiaRole.mafia,
          MafiaRole.doctor,
          MafiaRole.police,
          MafiaRole.citizen,
        };
        for (final r in roles) {
          expect(basic.contains(r), isTrue, reason: '$n인에 ${r.label} 이 나왔다');
        }
        expect(roles.length, n);
      }
    });

    test('확장을 꺼도 시작하자마자 마피아 승리인 편성은 없다', () {
      // 확장 역할 중 스파이는 마피아팀이라, 끄면 오히려 시민이 유리해야 한다.
      for (var n = 4; n <= 20; n++) {
        final roles = MafiaComposition.forPlayerCount(n, extended: false);
        final mafiaTeam = roles.where((r) => r.isMafiaTeam).length;
        expect(mafiaTeam < roles.length - mafiaTeam, isTrue, reason: '$n인');
      }
    });

    test('applyRules 로 규칙이 들어가고 저장·복원된다', () {
      final g = MafiaGame()
        ..applyRules({'extendedRoles': false, 'executeOnTie': true});
      expect(g.extendedRoles, isFalse);
      expect(g.executeOnTie, isTrue);

      // 규칙이 스냅샷에 실려야 앱 재시작 후 같은 규칙으로 이어진다.
      final restored = MafiaGame()..restore(_ctx, g.toJson());
      expect(restored.extendedRoles, isFalse);
      expect(restored.executeOnTie, isTrue);
    });

    test('규칙을 안 주면 표준 룰이 기본이다', () {
      final g = MafiaGame()..applyRules({});
      expect(g.extendedRoles, isTrue, reason: '확장 역할이 기본');
      expect(g.executeOnTie, isFalse, reason: '동표는 무처형이 표준');
    });
  });

  group('라이어 규칙', () {
    test('고른 카테고리만 남는다', () {
      final g = LiarGame()
        ..applyRules({
          'categories': ['음식', '동물'],
        });
      expect(g.enabledCategories, ['음식', '동물']);
    });

    test('없는 카테고리는 걸러낸다', () {
      // 저장된 설정이 오래돼 사라진 카테고리를 가리키면 제시어를 못 뽑는다.
      final g = LiarGame()
        ..applyRules({
          'categories': ['음식', '없는분류'],
        });
      expect(g.enabledCategories, ['음식']);
    });

    test('저장·복원을 왕복한다', () {
      final g = LiarGame()
        ..applyRules({
          'categories': ['장소'],
        });
      final restored = LiarGame()..restore(_ctx, g.toJson());
      expect(restored.enabledCategories, ['장소']);
    });
  });

  group('규칙 선언', () {
    test('선언한 규칙 키가 모듈이 실제로 읽는 키와 맞다', () {
      // 어긋나면 설정 화면에서 껐는데 게임은 그대로 도는, 알아채기 힘든 버그가 된다.
      final mafia = GameCatalog.byId(MafiaGame.gameId)!;
      final keys = mafia.rules.map((r) => r.key).toSet();
      expect(keys, containsAll(['extendedRoles', 'executeOnTie']));

      final applied = MafiaGame()
        ..applyRules({for (final r in mafia.rules) r.key: _flip(r)});
      expect(applied.extendedRoles, isFalse);
      expect(applied.executeOnTie, isTrue);
    });

    test('규칙 키가 종목 안에서 유일하다', () {
      for (final game in GameCatalog.all) {
        final keys = game.rules.map((r) => r.key).toList();
        expect(keys.toSet().length, keys.length, reason: game.id);
      }
    });

    test('라이어 카테고리 선택지가 실제 제시어 풀과 일치한다', () {
      final liar = GameCatalog.byId(LiarGame.gameId)!;
      final spec = liar.rules.whereType<MultiChoiceRule>().single;
      expect(spec.options.keys.toSet(), LiarGame.wordPools.keys.toSet());
      expect(
        spec.minSelected,
        greaterThanOrEqualTo(1),
        reason: '전부 끄면 제시어를 못 뽑는다',
      );
    });
  });
}

/// 토글 규칙의 기본값을 뒤집어 "설정이 실제로 먹히는지" 확인용 값을 만든다.
Object _flip(GameRuleSpec r) => r is ToggleRule ? !r.initial : r.defaultValue;

/// 아무것도 하지 않는 ctx — restore 는 전송을 하지 않는다.
final _ctx = GameContext(
  players: () => [],
  broadcast: (_) {},
  sendTo: (_, _) {},
  onGameEvent: (_, _) {},
);
