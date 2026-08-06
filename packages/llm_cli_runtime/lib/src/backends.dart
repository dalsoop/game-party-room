import 'dart:convert';

import 'runtime.dart';

/// `claude -p --output-format json` — Claude Code 구독을 그대로 쓴다.
///
/// 응답은 `{"result": "...", "session_id": ..., "is_error": ...}` 봉투다.
class ClaudeCliBackend extends LlmCliBackend {
  const ClaudeCliBackend({this.executableOverride});

  final String? executableOverride;

  @override
  String get id => 'claude';
  @override
  String get label => 'Claude Code';
  @override
  String get installHint => 'npm i -g @anthropic-ai/claude-code 후 claude 로그인';

  @override
  String? resolveExecutable() {
    final (given, path) = LlmCliBackend.resolveOverride(executableOverride);
    if (given) return path;
    return LlmCliBackend.resolveOnPath(
      'claude',
      extra: [
        '~/.claude/local/claude',
        '~/.local/bin/claude',
        '~/.npm-global/bin/claude',
      ],
    );
  }

  @override
  Future<LlmRunResult> run(LlmRunRequest request) async {
    final exec = resolveExecutable();
    if (exec == null) throw LlmNotInstalled(id);

    final args = <String>[
      '-p',
      request.composedPrompt,
      '--output-format',
      'json',
      if (request.model != null) ...['--model', request.model!],
    ];
    final r = await LlmCliBackend.exec(
      exec,
      args,
      cwd: request.cwd,
      timeout: request.timeout,
      backend: id,
    );
    if (r.exitCode != 0) {
      throw LlmProcessFailed(id, r.exitCode, r.stderr as String);
    }

    final stdout = r.stdout as String;
    try {
      final j = jsonDecode(stdout) as Map<String, dynamic>;
      final text = (j['result'] as String? ?? '').trim();
      if (text.isEmpty) throw LlmEmptyResponse(id);
      return LlmRunResult(
        text: text,
        sessionId: j['session_id'] as String?,
        isError: j['is_error'] as bool? ?? false,
        costUsd: (j['total_cost_usd'] as num?)?.toDouble(),
        rawStdout: stdout,
      );
    } on LlmRunError {
      rethrow;
    } catch (_) {
      // JSON 이 아니면 평문으로 온 것으로 본다(버전 차이 대비).
      final text = stdout.trim();
      if (text.isEmpty) throw LlmEmptyResponse(id);
      return LlmRunResult(text: text, rawStdout: stdout);
    }
  }
}

/// `codex exec` — ChatGPT 구독을 그대로 쓴다.
///
/// 출력이 평문이고 훅 로그·토큰 사용량이 섞여 나온다. 마지막 의미 있는 줄이
/// 최종 답변이라 그것만 뽑는다.
class CodexCliBackend extends LlmCliBackend {
  const CodexCliBackend({this.executableOverride, this.sandbox = 'read-only'});

  final String? executableOverride;
  final String sandbox;

  @override
  String get id => 'codex';
  @override
  String get label => 'Codex (ChatGPT)';
  @override
  String get installHint => 'npm i -g @openai/codex 후 codex 로그인';

  @override
  String? resolveExecutable() {
    final (given, path) = LlmCliBackend.resolveOverride(executableOverride);
    if (given) return path;
    return LlmCliBackend.resolveOnPath(
      'codex',
      extra: ['~/.npm-global/bin/codex', '~/.local/bin/codex'],
    );
  }

  @override
  Future<LlmRunResult> run(LlmRunRequest request) async {
    final exec = resolveExecutable();
    if (exec == null) throw LlmNotInstalled(id);

    final args = <String>[
      'exec',
      '--sandbox',
      sandbox,
      '--skip-git-repo-check',
      '--color',
      'never',
      if (request.model != null) ...['--model', request.model!],
      request.composedPrompt,
    ];
    final r = await LlmCliBackend.exec(
      exec,
      args,
      cwd: request.cwd,
      timeout: request.timeout,
      backend: id,
    );
    if (r.exitCode != 0) {
      throw LlmProcessFailed(id, r.exitCode, r.stderr as String);
    }
    final text = extractAnswer(r.stdout as String);
    if (text.isEmpty) throw LlmEmptyResponse(id);
    return LlmRunResult(text: text, rawStdout: r.stdout as String);
  }

  /// 훅 로그·헤더·토큰 사용량을 걷어내고 마지막 답변만 남긴다.
  ///
  /// 실제 출력 예:
  /// ```
  /// hook: UserPromptSubmit Completed
  /// codex
  /// 밤이 되었습니다.
  /// hook: Stop
  /// tokens used
  /// 2,974
  /// 밤이 되었습니다.
  /// ```
  static String extractAnswer(String stdout) {
    final noise = RegExp(
      r'^(hook:|tokens used$|codex$|\[.*\]$|[\d,]+$|-{3,}$)',
      caseSensitive: false,
    );
    final lines = stdout
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !noise.hasMatch(l))
        .toList();
    return lines.isEmpty ? '' : lines.last;
  }
}

/// `grok -p --output-format json` — Grok 구독을 그대로 쓴다.
///
/// swift-app-mono 의 `GrokBackend` 는 인자가 검증되지 않아 닫혀 있었는데,
/// 이 맥의 grok CLI(`Grok Build TUI`)에서 확인한 플래그가 위 두 개다.
class GrokCliBackend extends LlmCliBackend {
  const GrokCliBackend({this.executableOverride});

  final String? executableOverride;

  @override
  String get id => 'grok';
  @override
  String get label => 'Grok';
  @override
  String get installHint => 'grok CLI 설치 후 로그인';

  @override
  String? resolveExecutable() {
    final (given, path) = LlmCliBackend.resolveOverride(executableOverride);
    if (given) return path;
    return LlmCliBackend.resolveOnPath('grok', extra: ['~/.grok/bin/grok']);
  }

  @override
  Future<LlmRunResult> run(LlmRunRequest request) async {
    final exec = resolveExecutable();
    if (exec == null) throw LlmNotInstalled(id);

    final args = <String>[
      '-p',
      request.composedPrompt,
      '--output-format',
      'json',
      if (request.model != null) ...['-m', request.model!],
    ];
    final r = await LlmCliBackend.exec(
      exec,
      args,
      cwd: request.cwd,
      timeout: request.timeout,
      backend: id,
    );

    final stdout = (r.stdout as String).trim();
    // grok 은 실패도 stdout 에 {"type":"error"} 로 싣는다 — exit code 만
    // 보면 "잔액 소진"을 성공으로 오인한다.
    if (stdout.startsWith('{')) {
      try {
        final j = jsonDecode(stdout) as Map<String, dynamic>;
        if (j['type'] == 'error') {
          throw LlmProcessFailed(id, r.exitCode, j['message'] as String? ?? '');
        }
        final text = (j['result'] ?? j['text'] ?? j['response']) as String?;
        if (text != null && text.trim().isNotEmpty) {
          return LlmRunResult(text: text.trim(), rawStdout: stdout);
        }
      } on LlmRunError {
        rethrow;
      } catch (_) {
        // 아래 평문 경로로.
      }
    }
    if (r.exitCode != 0) {
      throw LlmProcessFailed(id, r.exitCode, r.stderr as String);
    }
    if (stdout.isEmpty) throw LlmEmptyResponse(id);
    return LlmRunResult(text: stdout, rawStdout: stdout);
  }
}
