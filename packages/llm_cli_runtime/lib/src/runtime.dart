/// 터미널 LLM CLI 실행 계층.
///
/// **API 키가 아니라 이미 로그인된 구독을 쓴다.** 맥에 `claude`·`codex`·`grok`
/// 이 깔려 있고 로그인돼 있으면, 앱은 그 CLI 를 그대로 불러 답을 받는다 —
/// 사용자가 키를 발급받아 붙여넣을 필요가 없다.
///
/// 계약은 swift-app-mono 의 `swiftkit/LLMRuntimeKit` 과 같은 모양으로 맞췄다:
/// 요청/결과/오류 타입 + 백엔드 프로토콜 + 디스패치. 두 생태계가 같은 개념을
/// 쓰면 한쪽에서 배운 것(인자·PATH 보강·타임아웃 코드)이 다른 쪽에 그대로 온다.
library;

import 'dart:io';

import 'backends.dart';

/// 한 번의 단발 질의.
class LlmRunRequest {
  const LlmRunRequest({
    required this.prompt,
    this.system,
    this.model,
    this.cwd,
    this.timeout = const Duration(seconds: 90),
  });

  final String prompt;

  /// 백엔드에 따라 시스템 프롬프트를 따로 못 주는 경우가 있다 —
  /// 그럴 땐 [composedPrompt] 처럼 본문 앞에 붙인다.
  final String? system;
  final String? model;
  final String? cwd;
  final Duration timeout;

  String get composedPrompt =>
      [system, prompt].where((s) => s != null && s.isNotEmpty).join('\n\n');
}

class LlmRunResult {
  const LlmRunResult({
    required this.text,
    this.sessionId,
    this.isError = false,
    this.costUsd,
    this.rawStdout = '',
  });

  final String text;
  final String? sessionId;
  final bool isError;
  final double? costUsd;
  final String rawStdout;
}

sealed class LlmRunError implements Exception {
  const LlmRunError(this.backend);
  final String backend;
}

class LlmNotInstalled extends LlmRunError {
  const LlmNotInstalled(super.backend);
  @override
  String toString() => '$backend CLI 를 찾지 못했습니다';
}

class LlmProcessFailed extends LlmRunError {
  const LlmProcessFailed(super.backend, this.exitCode, this.stderr);
  final int exitCode;
  final String stderr;
  @override
  String toString() {
    final head = stderr.trim().split('\n').first;
    return '$backend 실행 실패 ($exitCode)${head.isEmpty ? '' : ': $head'}';
  }
}

class LlmTimeout extends LlmRunError {
  const LlmTimeout(super.backend);
  @override
  String toString() => '$backend 응답이 시간 내에 오지 않았습니다';
}

class LlmEmptyResponse extends LlmRunError {
  const LlmEmptyResponse(super.backend);
  @override
  String toString() => '$backend 가 빈 응답을 돌려줬습니다';
}

/// CLI 백엔드 하나.
abstract class LlmCliBackend {
  const LlmCliBackend();

  /// 'claude' | 'codex' | 'grok'
  String get id;

  /// 사람이 읽는 이름.
  String get label;

  /// 설치 안내에 보여 줄 한 줄.
  String get installHint;

  /// 실행 파일 경로. 없으면 null.
  String? resolveExecutable();

  bool get installed => resolveExecutable() != null;

  Future<LlmRunResult> run(LlmRunRequest request);

  /// 사용자가 직접 지정한 경로를 해석한다.
  ///
  /// - 지정이 없으면 null → 호출자가 자동 탐색으로 넘어간다.
  /// - 지정이 있는데 없는 파일이면 [notFound] 로 표시하고 **자동 탐색으로
  ///   넘어가지 않는다**. 명시한 경로가 틀렸는데 조용히 다른 바이너리를
  ///   쓰면, 사용자는 자기가 고른 것이 돌아가고 있다고 착각한다.
  static (bool given, String? path) resolveOverride(String? override) {
    if (override == null || override.isEmpty) return (false, null);
    return (true, File(override).existsSync() ? override : null);
  }

