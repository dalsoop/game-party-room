import 'dart:io';

import 'package:llm_cli_runtime/llm_cli_runtime.dart';
import 'package:test/test.dart';

/// CLI 런타임의 계약.
///
/// 실제 CLI 는 로그인·구독·잔액에 따라 결과가 달라지므로, 여기서는
/// **인자 조립·출력 파싱·실패 처리** 를 가짜 실행 파일로 못박는다.
/// 진짜 CLI 왕복은 `dart test -t live` 로 따로 돌린다.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('llm_cli_test_');
  });
  tearDown(() async => tmp.delete(recursive: true));

  /// 인자를 파일로 남기고 [stdout] 을 뱉는 가짜 CLI.
  Future<String> fakeCli(
    String stdout, {
    int exitCode = 0,
    String stderr = '',
  }) async {
    final argLog = '${tmp.path}/args.txt';
    final path = '${tmp.path}/fake';
    await File(path).writeAsString('''#!/bin/sh
printf '%s\\036' "\$@" > $argLog
cat <<'PAYLOAD'
$stdout
PAYLOAD
${stderr.isEmpty ? '' : 'echo "$stderr" >&2'}
exit $exitCode
''');
    await Process.run('chmod', ['+x', path]);
    return path;
  }

  Future<List<String>> loggedArgs() async =>
      (await File('${tmp.path}/args.txt').readAsString())
          // 프롬프트에 개행이 들어가므로 구분자는 개행이 아니어야 한다.
          .split('\u001e')
          .where((l) => l.isNotEmpty)
          .toList();

  group('claude', () {
    test('JSON 봉투에서 result 만 꺼낸다', () async {
      final exec = await fakeCli(
        '{"result":"밤이 되었습니다.","session_id":"S1",'
        '"is_error":false,"total_cost_usd":0.01}',
      );
      final r = await ClaudeCliBackend(
        executableOverride: exec,
      ).run(const LlmRunRequest(prompt: '밤을 알려라', system: '너는 사회자다'));
      expect(r.text, '밤이 되었습니다.');
      expect(r.sessionId, 'S1');
      expect(r.costUsd, 0.01);
    });

    test('-p 와 --output-format json 으로 부르고, system 을 앞에 붙인다', () async {
      final exec = await fakeCli('{"result":"ok"}');
      await ClaudeCliBackend(
        executableOverride: exec,
      ).run(const LlmRunRequest(prompt: '본문', system: '머리말', model: 'sonnet'));
      final args = await loggedArgs();
      expect(args, contains('-p'));
      expect(args, containsAllInOrder(['--output-format', 'json']));
      expect(args, containsAllInOrder(['--model', 'sonnet']));
      expect(args.any((a) => a.contains('머리말') && a.contains('본문')), isTrue);
    });

    test('JSON 이 아니면 평문으로 받아들인다', () async {
      final exec = await fakeCli('그냥 문장입니다');
      final r = await ClaudeCliBackend(
        executableOverride: exec,
      ).run(const LlmRunRequest(prompt: 'x'));
      expect(r.text, '그냥 문장입니다');
    });

    test('0 이 아닌 종료코드는 실패로 올린다', () async {
      final exec = await fakeCli('', exitCode: 1, stderr: 'not logged in');
      expect(
        () => ClaudeCliBackend(
          executableOverride: exec,
        ).run(const LlmRunRequest(prompt: 'x')),
        throwsA(isA<LlmProcessFailed>()),
      );
    });
  });

  group('codex', () {
    test('훅 로그·토큰 사용량을 걷어내고 답변만 남긴다', () {
      const raw = '''
hook: UserPromptSubmit Completed
codex
밤이 되었습니다.
hook: Stop
hook: Stop Completed
tokens used
2,974
밤이 되었습니다.
''';
      expect(CodexCliBackend.extractAnswer(raw), '밤이 되었습니다.');
    });

    test('exec --sandbox 로 부른다', () async {
      final exec = await fakeCli('codex\n답변입니다.');
      final r = await CodexCliBackend(
        executableOverride: exec,
      ).run(const LlmRunRequest(prompt: '질문'));
      expect(r.text, '답변입니다.');
      final args = await loggedArgs();
      expect(args.first, 'exec');
      expect(args, containsAllInOrder(['--sandbox', 'read-only']));
      expect(args, contains('--skip-git-repo-check'));
    });
  });

  group('grok', () {
    test('stdout 에 실린 오류를 성공으로 오인하지 않는다', () async {
      // grok 은 잔액 소진도 exit 0 + {"type":"error"} 로 올 수 있다.
      final exec = await fakeCli(
        '{"type":"error","message":"usage balance exhausted"}',
      );
      expect(
        () => GrokCliBackend(
          executableOverride: exec,
        ).run(const LlmRunRequest(prompt: 'x')),
        throwsA(
          isA<LlmProcessFailed>().having(
            (e) => e.stderr,
            'message',
            contains('balance'),
          ),
        ),
      );
    });

    test('-p 와 --output-format json 으로 부른다', () async {
      final exec = await fakeCli('{"result":"안녕"}');
      final r = await GrokCliBackend(
        executableOverride: exec,
      ).run(const LlmRunRequest(prompt: '인사해'));
      expect(r.text, '안녕');
      final args = await loggedArgs();
      expect(args, contains('-p'));
      expect(args, containsAllInOrder(['--output-format', 'json']));
    });
  });

  group('런타임', () {
    test('설치 안 된 백엔드는 실행 전에 막는다', () {
      final rt = LlmCliRuntime(
        backends: const [ClaudeCliBackend(executableOverride: '/nope/claude')],
      );
      expect(
        () => rt.run('claude', const LlmRunRequest(prompt: 'x')),
        throwsA(isA<LlmNotInstalled>()),
      );
      expect(rt.available, isEmpty);
    });

    test('모르는 id 도 막는다', () {
      expect(
        () => LlmCliRuntime().run('없는것', const LlmRunRequest(prompt: 'x')),
        throwsA(isA<LlmNotInstalled>()),
      );
    });
  });

  group('실제 CLI', () {
    test('이 맥에 설치된 백엔드가 하나 이상 잡힌다', () {
      final rt = LlmCliRuntime();
      final ids = rt.available.map((b) => b.id).toList();
      // CI 등 CLI 가 없는 환경에서는 건너뛴다.
      if (ids.isEmpty) {
        markTestSkipped('설치된 LLM CLI 없음');
        return;
      }
      expect(ids, isNotEmpty);
    });
  });

  _cacheTests();
}

