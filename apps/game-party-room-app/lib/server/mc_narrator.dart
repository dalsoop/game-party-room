import 'dart:async';

/// 사회자 발화 순서 관리 — **한 번에 하나, 밀린 것은 가장 최근 것만.**
///
/// 예전에는 게임 이벤트마다 그냥 던졌다. 그래서 세 가지가 났다:
/// 1. 밤·낮이 연달아 오면 LLM 응답이 **뒤바뀐 순서로** 도착했다
///    ("낮이 밝았습니다" 다음에 "밤이 되었습니다").
/// 2. 통로가 느리면 호출이 겹쳐 쌓였다 — CLI 백엔드는 호출 하나가
///    프로세스 하나라, 파티 도중 맥이 무거워진다.
/// 3. 판이 끝난 뒤 도착한 대사가 다음 판 단톡에 떨어졌다.
///
/// 사회자는 기록이 아니라 추임새다. 밀린 것을 다 읽을 이유가 없으므로
/// 대기는 한 칸이고 새 이벤트가 그 칸을 덮어쓴다.
class McNarrator {
  McNarrator(this._narrate);

  /// 실제로 문장을 지어 오는 통로. null 이면 사회자가 꺼져 있는 것이다.
  final Future<String?> Function(String event, Map<String, dynamic> data)?
  Function()
  _narrate;

  /// 지어진 문장이 나왔을 때.
  void Function(String line)? onLine;

  bool _busy = false;
  (String, Map<String, dynamic>)? _pending;
  int _epoch = 0;

  bool get busy => _busy;

  /// 대기 중인 이벤트가 있는지 — 테스트·진단용.
  bool get hasPending => _pending != null;

  void speak(String event, Map<String, dynamic> data) {
    if (_narrate() == null) return;
    if (_busy) {
      _pending = (event, data);
      return;
    }
    _run(event, data);
  }

  /// 판이 끝났다 — 돌고 있는 발화의 결과를 버리고 대기도 비운다.
  void reset() {
    _epoch++;
    _pending = null;
  }

  void _run(String event, Map<String, dynamic> data) {
    final narrate = _narrate();
    if (narrate == null) return;
    final epoch = _epoch;
    _busy = true;
    narrate(event, data)
        .then((line) {
          if (epoch != _epoch) return; // 지난 판의 대사 — 버린다.
          if (line != null && line.isNotEmpty) onLine?.call(line);
        })
        .catchError((_) {
          // 통로가 예상 못 한 방식으로 터져도 파티는 멈추지 않는다.
        })
        .whenComplete(() {
          _busy = false;
          final next = _pending;
          _pending = null;
          if (next != null && epoch == _epoch) _run(next.$1, next.$2);
        });
  }
}
