import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../host_controller.dart';

/// CLI 표면을 화면에서도 보여 준다.
///
/// 계약(`docs/app-interop-contract.md`)의 GUI 완료 조건: "GUI 앱은 자동화
/// 가능한 기능을 CLI 에만 숨겨 두지 않는다. 사용자가 기능의 존재·현재 상태·
/// 실행 결과·복구 액션을 화면에서 발견할 수 있어야 한다."
/// 그래서 여기서 **설치 여부·상태 파일 위치·명령 목록**을 다 보인다.
class CliPage extends StatefulWidget {
  const CliPage({super.key, required this.ctrl});

  final HostController ctrl;

  static void open(BuildContext context, HostController ctrl) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => CliPage(ctrl: ctrl)),
  );

  /// PATH 에서 partyroom 을 찾는다. GUI 앱은 로그인 셸 PATH 를 못 물려받으므로
  /// 알려진 위치를 직접 짚는다(터널·LLM CLI 탐색과 같은 이유).
  static String? resolve() {
    final home = Platform.environment['HOME'] ?? '';
    for (final p in [
      '/opt/homebrew/bin/partyroom',
      '/usr/local/bin/partyroom',
      '$home/.local/bin/partyroom',
    ]) {
      if (File(p).existsSync()) return p;
    }
    return null;
  }

  @override
  State<CliPage> createState() => _CliPageState();
}

class _CliPageState extends State<CliPage> {
  String? _path = CliPage.resolve();

  @override
  Widget build(BuildContext context) {
    final mirror = widget.ctrl.mirror;
    final installed = _path != null;
    return Scaffold(
      appBar: AppBar(title: const Text('명령줄에서 조종하기')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              _Card(
                icon: installed ? Icons.check_circle : Icons.info_outline,
                color: installed ? Colors.green : Colors.orange,
                title: installed ? 'CLI 설치됨' : 'CLI 가 PATH 에 없습니다',
                body: installed
                    ? _path!
                    : '아래 한 줄을 터미널에 붙여넣으면 설치됩니다.\n'
                          '화면 없이 상태를 확인하거나 판을 진행할 수 있습니다.',
                action: installed
                    ? TextButton(
                        onPressed: () =>
                            setState(() => _path = CliPage.resolve()),
                        child: const Text('다시 검사'),
                      )
                    : TextButton(
                        onPressed: () {
                          Clipboard.setData(
                            const ClipboardData(text: _installCommand),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('설치 명령을 복사했습니다')),
                          );
                        },
                        child: const Text('설치 명령 복사'),
                      ),
              ),
              _Card(
                icon: Icons.folder_outlined,
                color: Colors.blueGrey,
                title: '상태 파일',
                body:
                    '${mirror.file.path}\n'
                    '방·참가자·판·네트워크 상태가 여기 실시간으로 실립니다.\n'
                    '앱이 꺼져 있어도 마지막 상태를 읽을 수 있습니다.',
                action: TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: mirror.file.path));
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('경로를 복사했습니다')));
                  },
                  child: const Text('경로 복사'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
                child: Text(
                  '할 수 있는 것',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              for (final (cmd, what) in _commands)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    cmd,
                    style: const TextStyle(fontFamily: 'Menlo', fontSize: 12.5),
                  ),
                  subtitle: Text(what, style: const TextStyle(fontSize: 12)),
                ),
              const SizedBox(height: 8),
              const Text(
                '모든 명령에 --json 을 붙이면 {"ok":true,"result":…} 로 답합니다.\n'
                '이 화면에서 하는 일과 CLI 가 하는 일은 같은 코드를 지납니다.',
                style: TextStyle(fontSize: 12, color: Color(0xFF7C8698)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 소스 위치를 사람이 외울 필요는 없다 — 한 줄이면 끝나야 한다.
const _installCommand =
    'sh ~/Documents/WORK/apps/flutter-app-mono/apps/game-party-room-app/cli/install.sh';

const _commands = <(String, String)>[
  ('partyroom state', '앱이 꺼져 있어도 마지막 상태를 답한다'),
  ('partyroom status', '떠 있는 앱의 지금 상태'),
  ('partyroom players', '참가자 목록과 접속 여부'),
  ('partyroom games', '종목과 시작 가능 여부'),
  ('partyroom sections', '대화·자료 칸'),
  ('partyroom start mafia', '판 시작'),
  ('partyroom start ladder --outcomes 당첨,꽝,꽝', '결과 칸을 지정해 사다리 시작'),
  ('partyroom marble launch', '구슬 출발'),
  ('partyroom ladder all', '사다리 남은 줄 전부 공개'),
  ('partyroom end', '진행 중인 판 끝내기'),
  ('partyroom chat "곧 시작합니다"', '호스트로 한마디'),
  ('partyroom kick A3F2', '참가자 내보내기'),
];

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDBE4F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: Color(0xFF5F6C82),
                  ),
                ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
