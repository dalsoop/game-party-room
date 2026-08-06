import 'dart:math';

import '../../game_module.dart';
import '../../player.dart';
import '../../roster.dart';
import '../palette.dart';

/// 사다리 한 판의 뼈대 — 세로줄 N개와 가로대들.
///
/// 가로대는 (행, 왼쪽 세로줄 번호) 로 적는다. 같은 행에서 이웃한 두 가로대가
/// 겹치면(한 세로줄이 좌우로 동시에 이어지면) 사다리가 아니게 되므로 생성이
/// 원천 차단한다. 추적은 위에서 아래로 한 행씩: 내 줄 오른쪽에 가로대가 있으면
/// 오른쪽으로, 왼쪽에 있으면 왼쪽으로 건넌다.
class Ladder {
  Ladder._(this.columns, this.rows, this._rungs);

  final int columns;
  final int rows;

  /// row * (columns-1) + leftCol 을 담는다.
  final Set<int> _rungs;

  bool rungAt(int row, int leftCol) {
    if (leftCol < 0 || leftCol >= columns - 1) return false;
    return _rungs.contains(row * (columns - 1) + leftCol);
  }

  /// 세로줄 수에 맞는 행 수.
  ///
  /// 예전에는 14로 고정이었다. 화면 밀도를 일정하게 두려는 값이었는데,
  /// **렌더링 걱정이 게임 로직 상수를 정하고 있었다.** 사다리는 랜덤워크라
  /// 세로줄이 늘수록 같은 행 수로는 덜 섞인다 — 20명이면 제자리에 남을
  /// 확률이 이상값(1/n)의 3.4배였다. 선이 거의 직선으로 내려가면 참가자가
  /// 조작을 의심한다.
  ///
  /// 세로줄의 2배로 늘리면 2.2배까지 내려간다. 더 늘려도 이동이 √행 으로만
  /// 자라서(4배·행 80이어도 1.7배) 화면만 빽빽해진다 — 여기서 끊는다.
  /// 완전히 균일해지지 않는 것은 사다리타기의 본성이고, **당첨 확률 자체는
  /// 결과 칸 셔플이 이미 균일하게 만든다**(실측 20명 4.6~5.6%, 이상 5.0%).
  ///
  /// 화면은 이 값에 맞춰 간격을 줄인다(`rowH = 높이/(rows+1)`).
  static int rowsFor(int columns) => (columns * 2).clamp(14, 40);

  /// [seed]·[columns] 가 같으면 언제나 같은 사다리 — 저장·복원이 이 성질에
  /// 기댄다. [rows] 는 저장분을 되살릴 때만 넘긴다(그때의 행 수를 그대로
  /// 재현해야 참가자가 이미 본 결과와 어긋나지 않는다).
  factory Ladder.generate({
    required int columns,
    required int seed,
    int? rows,
  }) {
    final rng = Random(seed);
    rows ??= rowsFor(columns);
    final rungs = <int>{};

    for (var row = 0; row < rows; row++) {
      var skipNext = false;
      for (var col = 0; col < columns - 1; col++) {
        if (skipNext) {
          skipNext = false;
          continue;
        }
        if (rng.nextDouble() < 0.30) {
          rungs.add(row * (columns - 1) + col);
          skipNext = true; // 이웃 가로대와 같은 행에서 겹치지 않게
        }
      }
    }

    // 어느 이웃 쌍에도 가로대가 하나도 없으면 그 경계로는 절대 못 건넌다 —
    // 섞임을 보장하기 위해 빠진 쌍에 하나씩 심는다(겹침 없는 행을 고른다).
    for (var col = 0; col < columns - 1; col++) {
      final has = List.generate(
        rows,
        (r) => rungs.contains(r * (columns - 1) + col),
      ).any((v) => v);
      if (has) continue;
      for (var attempt = 0; attempt < 50; attempt++) {
        final row = rng.nextInt(rows);
        final conflict =
            rungs.contains(row * (columns - 1) + col - 1) ||
            rungs.contains(row * (columns - 1) + col + 1);
        if (conflict) continue;
        rungs.add(row * (columns - 1) + col);
        break;
      }
    }

    return Ladder._(columns, rows, rungs);
  }

  /// [start] 줄이 각 행을 지난 뒤 서 있는 세로줄 번호들.
  /// 길이는 rows+1 — 첫 값이 출발 줄, 마지막 값이 도착 줄이다.
  /// 호스트가 경로 애니메이션을 그릴 때 그대로 꺾은선으로 쓴다.
  List<int> trace(int start) {
    final path = <int>[start];
    var c = start;
    for (var row = 0; row < rows; row++) {
      if (rungAt(row, c)) {
        c += 1;
      } else if (rungAt(row, c - 1)) {
        c -= 1;
      }
      path.add(c);
    }
    return path;
  }

