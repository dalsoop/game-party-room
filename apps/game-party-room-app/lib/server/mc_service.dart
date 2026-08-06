import 'dart:convert';
import 'dart:io';

import 'package:llm_cli_runtime/llm_cli_runtime.dart';

/// 사회자가 말을 지어내는 통로.
///
/// 두 가지다 —
/// - **터미널 구독**([McCliSource]): 맥에 로그인된 claude·codex·grok CLI 를
///   그대로 부른다. 키 발급·붙여넣기가 없어 사용자가 할 일이 "켜기" 뿐이다.
/// - **HTTP**([McHttpSource]): OpenAI 호환 엔드포인트. 서버·팀 키를 쓰거나
///   Ollama 같은 로컬 서버를 붙일 때.
abstract class McSource {
  const McSource();

  /// 설정 화면에 보여 줄 한 줄.
  String get label;

  Future<String?> complete(String system, String user);
}

/// 이미 로그인된 CLI 구독을 빌려 쓴다.
class McCliSource extends McSource {
  McCliSource({required this.backendId, LlmCliRuntime? runtime})
    : runtime = runtime ?? LlmCliRuntime();

  final String backendId;
  final LlmCliRuntime runtime;

  @override
  String get label => runtime.byId(backendId)?.label ?? backendId;

  @override
  Future<String?> complete(String system, String user) async {
    final r = await runtime.run(
      backendId,
      LlmRunRequest(
        system: system,
        prompt: user,
        // 사회자는 진행 중에 끼어드는 것이라 오래 못 기다린다.
        timeout: const Duration(seconds: 45),
      ),
    );
    return r.text;
  }
}

/// OpenAI 호환 /chat/completions.
class McHttpSource extends McSource {
  const McHttpSource({required this.baseUrl, required this.model, this.apiKey});

  final String baseUrl;
  final String model;
  final String? apiKey;

  @override
  String get label => '$model · $baseUrl';

  @override
  Future<String?> complete(String system, String user) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.postUrl(Uri.parse('$baseUrl/chat/completions'));
      req.headers.contentType = ContentType.json;
      if (apiKey != null && apiKey!.isNotEmpty) {
        req.headers.set('authorization', 'Bearer $apiKey');
      }
      req.write(
        jsonEncode({
          'model': model,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
          // 사회자 한 마디는 짧아야 한다 — 길면 아무도 안 읽는다.
          'max_tokens': 120,
          'temperature': 0.9,
        }),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 300) throw HttpException('HTTP ${res.statusCode}');
      final json = jsonDecode(body) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return null;
      final msg = (choices.first as Map<String, dynamic>)['message'];
      return (msg as Map<String, dynamic>)['content'] as String?;
    } finally {
      client.close(force: true);
    }
  }
}

/// LLM 사회자 — 게임 진행 순간에 분위기를 잡는 한두 문장을 지어 방에 뿌린다.
///
/// **게임 규칙에는 일절 관여하지 않는다.** 순위·승패·역할은 서버 모듈이 이미
/// 정했고, 사회자는 그 결과를 말로 옮길 뿐이다. 호출이 실패하거나 느려도
/// 게임은 그대로 진행된다(호출은 전부 fire-and-forget).
///
/// 제공자는 OpenAI 호환 `/chat/completions` 하나로 통일한다 — OpenAI·LiteLLM·
/// Ollama(`http://localhost:11434/v1`)·LM Studio 가 모두 이 규격이라
/// 사용자가 base URL 과 모델만 넣으면 원하는 것을 붙일 수 있다.
class McService {
  McService({required this.source, this.persona = McPersona.classic});

  /// 터미널 구독이든 HTTP 든, 사회자가 보기엔 "문장을 돌려주는 것" 하나다.
  final McSource source;
  final McPersona persona;

  /// 한 번 실패하면 잠시 쉰다 — 매 이벤트마다 타임아웃을 기다리면
  /// 사회자가 아니라 방해물이 된다.
  DateTime? _mutedUntil;

  bool get muted =>
      _mutedUntil != null && DateTime.now().isBefore(_mutedUntil!);

  /// [event]/[data] 로 한 문장을 짓는다. 말할 것이 없으면 null.
  ///
  /// 실패·타임아웃도 null — 호출자는 결과가 없으면 그냥 넘어간다.
  Future<String?> narrate(String event, Map<String, dynamic> data) async {
    if (muted) return null;
    final beat = _beatFor(event, data);
    if (beat == null) return null;

    try {
      final raw = await source
          .complete(persona.systemPrompt, beat)
          .timeout(const Duration(seconds: 50));
      return _tidy(raw);
    } catch (_) {
      // 30초 쉬었다 다시 시도한다.
      _mutedUntil = DateTime.now().add(const Duration(seconds: 30));
      return null;
    }
  }

