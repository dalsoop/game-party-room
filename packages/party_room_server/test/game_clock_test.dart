import 'package:party_room_server/party_room_server.dart';
import 'package:test/test.dart';

/// 판을 굴리는 시계. 화면이 사라져도 시간은 계속 흘러야 한다.
void main() {
  test('흐른 시간이 실제 경과를 따라간다', () async {
    final clock = GameClock(interval: const Duration(milliseconds: 5));
    addTearDown(clock.dispose);
    var total = 0.0;
    var ticks = 0;
    final wall = Stopwatch()..start();
    clock.start((dt) {
      total += dt;
      ticks++;
    });
    await Future<void>.delayed(const Duration(milliseconds: 120));
    clock.stop();
    wall.stop();

    expect(ticks, greaterThan(0), reason: '아예 안 불렸다');
    final elapsed = wall.elapsedMilliseconds / 1000;
    expect(total, closeTo(elapsed, elapsed * 0.5 + 0.02));
  });

  test('멈추면 더 안 흐른다', () async {
    final clock = GameClock(interval: const Duration(milliseconds: 5));
    addTearDown(clock.dispose);
    var ticks = 0;
    clock.start((_) => ticks++);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    clock.stop();
    final frozen = ticks;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(ticks, frozen);
    expect(clock.running, isFalse);
  });

  test('다시 시작하면 앞의 것은 갈아 끼워진다', () async {
    final clock = GameClock(interval: const Duration(milliseconds: 5));
    addTearDown(clock.dispose);
    var first = 0;
    var second = 0;
    clock.start((_) => first++);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    clock.start((_) => second++);
    final frozen = first;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    clock.stop();
    expect(second, greaterThan(0));
    expect(first, frozen, reason: '앞의 콜백이 아직도 불린다');
  });

  test('한 틱이 지나치게 길어도 상식적인 값을 준다', () async {
    final clock = GameClock(interval: const Duration(milliseconds: 5));
    addTearDown(clock.dispose);
    final seen = <double>[];
    clock.start(seen.add);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    clock.stop();
    expect(seen, isNotEmpty);
    expect(seen.every((dt) => dt <= 0.25), isTrue);
  });

  test('dispose 하면 타이머가 남지 않는다', () async {
    final clock = GameClock(interval: const Duration(milliseconds: 5));
    var ticks = 0;
    clock.start((_) => ticks++);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    clock.dispose();
    final frozen = ticks;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(ticks, frozen);
  });
}