  int endOf(int start) => trace(start).last;
}

/// 사다리타기 — 참가자 한 명이 세로줄 하나를 갖고, 도착 칸이 운명이다.
///
/// 구슬 룰렛과 같은 **관전형** 종목: 호스트 화면이 본체고 폰은 "내 줄 몇 번" 과
/// 자기 결과만 받는다. [onMessage] 가 비어 있는 것은 실수가 아니라 성격이다.
///
/// 결과 칸은 호스트가 정한다(벌칙·아이스크림 사기·통과…). 비워 두면
/// "당첨" 하나에 나머지는 "꽝" — 뽑기 도구의 기본형이다.
class LadderGame implements GameModule {
  static const gameId = 'ladder';

  @override
  String get id => gameId;
  @override
  String get name => '사다리타기';
  @override
  int get minPlayers => 2;
  @override
  int get maxPlayers => 20;

  /// 구슬 룰렛과 같은 이유 — 뽑기 결과는 판별 기록이다.
  @override
  bool get ownsSection => true;

  /// 호스트가 입력한 결과 칸 원본. 인원보다 적으면 "꽝" 으로 채운다.
  List<String> rawOutcomes = [];

  final GameRoster roster = GameRoster();

  Ladder? _ladder;
  Ladder? get ladder => _ladder;

  /// 도착 칸 순서대로 늘어선 결과 문구(길이 = 인원).
  List<String> outcomes = [];

  int _seed = 0;
  int get seed => _seed;

  /// 공개(추적 완료)된 세로줄들 — 공개한 순서대로.
  final List<int> revealed = [];

  bool _ended = false;
  bool get finished => _ended;

  void setup({required List<String> outcomes}) {
    rawOutcomes = outcomes;
  }

  /// 별도 규칙 없음 — 결과 칸은 시작 다이얼로그에서 직접 만든다.
  @override
  void applyRules(Map<String, dynamic> rules) {}

  @override
  void start(GameContext ctx) {
    roster.seatConnected(ctx);
    _seed = DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF;
    _build();
    revealed.clear();
    _ended = false;

    for (var i = 0; i < roster.length; i++) {
      final seat = roster.seats[i];
      ctx.sendTo(seat.session, {
        'type': 'scene',
        'scene': 'ladder_ready',
        'column': i,
        'color': partyColorOf(i),
        'nickname': seat.nickname,
        'total': roster.length,
        'outcomes': outcomes,
      });
    }
    ctx.onGameEvent('ladder_ready', {'count': roster.length, 'seed': _seed});
  }

  /// 사다리와 결과 칸을 세운다.
  ///
  /// 자리(세로줄)는 시드로 섞는다 — 명단 순서 그대로면 먼저 입장한 사람이
  /// 늘 같은 줄이라 "자리빨" 이 생긴다. 결과 칸 순서도 시드로 섞어,
  /// 호스트가 입력한 순서에서 위치를 유추할 수 없게 한다.
  void _build() {
    final rng = Random(_seed);
    final shuffled = roster.seats.toList()..shuffle(rng);
    roster.restore([
      for (final s in shuffled)
        {'session': s.session, 'tag': s.tag, 'nickname': s.nickname},
    ]);

    final n = roster.length;
    final padded = List<String>.of(
      (rawOutcomes.isEmpty ? const ['당첨'] : rawOutcomes).take(n),
    );
    while (padded.length < n) {
      padded.add('꽝');
    }
    outcomes = padded..shuffle(rng);

    _ladder = Ladder.generate(columns: n, seed: _seed);
  }

  /// [column] 줄의 도착 결과.
  String outcomeOf(int column) => outcomes[_ladder!.endOf(column)];

  /// 아직 공개 안 된 줄 중 첫 번째. 없으면 null.
  int? get nextUnrevealed {
    for (var i = 0; i < roster.length; i++) {
      if (!revealed.contains(i)) return i;
    }
    return null;
  }

  /// 호스트가 [column] 줄의 추적 연출을 끝낸 뒤 부른다 — 그 참가자에게
  /// 결과를 보내고, 전원 공개되면 전체 표를 발표한다.
  ///
  /// 연출 전에 보내면 폰이 큰 화면보다 먼저 스포일러를 띄운다. 순서가 계약이다.
  void reveal(GameContext ctx, int column) {
    if (_ladder == null || _ended) return;
    if (column < 0 || column >= roster.length) return;
    if (revealed.contains(column)) return;
    revealed.add(column);

    final seat = roster.seats[column];
    final outcome = outcomeOf(column);
    ctx.sendTo(seat.session, {
      'type': 'scene',
      'scene': 'ladder_result',
      'outcome': outcome,
      'hit': outcome != '꽝',
      'column': column,
      'color': partyColorOf(column),
    });
    ctx.onGameEvent('ladder_reveal', {
      'nickname': seat.nickname,
      'outcome': outcome,
      'done': revealed.length,
      'total': roster.length,
    });

    if (revealed.length >= roster.length) _finish(ctx);
  }

