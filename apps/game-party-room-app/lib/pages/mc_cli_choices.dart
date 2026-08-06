import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:llm_cli_runtime/llm_cli_runtime.dart';

import '../host_controller.dart';

/// 설정 화면의 "터미널 구독" 목록.
///
/// 사회자를 붙이는 가장 쉬운 길이라 맨 위에 둔다 — 맥에 이미 로그인된
/// claude·codex·grok 이 있으면 **키를 만들 필요가 전혀 없다**.
/// 설치 안 된 것은 숨기지 않고 흐리게 두고 설치 한 줄을 복사하게 한다.
class McCliChoices {
  const McCliChoices._();

  static List<Widget> tiles(BuildContext context, HostController ctrl) {
    final runtime = LlmCliRuntime();
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                '터미널 구독 — 이미 로그인돼 있으면 키가 필요 없습니다',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            // 설치 여부는 캐시된다(로그인 셸 조회가 느려서). 방금 깔았으면
            // 여기서 다시 보게 한다 — 안 그러면 앱을 껐다 켜야 한다.
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                LlmCliBackend.clearResolveCache();
                ctrl.settings.notify();
              },
              child: const Text('다시 검사', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
      for (final backend in runtime.backends)
        _BackendTile(ctrl: ctrl, backend: backend),
    ];
  }
}

class _BackendTile extends StatelessWidget {
  const _BackendTile({required this.ctrl, required this.backend});

  final HostController ctrl;
  final LlmCliBackend backend;

  @override
  Widget build(BuildContext context) {
    final installed = backend.installed;
    final selected =
        ctrl.settings.mcProvider == 'cli' &&
        ctrl.settings.mcCliBackend == backend.id;

    return ListTile(
      leading: Icon(
        Icons.terminal,
        color: installed ? null : Colors.grey.shade400,
      ),
      title: Text(
        backend.label,
        style: TextStyle(color: installed ? null : Colors.grey),
      ),
      subtitle: Text(
        installed ? '설치됨 — 구독 그대로 사용' : '설치 안 됨 · ${backend.installHint}',
        style: TextStyle(
          fontSize: 12,
          color: installed ? Colors.green.shade700 : Colors.grey,
        ),
      ),
      // 라디오 위젯 대신 아이콘 — 선택 여부는 provider 까지 함께 봐야 하고
      // (cli 를 안 쓰는 중이면 어느 것도 켜져 있으면 안 된다),
      // 줄 전체가 탭 영역이라 조작은 onTap 하나로 충분하다.
      trailing: installed
          ? Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? const Color(0xFF2FB3FF) : Colors.grey,
            )
          : IconButton(
              tooltip: '설치 명령 복사',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: backend.installHint));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('설치 명령을 복사했습니다')));
              },
            ),
      selected: selected,
      onTap: installed
          ? () => ctrl.settings.setMc(provider: 'cli', cliBackend: backend.id)
          : null,
    );
  }
}