/// 탐색 캐시.
///
/// 마지막 수단인 `zsh -lc` 는 동기 실행이라 설정 화면 build 에서 매번 돌면
/// 화면이 끊긴다 — 하필 CLI 가 안 깔린 맥에서만. 캐시하되, 사용자가 방금
/// 설치했을 수 있으니 비우는 손잡이를 남긴다.
void _cacheTests() {
  group('탐색 캐시', () {
    test('한 번 찾은 결과를 다시 찾지 않는다', () {
      final dir = Directory.systemTemp.createTempSync('resolvecache');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bin = File('${dir.path}/faux-cli')..writeAsStringSync('x');

      final first = LlmCliBackend.resolveOnPath('faux-cli', extra: [bin.path]);
      expect(first, bin.path);

      bin.deleteSync();
      expect(
        LlmCliBackend.resolveOnPath('faux-cli', extra: [bin.path]),
        bin.path,
        reason: '캐시가 안 먹으면 매 build 마다 파일시스템·로그인 셸을 두드린다',
      );

      LlmCliBackend.clearResolveCache();
      expect(
        LlmCliBackend.resolveOnPath('faux-cli', extra: [bin.path]),
        isNull,
        reason: '비운 뒤에는 실제 상태를 다시 봐야 한다',
      );
    });
  });
}