  void _finish(GameContext ctx) {
    if (_ended) return;
    _ended = true;
    ctx.broadcast({
      'type': 'scene',
      'scene': 'ladder_end',
      'results': _resultTable(),
      // 시드 공개 — 같은 시드는 같은 사다리를 만든다. 뽑기 도구인 이상
      // "어떻게 나온 결과냐" 에 답할 수 있어야 한다.
      'seed': _seed,
    });
    ctx.onGameEvent('ladder_end', {});
  }

  List<Map<String, dynamic>> _resultTable() => [
    for (var i = 0; i < roster.length; i++)
      {
        'column': i,
        'color': partyColorOf(i),
        'nickname': roster.seats[i].nickname,
        'tag': roster.seats[i].tag,
        'outcome': outcomeOf(i),
        'hit': outcomeOf(i) != '꽝',
      },
  ];

  @override
  void onMessage(GameContext ctx, Player from, Map<String, dynamic> msg) {
    // 참가자가 보낼 것이 없다 — 관전형이다.
  }

  @override
  void onReconnect(GameContext ctx, Player player) {
    if (_ladder == null) return;
    final column = _columnOf(player.sessionToken);
    if (column == null) return;

    if (_ended) {
      ctx.sendTo(player.sessionToken, {
        'type': 'scene',
        'scene': 'ladder_end',
        'results': _resultTable(),
        'seed': _seed,
      });
      return;
    }
    if (revealed.contains(column)) {
      final outcome = outcomeOf(column);
      ctx.sendTo(player.sessionToken, {
        'type': 'scene',
        'scene': 'ladder_result',
        'outcome': outcome,
        'hit': outcome != '꽝',
        'column': column,
        'color': partyColorOf(column),
      });
      return;
    }
    final seat = roster.seats[column];
    ctx.sendTo(player.sessionToken, {
      'type': 'scene',
      'scene': 'ladder_ready',
      'column': column,
      'color': partyColorOf(column),
      'nickname': seat.nickname,
      'total': roster.length,
      'outcomes': outcomes,
    });
  }

  int? _columnOf(String session) {
    for (var i = 0; i < roster.length; i++) {
      if (roster.seats[i].session == session) return i;
    }
    return null;
  }

  @override
  void end(GameContext ctx) {
    _ladder = null;
    revealed.clear();
    _ended = false;
  }

  @override
  Map<String, dynamic> toJson() => {
    'rawOutcomes': rawOutcomes,
    'seed': _seed,
    // 행 수 공식이 바뀌어도 이미 시작된 판은 그대로 되살아나야 한다 —
    // 참가자가 본 결과가 앱 업데이트로 달라지면 안 된다.
    'rows': _ladder?.rows,
    'roster': roster.toJson(),
    'revealed': revealed,
    'ended': _ended,
  };

  @override
  void restore(GameContext ctx, Map<String, dynamic> json) {
    rawOutcomes = [
      for (final o in (json['rawOutcomes'] as List<dynamic>? ?? const []))
        o as String,
    ];
    _seed = (json['seed'] as num?)?.toInt() ?? 0;
    roster.restore(json['roster'] as List<dynamic>?);
    if (roster.isEmpty) return;

    // 같은 시드·같은 명단 → 같은 사다리·같은 결과 배치. 단, _build 는
    // 명단을 다시 섞으므로 **이미 섞여 저장된 명단을 또 섞지 않게** 시드
    // 셔플을 건너뛰고 사다리·결과만 다시 세운다.
    final rng = Random(_seed);
    // 저장 당시와 같은 난수 소비 순서를 재현한다: shuffle(명단) → 결과 셔플.
    (List.generate(roster.length, (i) => i)).shuffle(rng);
    final n = roster.length;
    final padded = List<String>.of(
      (rawOutcomes.isEmpty ? const ['당첨'] : rawOutcomes).take(n),
    );
    while (padded.length < n) {
      padded.add('꽝');
    }
    outcomes = padded..shuffle(rng);
    _ladder = Ladder.generate(
      columns: n,
      seed: _seed,
      rows: (json['rows'] as num?)?.toInt(),
    );

    revealed
      ..clear()
      ..addAll([
        for (final r in (json['revealed'] as List<dynamic>? ?? const []))
          (r as num).toInt(),
      ]);
    _ended = json['ended'] as bool? ?? false;
  }
}