  /// 연결 확인 — 설정 화면의 [테스트] 버튼용.
  /// 성공하면 사회자가 실제로 한 말, 실패하면 [McProbeResult.error].
  Future<McProbeResult> probe() async {
    try {
      final raw = await source
          .complete(persona.systemPrompt, '방금 파티가 시작됐다. 한 문장으로 인사해라.')
          .timeout(const Duration(seconds: 60));
      final text = _tidy(raw);
      if (text == null || text.isEmpty) {
        return const McProbeResult(error: '응답이 비어 있습니다');
      }
      return McProbeResult(sample: text);
    } on SocketException {
      return const McProbeResult(error: '서버에 연결할 수 없습니다 — 주소를 확인하세요');
    } catch (e) {
      return McProbeResult(error: e.toString().split('\n').first);
    }
  }

  /// 모델이 붙이는 따옴표를 벗기고 한 줄로 만든다.
  static String? _tidy(String? raw) {
    if (raw == null) return null;
    final one = raw.trim().replaceAll(RegExp(r'\s*\n+\s*'), ' ');
    return one.replaceAll(RegExp(r'^["\u201c]|["\u201d]$'), '').trim();
  }

  /// 프롬프트 생성기를 테스트에 연다.
  ///
  /// 이 함수의 출력이 곧 "모델에게 넘어가는 전부" 라, 비밀 누설 여부는
  /// 네트워크 없이 여기서 검사할 수 있어야 한다.
  static String? beatForTest(String event, Map<String, dynamic> data) =>
      _beatFor(event, data);

  /// 이벤트 → 사회자가 받을 상황 설명.
  ///
  /// **여기가 이 기능의 안전선이다.** 참가자가 아직 모르는 것(마피아가 누구인지,
  /// 라이어의 제시어)은 절대 넣지 않는다 — 모델에 주면 언젠가 새어 나온다.
  /// 모든 문장은 "이미 공개된 사실" 로만 만든다.
  static String? _beatFor(String event, Map<String, dynamic> data) {
    switch (event) {
      case 'mafia_started':
        // roles 가 payload 에 있지만 **의도적으로 쓰지 않는다**.
        return '마피아 게임이 시작됐다. 참가자는 ${data['players']}명. '
            '역할이 각자 폰으로 비밀리에 전달됐다. 게임의 시작을 알려라.';
      case 'mafia_phase':
        return switch (data['phase'] as String?) {
          'night' =>
            '${data['round']}일차 밤이 됐다. 모두 눈을 감는다. '
                '긴장감 있게 밤의 시작을 알려라.',
          'day' =>
            '${data['round']}일차 아침이 밝았다. '
                '간밤의 소식: "${data['announcement']}". 이 소식을 전해라.',
          'vote' => '토론이 끝나고 처형 투표를 시작한다. 투표를 재촉해라.',
          'vote_closed' =>
            '투표 결과가 나왔다: "${data['announcement']}". '
                '결과를 발표해라.',
          _ => null,
        };
      case 'mafia_ended':
        return data['winner'] == 'mafia'
            ? '마피아가 승리했다. 마피아 진영의 승리를 선언해라.'
            : '시민이 승리했다. 시민 진영의 승리를 선언해라.';

      case 'liar_started':
        // liar·word 가 payload 에 있지만 **절대 넣지 않는다** — 게임이 끝난다.
        return '라이어 게임이 시작됐다. 제시어가 각자에게 전달됐고 '
            '한 명만 모른다. 설명 순서를 시작하라고 알려라.';
      case 'liar_ended':
        return data['caught'] == true
            ? '라이어가 붙잡혔다. 시민들의 승리를 선언해라.'
            : '라이어가 끝까지 들키지 않았다. 라이어의 승리를 선언해라.';

      case 'poll_closed':
        return '익명 투표가 마감됐다. 총 ${data['total']}표. 결과 공개를 알려라.';

      case 'marble_done':
        return '구슬 룰렛이 끝났다. ${data['winner']} 님이 ${data['rank']}위로 '
            '당첨됐다. 당첨을 발표해라.';

      case 'ladder_end':
        return '사다리타기가 모두 공개됐다. 결과 발표를 마무리해라.';

      default:
        return null;
    }
  }
}

/// 연결 테스트 결과 — 실패 사유 또는 실제로 받은 한 문장.
class McProbeResult {
  const McProbeResult({this.sample, this.error});
  final String? sample;
  final String? error;
  bool get ok => error == null;
}

/// 사회자 성격 — 같은 상황도 톤이 다르면 파티 분위기가 달라진다.
enum McPersona {
  classic('정통 사회자', '차분하고 진중한 진행자'),
  hype('텐션 폭발', '과장되게 신난 예능 MC'),
  noir('느와르', '탐정 소설 내레이터');

  const McPersona(this.label, this.hint);

  final String label;
  final String hint;

  String get systemPrompt =>
      '너는 오프라인 파티 게임의 사회자다. 성격: $hint.\n'
      '규칙:\n'
      '- 한국어로, 1~2문장, 최대 60자 내외로 짧게 말한다.\n'
      '- 게임의 승패·역할·정답을 스스로 판단하거나 추측하지 않는다. '
      '주어진 사실만 전한다.\n'
      '- 알려주지 않은 정보(누가 마피아인지, 제시어가 무엇인지)는 '
      '절대 언급하지도 추측하지도 않는다.\n'
      '- 따옴표나 이모지 없이 말만 한다.';
}
