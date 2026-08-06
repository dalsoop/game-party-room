import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:party_room_server/party_room_server.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../host_controller.dart';

/// 밖에 있는 사람을 들여보내는 길.
///
/// **로컬이 먼저다.** 같은 Wi-Fi 면 참가자는 호스트에게 곧장 붙고 이 화면은
/// 등장할 일이 없다. 여기는 그게 안 되는 사람을 위한 두 번째 QR 이다 —
/// 망이 다르거나, 카페 Wi-Fi 가 기기끼리 못 보게 막아 뒀거나(AP 격리),
/// 방화벽이 막았거나.
class RelayPage extends StatefulWidget {
  const RelayPage({super.key, required this.ctrl});

  final HostController ctrl;

  @override
  State<RelayPage> createState() => _RelayPageState();
}

class _RelayPageState extends State<RelayPage> {
  late final TextEditingController _base = TextEditingController(
    text: widget.ctrl.settings.relayBase,
  );

  @override
  void initState() {
    super.initState();
    widget.ctrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.ctrl.removeListener(_onChanged);
    _base.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    final ctrl = widget.ctrl;
    if (ctrl.relayStatus == RelayStatus.off) {
      ctrl.settings.setRelayBase(_base.text);
      await ctrl.startRelay();
    } else {
      await ctrl.stopRelay();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    final url = ctrl.relayUrl;
    final on = ctrl.relayStatus != RelayStatus.off;

    return Scaffold(
      appBar: AppBar(title: const Text('밖에 있는 사람 들이기')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _StatusCard(ctrl: ctrl),
          const SizedBox(height: 14),
          const Text(
            '이건 어떤 길인가요',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            '호스트가 랑데부 서버로 나가서 붙고, 참가자는 그 서버를 거쳐 '
            '들어옵니다. 포트를 열거나 방화벽을 손댈 일이 없습니다.\n\n'
            '같은 Wi-Fi 에 있는 사람은 이 길을 쓸 필요가 없어요 — '
            '지금 QR 그대로가 더 빠릅니다.',
            style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _base,
            enabled: !on,
            // 켜지 않고 나가도 적어 둔 주소는 남는다 — 다음 파티에 다시
            // 치게 하지 않는다.
            onSubmitted: ctrl.settings.setRelayBase,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: '랑데부 서버 주소',
              hintText: 'https://party.example.com',
              helperText: '직접 띄운 서버 주소입니다 (packages/party_room_relay)',
              helperMaxLines: 2,
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _base.text.trim().isEmpty && !on ? null : _toggle,
            icon: Icon(on ? Icons.stop_circle_outlined : Icons.cloud_upload),
            label: Text(on ? '끄기' : '켜기'),
          ),
          if (url != null) ...[
            const Divider(height: 36),
            const Text(
              '밖에 있는 사람에게 보여줄 QR',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(color: Color(0x1A1D2B50), blurRadius: 12),
                  ],
                ),
                child: QrImageView(data: url, size: 200),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: url)),
                icon: const Icon(Icons.copy, size: 16),
                label: Text(url, style: const TextStyle(fontSize: 11)),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const _Caveat(),
        ],
      ),
    );
  }
}

/// 지금 어떤 상태인가 — 이 화면의 결론.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.ctrl});

  final HostController ctrl;

  @override
  Widget build(BuildContext context) {
    final (icon, tone, title, sub) = switch (ctrl.relayStatus) {
      RelayStatus.off => (
        Icons.cloud_off,
        Colors.grey,
        '꺼져 있습니다',
        '같은 Wi-Fi 에 있는 사람만 들어올 수 있습니다',
      ),
      RelayStatus.connecting => (
        Icons.cloud_sync,
        Colors.blueGrey,
        '붙는 중…',
        '랑데부 서버에 연결하고 있습니다',
      ),
      RelayStatus.ready => (
        Icons.cloud_done,
        Colors.green,
        '방 코드 ${ctrl.relayCode}',
        '어느 망에서든 들어올 수 있습니다',
      ),
      RelayStatus.retrying => (
        Icons.cloud_sync,
        Colors.orange,
        '끊겼습니다 — 다시 붙는 중',
        '코드는 그대로입니다. 나눠 준 QR 은 안 죽습니다',
      ),
      RelayStatus.denied => (
        Icons.error_outline,
        Colors.red,
        '거절당했습니다',
        switch (ctrl.relay?.deniedReason) {
          'version' => '릴레이 서버의 판이 앱과 다릅니다 — 서버를 올리세요',
          'secret' => '이 앱의 열쇠가 너무 짧습니다',
          _ => '이유: ${ctrl.relay?.deniedReason ?? "알 수 없음"}',
        },
      ),
    };

    return Card(
      color: tone == Colors.grey
          ? Colors.grey.shade100
          : tone.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: tone),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(sub, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Caveat extends StatelessWidget {
  const _Caveat();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              // 왜 그런지까지 적는다. "왜 사진이 안 올라가?" 는 파티에서
              // 반드시 나오는 질문이다.
              '이 길로 들어온 사람은 자료(사진·영상·파일)를 주고받을 수 '
              '없습니다. 한 사람 30MB 를 남의 서버로 나르지 않기 때문입니다 — '
              '대화와 게임은 다 됩니다.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
            ),
          ),
        ],
      ),
    );
  }
}
