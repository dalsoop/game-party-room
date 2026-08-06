import 'dart:async';
import 'package:flutter/material.dart';

import '../host_controller.dart';
import 'host_hud.dart';

/// 익명 투표: 설정 다이얼로그 → 진행 페이지.
class PollPage extends StatelessWidget {
  const PollPage({super.key, required this.ctrl});

  final HostController ctrl;

  /// 로비에서 호출: 질문 설정 후 페이지 진입.
  static Future<void> startFlow(
    BuildContext context,
    HostController ctrl,
  ) async {
    final result = await showDialog<(String, List<String>)>(
      context: context,
      builder: (_) => const _PollSetupDialog(),
    );
    if (result == null) return;
    final (question, options) = result;
    ctrl.games.startPoll(question, options);
    if (context.mounted) {
      // 이 Future 는 밀어 넣은 화면이 닫힐 때 끝난다 — 여기서 기다릴 것이
      // 아니다. 빠뜨린 게 아니라는 걸 unawaited 로 밝힌다.
      unawaited(
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PollPage(ctrl: ctrl)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        if (ctrl.games.poll == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          });
          return const SizedBox.shrink();
        }
        final poll = ctrl.games.poll!;
        return HudScaffold(
          title: '익명 투표',
          status: ctrl.games.gameStatus,
          onEnd: () {
            ctrl.games.endGame();
            Navigator.pop(context);
          },
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 질문이 이 화면의 첫 줄이다. 예전에는 그 위에 장식
                    // 사진이 있어서, 멀리서 보면 사진이 먼저 눈에 들어왔다 —
                    // 정작 사람들이 읽어야 할 것은 질문인데.
                    const SizedBox(height: 4),
                    Text(
                      poll.question,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: HostHud.ink,
                      ),
                    ),
                    const SizedBox(height: 16),
                    HudMcLine(line: ctrl.mcLine),
                    for (var i = 0; i < poll.options.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _OptionRow(index: i, label: poll.options[i]),
                      ),
                    const SizedBox(height: 10),
                    const Text(
                      '전원 투표하면 자동으로 결과가 공개됩니다',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: HostHud.dim),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 선택지 한 줄 — 참가자 폰의 번호 매긴 행과 같은 어법.
class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.index, required this.label});

  final int index;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const NotchClipper(size: 11),
      child: Container(
        color: const Color(0xFF141C36),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Text(
              (index + 1).toString().padLeft(2, '0'),
              style: const TextStyle(
                color: HostHud.dim,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: HostHud.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PollSetupDialog extends StatefulWidget {
  const _PollSetupDialog();

  @override
  State<_PollSetupDialog> createState() => _PollSetupDialogState();
}

class _PollSetupDialogState extends State<_PollSetupDialog> {
  final _question = TextEditingController(text: '오늘 뭐 먹을까?');
  final _options = TextEditingController(text: '치킨, 피자, 곱창, 회');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('익명 투표 만들기'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _question,
            decoration: const InputDecoration(labelText: '질문'),
          ),
          TextField(
            controller: _options,
            decoration: const InputDecoration(labelText: '선택지 (쉼표로 구분)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            final q = _question.text.trim();
            final opts = _options.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            if (q.isEmpty || opts.length < 2) return;
            Navigator.pop(context, (q, opts));
          },
          child: const Text('시작'),
        ),
      ],
    );
  }
}
