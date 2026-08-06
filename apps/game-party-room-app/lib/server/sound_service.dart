import 'package:audioplayers/audioplayers.dart';

/// 진행 효과음.
///
/// **결정적인 순간에만 운다.** 스파크마다 소리를 내면 파티 소음이 되고,
/// 사람들이 서로 말하는 자리라 배경음악도 방해다. 출발·골인·당첨·낮밤 전환
/// 처럼 "지금 뭔가 일어났다" 를 알려야 하는 곳에만 붙인다.
///
/// 음원은 사인파 합성으로 직접 만든 것이라 라이선스 분쟁 여지가 없다.
enum GameSound {
  start('snd/start.wav'),
  finish('snd/finish.wav'),
  win('snd/win.wav'),
  night('snd/night.wav'),
  day('snd/day.wav'),
  reveal('snd/reveal.wav');

  const GameSound(this.asset);

  /// `assets/` 를 뺀 경로 — audioplayers 의 AssetSource 규약.
  final String asset;
}

class SoundService {
  SoundService({this.enabled = true});

  bool enabled;

  /// 소리마다 플레이어를 따로 둔다.
  ///
  /// 하나를 돌려 쓰면 골인이 연달아 날 때 앞 소리가 끊긴다 —
  /// 구슬 여섯 개가 1초 안에 들어오는 장면이 실제로 있다.
  final Map<GameSound, AudioPlayer> _players = {};

  /// 첫 재생에서 파일을 읽으면 그만큼 늦는다. 미리 물려 둔다.
  Future<void> warmUp() async {
    for (final s in GameSound.values) {
      final p = _player(s);
      try {
        await p.setSource(AssetSource(s.asset));
      } catch (_) {
        // 오디오 장치가 없어도 게임은 그대로 간다.
      }
    }
  }

  AudioPlayer _player(GameSound s) => _players.putIfAbsent(s, () {
    final p = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    // 말소리를 덮지 않게 낮게 깐다.
    p.setVolume(0.55);
    return p;
  });

  /// 소리는 게임 진행을 막지 않는다 — 실패해도 조용히 넘어간다.
  void play(GameSound sound) {
    if (!enabled) return;
    final p = _player(sound);
    p.stop().then((_) => p.play(AssetSource(sound.asset))).catchError((_) {});
  }

  Future<void> dispose() async {
    for (final p in _players.values) {
      await p.dispose();
    }
    _players.clear();
  }
}
