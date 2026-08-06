import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../server/diagnostics.dart';

/// 오류 기록 보기.
///
/// 호스트가 읽고 이해하라고 두는 화면이 아니라, **보낼 수 있게** 두는 화면이다.
/// 그래서 손잡이는 [전체 복사] 하나면 충분하고, 나머지는 "언제 무슨 일이
/// 있었나" 를 눈으로 확인하는 용도다.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key, this.diagnostics});

  /// 테스트에서 임시 디렉터리를 물리려고 둔 구멍. 앱에서는 항상 null.
  final Diagnostics? diagnostics;

  static void open(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const DiagnosticsPage()),
  );

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  Diagnostics get diag => widget.diagnostics ?? Diagnostics.instance;
  late List<String> _entries = diag.recent();

  void _reload() => setState(() => _entries = diag.recent());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('오류 기록'),
        actions: [
          if (_entries.isNotEmpty) ...[
            IconButton(
              tooltip: '전체 복사',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _entries.join('\n\n')));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('오류 기록을 복사했습니다')));
              },
            ),
            IconButton(
              tooltip: '지우기',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                diag.clear();
                _reload();
              },
            ),
          ],
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: _entries.isEmpty
              ? const _Empty()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: _entries.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) return _Note(path: diag.logFile.path);
                    return _Entry(text: _entries[i - 1]);
                  },
                ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 40, color: Colors.green),
          SizedBox(height: 10),
          Text('기록된 오류가 없습니다', style: TextStyle(fontSize: 15)),
          SizedBox(height: 4),
          Text(
            '문제가 생기면 여기에 자동으로 쌓입니다.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF7C8698)),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Text(
        '이 기록은 이 맥에만 있습니다 — 어디로도 전송되지 않습니다.\n$path',
        style: const TextStyle(fontSize: 11.5, color: Color(0xFF7C8698)),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final head = lines.first.replaceFirst('── ', '');
    final body = lines.skip(1).join('\n').trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE3E9F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            head,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFF7C8698),
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            body,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              fontFamily: 'Menlo',
            ),
          ),
        ],
      ),
    );
  }
}
