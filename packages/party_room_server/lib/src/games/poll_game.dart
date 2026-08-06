import '../game_module.dart';
import '../player.dart';

/// 게임 1호: 익명 투표.
///
/// 호스트가 질문+선택지를 만들면 참가자 전원이 자기 폰에서 익명 투표.
/// 전원 투표(또는 호스트 마감) 시 결과 공개. 모듈 구조 검증용 최소 게임.
class PollGame implements GameModule {
  static const gameId = 'poll';

  @override
  String get id => gameId;
  @override
  String get name => '익명 투표';
  @override
  int get minPlayers => 2;
  @override
  int get maxPlayers => 20;

  /// 즉석 투표는 물어보고 끝이다. 빈 칸만 쌓이므로 열지 않는다.
  @override
  bool get ownsSection => false;

  String question = '';
  List<String> options = [];
  final Map<String, int> _votes = {}; // sessionToken -> option index
  bool closed = false;

  void setup({required String question, required List<String> options}) {
    this.question = question;
    this.options = options;
  }

  /// 익명 투표는 호스트가 매번 질문·선택지를 직접 만들므로 별도 규칙이 없다.
  @override
  void applyRules(Map<String, dynamic> rules) {}

  @override
  void start(GameContext ctx) {
    _votes.clear();
    closed = false;
    ctx.broadcast({
      'type': 'scene',
      'scene': 'poll',
      'question': question,
      'options': options,
    });
    _pushProgress(ctx);
  }

  @override
  void onMessage(GameContext ctx, Player from, Map<String, dynamic> msg) {
    if (msg['type'] != 'poll_vote' || closed) return;
    final idx = msg['option'];
    if (idx is! int || idx < 0 || idx >= options.length) return;
    _votes[from.sessionToken] = idx;
    ctx.sendTo(from.sessionToken, {'type': 'poll_ack', 'option': idx});
    _pushProgress(ctx);
    // 전원 투표 시 자동 마감
    final connected = ctx.players().where((p) => p.connected).length;
    if (_votes.length >= connected && connected > 0) {
      close(ctx);
    }
  }

  /// 결과 집계 후 전원 공개. 호스트도 수동 호출 가능(마감 버튼).
  void close(GameContext ctx) {
    if (closed) return;
    closed = true;
    final counts = List<int>.filled(options.length, 0);
    for (final v in _votes.values) {
      counts[v]++;
    }
    ctx.broadcast({
      'type': 'poll_result',
      'question': question,
      'options': options,
      'counts': counts,
      'total': _votes.length,
    });
    ctx.onGameEvent('poll_closed', {'counts': counts, 'total': _votes.length});
  }

  void _pushProgress(GameContext ctx) {
    ctx.onGameEvent('poll_progress', {
      'voted': _votes.length,
      'players': ctx.players().where((p) => p.connected).length,
    });
  }

  @override
  void onReconnect(GameContext ctx, Player player) {
    // 재접속자에게 현재 화면 복구
    ctx.sendTo(player.sessionToken, {
      'type': 'scene',
      'scene': 'poll',
      'question': question,
      'options': options,
    });
    final myVote = _votes[player.sessionToken];
    if (myVote != null) {
      ctx.sendTo(player.sessionToken, {'type': 'poll_ack', 'option': myVote});
    }
  }

  @override
  void end(GameContext ctx) {
    closed = true;
  }

  @override
  Map<String, dynamic> toJson() => {
    'question': question,
    'options': options,
    'votes': _votes,
    'closed': closed,
  };

  @override
  void restore(GameContext ctx, Map<String, dynamic> json) {
    question = json['question'] as String? ?? '';
    options = (json['options'] as List<dynamic>? ?? []).cast<String>();
    closed = json['closed'] as bool? ?? false;
    _votes
      ..clear()
      ..addAll(
        (json['votes'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v as int),
        ),
      );
  }
}
