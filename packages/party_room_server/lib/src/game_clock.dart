import 'dart:async';

/// 화면과 무관하게 게임 진행 시간을 흘리는 시계.
///
/// 구슬 물리와 사다리 공개는 화면이 가려져도 끝나야 한다. vsync 대신 실제
/// 경과 시간을 쓰고, 앱이 오래 멈췄다가 돌아온 한 틱은 250ms 로 제한한다.
class GameClock {
  GameClock({this.interval = const Duration(milliseconds: 16)});

  final Duration interval;

  Timer? _timer;
  Stopwatch? _watch;
  void Function(double dt)? _onTick;

  bool get running => _timer != null;

  void start(void Function(double dt) onTick) {
    stop();
    _onTick = onTick;
    _watch = Stopwatch()..start();
    _timer = Timer.periodic(interval, (_) {
      final watch = _watch;
      if (watch == null) return;
      final dt = watch.elapsedMicroseconds / 1e6;
      watch.reset();
      if (dt <= 0) return;
      _onTick?.call(dt > 0.25 ? 0.25 : dt);
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _watch?.stop();
    _watch = null;
    _onTick = null;
  }

  void dispose() => stop();
}
