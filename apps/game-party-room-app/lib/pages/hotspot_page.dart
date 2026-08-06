import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../host_controller.dart';
import '../server/host_address.dart';
import '../server/hotspot/hotspot_support.dart';

/// 전용 Wi-Fi(핫스팟) 온보딩.
///
/// 참가자가 호스트에 직접 붙으면 대역·VPN·AP격리 문제가 한 번에 사라진다.
/// 플랫폼마다 되는 방법이 달라서(앱이 켤 수 있는 건 Android 뿐) 안내문은
/// [HotspotGuide] 가 들고 있고, 이 화면은 그걸 그리고 결과를 감지만 한다.
class HotspotPage extends StatefulWidget {
  const HotspotPage({super.key, required this.ctrl, this.guide});

  final HostController ctrl;

  /// 생략하면 현재 플랫폼의 안내를 쓴다.
  ///
  /// 테스트·프리뷰는 실행 머신의 OS에 끌려가지 않도록 안내를 직접 넣을 수 있다.
  final HotspotGuide? guide;

  @override
  State<HotspotPage> createState() => _HotspotPageState();
}

class _HotspotPageState extends State<HotspotPage> {
  late final HotspotGuide _guide;
  final _ssid = TextEditingController();
  final _password = TextEditingController();

  HostAddress? _detected;
  bool _checking = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _guide = widget.guide ?? HotspotGuide.forCurrentPlatform();
    // 핫스팟 이름은 파티마다 그대로다 — 매번 다시 치게 두지 않는다.
    // (암호는 저장하지 않으므로 늘 비어서 시작한다.)
    _ssid.text = widget.ctrl.settings.hotspotSsid;
    _check();
    // 사용자가 설정 앱을 다녀오는 동안 앱은 그대로 열려 있다 —
    // 돌아왔을 때 이미 "감지됨" 이도록 주기적으로 본다.
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final found = await HotspotDetector.detect();
      if (mounted && found?.ip != _detected?.ip) {
        setState(() => _detected = found);
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _useDetected() async {
    await widget.ctrl.refreshAddresses();
    final i = widget.ctrl.addresses.indexWhere((a) => a.ip == _detected?.ip);
    if (i >= 0) widget.ctrl.selectAddress(i);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final unsupported = _guide.capability == HotspotCapability.unsupported;
    return Scaffold(
      appBar: AppBar(title: const Text('전용 Wi-Fi 로 연결')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _StatusCard(detected: _detected, onUse: _useDetected),
          const SizedBox(height: 16),
          Text(
            '${_guide.platformName} — ${_guide.title}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(switch (_guide.capability) {
            HotspotCapability.appManaged => '앱이 직접 켤 수 있습니다',
            HotspotCapability.guided => '설정에서 켜면 앱이 자동으로 감지합니다',
            HotspotCapability.unsupported => '',
          }, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          for (var i = 0; i < _guide.steps.length; i++)
            _StepTile(index: i + 1, step: _guide.steps[i]),
          if (_guide.caveat != null) ...[
            const SizedBox(height: 8),
            _CaveatBox(text: _guide.caveat!),
          ],
          if (_guide.expectedHint != null) ...[
            const SizedBox(height: 8),
            Text(
              _guide.expectedHint!,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          if (!unsupported) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _check,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 검색'),
            ),
            const Divider(height: 36),
            _WifiQrSection(
              ssid: _ssid,
              password: _password,
              onSsidChanged: widget.ctrl.settings.setHotspotSsid,
            ),
          ],
        ],
      ),
    );
  }
}

/// 감지 상태 — 이 화면의 결론.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.detected, required this.onUse});

  final HostAddress? detected;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final ok = detected != null;
    return Card(
      color: ok ? Colors.green.shade50 : Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              ok ? Icons.wifi_tethering : Icons.wifi_tethering_off,
              color: ok ? Colors.green.shade700 : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ok ? '핫스팟 감지됨' : '아직 핫스팟이 없습니다',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (ok)
                    Text(
                      '${detected!.ip} · ${detected!.interfaceName}',
                      style: const TextStyle(fontSize: 12),
                    )
                  else
                    const Text(
                      '아래 안내대로 켜면 자동으로 잡힙니다',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
            if (ok)
              FilledButton(onPressed: onUse, child: const Text('이 주소 사용')),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.index, required this.step});

  final int index;
  final HotspotStep step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: step.caution
                ? Colors.orange.shade100
                : Colors.blue.shade50,
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: step.caution
                    ? Colors.orange.shade900
                    : Colors.blue.shade900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              step.text.replaceAll('**', ''),
              style: TextStyle(
                fontSize: 13,
                fontWeight: step.caution ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CaveatBox extends StatelessWidget {
  const _CaveatBox({required this.text});

  final String text;

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
              text,
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
            ),
          ),
        ],
      ),
    );
  }
}

/// 참가자가 Wi-Fi 에 바로 붙게 하는 QR. 이름·암호는 호스트가 설정에서 정한 값을 옮겨 적는다
/// (플랫폼이 앱에 알려주지 않는다).
class _WifiQrSection extends StatefulWidget {
  const _WifiQrSection({
    required this.ssid,
    required this.password,
    required this.onSsidChanged,
  });

  final TextEditingController ssid;
  final TextEditingController password;
  final void Function(String) onSsidChanged;

  @override
  State<_WifiQrSection> createState() => _WifiQrSectionState();
}

class _WifiQrSectionState extends State<_WifiQrSection> {
  @override
  Widget build(BuildContext context) {
    final ssid = widget.ssid.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Wi-Fi 접속 QR (선택)',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        const Text(
          // 스캔이 두 번이라는 것을 미리 말해 준다. 안 그러면 참가자가
          // Wi-Fi QR 만 찍고 "들어와졌나?" 하고 기다린다.
          '참가자는 ① 이 QR 로 Wi-Fi 에 붙고 → ② 방 QR 로 입장합니다',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: widget.ssid,
          decoration: const InputDecoration(
            labelText: '네트워크 이름 (SSID)',
            helperText: '이름은 다음 파티에도 기억합니다 · 암호는 저장하지 않습니다',
            helperStyle: TextStyle(fontSize: 10),
            isDense: true,
          ),
          onChanged: (v) {
            widget.onSsidChanged(v);
            setState(() {});
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.password,
          decoration: const InputDecoration(
            labelText: '암호 (없으면 비워두세요)',
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        if (ssid.isNotEmpty)
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
              child: QrImageView(
                data: WifiQr.build(ssid: ssid, password: widget.password.text),
                size: 180,
              ),
            ),
          ),
      ],
    );
  }
}
