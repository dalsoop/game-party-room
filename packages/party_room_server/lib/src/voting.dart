/// 세션을 대상으로 하는 투표 수집·집계.
///
/// 마피아(처형 투표)와 라이어(지목 투표)가 같은 일을 각자 구현하고 있었다.
/// 표 무게(정치인 2표)와 동표 판정이 한쪽에만 있어 규칙이 갈렸다 — 여기로 모은다.
class VoteBox {
  final Map<String, String> _votes = {}; // voter -> target

  int get length => _votes.length;
  bool get isEmpty => _votes.isEmpty;
  Map<String, String> get votes => Map.unmodifiable(_votes);

  void cast(String voter, String target) => _votes[voter] = target;
  void clear() => _votes.clear();

  /// 집계. [weightOf] 로 투표자별 표 무게를 준다(기본 1표).
  ///
  /// 동표는 [VoteTally.isTie] 로 알린다 — 처리 방침(무처형이냐 최다득표냐)은
  /// 게임 규칙이라 호출부가 정한다.
  VoteTally tally({int Function(String voter)? weightOf}) {
    final counts = <String, int>{};
    for (final e in _votes.entries) {
      final w = weightOf?.call(e.key) ?? 1;
      counts[e.value] = (counts[e.value] ?? 0) + w;
    }
    if (counts.isEmpty) {
      return const VoteTally(counts: {}, top: null, isTie: false);
    }

    // 득표 내림차순 + 동점은 세션 토큰 오름차순 — 정렬을 안정화해야 같은 표에서
    // 매번 같은 결과가 나온다(예전에는 Map 순회 순서에 따라 달라졌다).
    final sorted = counts.entries.toList()
      ..sort((a, b) {
        final byVotes = b.value.compareTo(a.value);
        return byVotes != 0 ? byVotes : a.key.compareTo(b.key);
      });
    final topVotes = sorted.first.value;
    final tiedCount = sorted.where((e) => e.value == topVotes).length;
    return VoteTally(
      counts: Map.unmodifiable(counts),
      top: sorted.first.key,
      isTie: tiedCount > 1,
    );
  }

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(_votes);

  void restore(Map<String, dynamic>? json) {
    _votes
      ..clear()
      ..addAll((json ?? const {}).map((k, v) => MapEntry(k, v as String)));
  }
}

/// 집계 결과.
class VoteTally {
  const VoteTally({
    required this.counts,
    required this.top,
    required this.isTie,
  });

  /// 대상 세션 → 득표수.
  final Map<String, int> counts;

  /// 최다 득표 대상. 표가 하나도 없으면 null.
  final String? top;

  /// 최다 득표가 둘 이상인지.
  final bool isTie;
}