  /// 탐색 결과 캐시(있음·없음 모두).
  ///
  /// 마지막 수단인 로그인 셸 조회(`zsh -lc`)는 **동기 실행이고 수십~수백 ms**
  /// 다. 설정 화면은 이 값을 build 에서 읽는데, 그 화면은 방 상태가 바뀔
  /// 때마다 다시 그려진다 — 캐시가 없으면 채팅 한 줄에도 로그인 셸이 세 번
  /// 뜬다. 하필 CLI 가 안 깔린 맥(= 구매자)에서만 느려진다.
  static final Map<String, String?> _resolved = {};

  /// 사용자가 방금 설치했을 수 있다 — 설정 화면에서 다시 검사할 때 부른다.
  static void clearResolveCache() => _resolved.clear();

  /// GUI 앱은 로그인 셸의 PATH 를 물려받지 못한다 — 알려진 설치 위치를 직접
  /// 짚고, 그래도 없으면 로그인 셸에 물어본다.
  static String? resolveOnPath(String name, {List<String> extra = const []}) {
    final key = '$name|${extra.join(',')}';
    if (_resolved.containsKey(key)) return _resolved[key];
    return _resolved[key] = _resolveOnPathUncached(name, extra: extra);
  }

  static String? _resolveOnPathUncached(
    String name, {
    List<String> extra = const [],
  }) {
    final home = Platform.environment['HOME'] ?? '';
    final candidates = <String>[
      ...extra.map((p) => p.replaceFirst('~', home)),
      ...?Platform.environment['PATH']
          ?.split(':')
          .where((d) => d.isNotEmpty)
          .map((d) => '$d/$name'),
      '/opt/homebrew/bin/$name',
      '/usr/local/bin/$name',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    try {
      final r = Process.runSync('/bin/zsh', ['-lc', 'command -v $name']);
      final out = (r.stdout as String).trim();
      if (r.exitCode == 0 && out.isNotEmpty && File(out).existsSync()) {
        return out;
      }
    } catch (_) {
      // 못 찾은 것으로 본다.
    }
    return null;
  }

  /// 공통 실행 — 타임아웃이 걸리면 프로세스를 확실히 죽인다.
  static Future<ProcessResult> exec(
    String executable,
    List<String> args, {
    String? cwd,
    required Duration timeout,
    required String backend,
  }) async {
    final proc = await Process.start(executable, args, workingDirectory: cwd);
    // stdin 을 즉시 닫는다. 열어 두면 대화형 CLI 가 입력을 기다리다 타임아웃까지
    // 버틴다(codex 에서 실제로 90초를 그냥 흘려보냈다). 프롬프트는 argv 로 준다.
    await proc.stdin.close();
    final out = StringBuffer();
    final err = StringBuffer();
    final done = Future.wait([
      proc.stdout.transform(const SystemEncoding().decoder).forEach(out.write),
      proc.stderr.transform(const SystemEncoding().decoder).forEach(err.write),
      proc.exitCode,
    ]);
    try {
      final results = await done.timeout(timeout);
      return ProcessResult(
        proc.pid,
        results[2] as int,
        out.toString(),
        err.toString(),
      );
    } on Object {
      proc.kill(ProcessSignal.sigkill);
      throw LlmTimeout(backend);
    }
  }
}

/// id → 백엔드 디스패치.
class LlmCliRuntime {
  LlmCliRuntime({List<LlmCliBackend>? backends})
    : backends = backends ?? defaultBackends();

  final List<LlmCliBackend> backends;

  static List<LlmCliBackend> defaultBackends() => const [
    ClaudeCliBackend(),
    CodexCliBackend(),
    GrokCliBackend(),
  ];

  LlmCliBackend? byId(String id) {
    for (final b in backends) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// 지금 이 맥에 실제로 깔려 있는 것들.
  List<LlmCliBackend> get available =>
      backends.where((b) => b.installed).toList();

  Future<LlmRunResult> run(String backendId, LlmRunRequest request) {
    final backend = byId(backendId);
    if (backend == null) throw LlmNotInstalled(backendId);
    if (!backend.installed) throw LlmNotInstalled(backend.id);
    return backend.run(request);
  }
}
