import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../host_controller.dart';
import '../../server/host_address.dart';
import '../../server/tunnel_service.dart';
import '../hotspot_page.dart';
import '../relay_page.dart';

/// 참가자가 들어올 **주소**를 고르고 알리는 화면들.
///
/// 로비에서 떼어 냈다. 이건 파티 진행이 아니라 네트워크 이야기다 — 어느
/// 랜카드로 열지, 인터넷으로 열지, 죽은 터널 주소를 어떻게 알릴지. 한
/// 파일에 있을 때는 1,200줄이라 둘이 섞여 읽혔다.

class AddressPicker extends StatelessWidget {
  const AddressPicker({super.key, required this.ctrl});

  final HostController ctrl;

  static final _linkStyle = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  Widget build(BuildContext context) {
    // 지난 파티의 저장분을 버리고 새로 열었다 — 옛 링크가 안 통한다는 뜻이라
    // 손님이 "왜 안 들어가져요" 하기 전에 호스트가 먼저 알아야 한다.
    if (ctrl.prunedOnLoad > 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Text(
              '오래 안 보인 참가자 ${ctrl.prunedOnLoad}명을 명단에서 정리했습니다',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            TextButton(
              style: _linkStyle,
              onPressed: () => ctrl.dismissFreshRoomNotice(),
              child: const Text('확인', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      );
    }

    // 지난번에 앱이 그냥 꺼져서 터널이 살아남아 있었다. 방이 인터넷에
    // 열린 채였다는 뜻이라 말없이 넘기지 않는다 — 지금은 닫힌 상태다.
    if (ctrl.reapedOrphanTunnel) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Text(
              '지난 실행에서 열려 있던 인터넷 터널을 닫았습니다',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton(
              style: _linkStyle,
              onPressed: () => ctrl.dismissOrphanNotice(),
              child: const Text('확인', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      );
    }

    // 저장된 인터넷 주소가 죽어 있다 — QR 는 이미 로컬 주소로 물러났고,
    // 여기서 이유를 말해 준다. 조용히 물러나기만 하면 호스트가
    // "왜 인터넷 주소가 아니지?" 하고 헤맨다.
    if (ctrl.externalBase != null && ctrl.externalDead) {
      return Column(
        children: [
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              Text(
                '저장된 인터넷 주소가 응답하지 않아 로컬 주소로 전환했습니다',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                style: _linkStyle,
                onPressed: () => ctrl.recheckExternal(),
                child: const Text('다시 확인', style: TextStyle(fontSize: 11)),
              ),
              TextButton(
                style: _linkStyle,
                onPressed: () => _editExternal(context),
                child: const Text('주소 바꾸기', style: TextStyle(fontSize: 11)),
              ),
              TextButton(
                style: _linkStyle,
                onPressed: () => ctrl.setExternalBase(null),
                child: const Text('해제', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      );
    }

    if (ctrl.usingExternal) {
      return Column(
        children: [
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              Text(
                ctrl.tunnelRunning
                    ? '인터넷 개방 중 · 어디서든 접속 가능'
                    : '인터넷 주소 · 어디서든 접속 가능',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (ctrl.tunnelRunning)
                TextButton(
                  style: _linkStyle,
                  onPressed: () => ctrl.stopTunnel(),
                  child: const Text('끄기', style: TextStyle(fontSize: 11)),
                )
              else
                TextButton(
                  style: _linkStyle,
                  onPressed: () => _editExternal(context),
                  child: const Text('바꾸기', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ],
      );
    }

    final current = ctrl.address;
    if (current == null) {
      // 예전에는 여기서 통째로 사라졌다. 그런데 **주소가 없을 때가**
      // 전용 Wi-Fi 안내가 필요한 바로 그 순간이다 — 사라지고 나면 그리로
      // 가는 길이 앱 어디에도 없어서, 호스트는 "아무도 못 들어와" 앞에서
      // 할 수 있는 게 없었다.
      return Column(
        children: [
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              Text(
                '접속할 수 있는 주소가 없습니다',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                style: _linkStyle,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => HotspotPage(ctrl: ctrl)),
                ),
                child: const Text(
                  '전용 Wi-Fi 만들기',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                style: _linkStyle,
                onPressed: () => ctrl.refreshAddresses(),
                child: const Text('다시 검색', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      );
    }
    final warn = current.kind == HostAddressKind.tunnel;

    return Column(
      children: [
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Text(
              '${current.label} · ${current.interfaceName}',
              style: TextStyle(
                fontSize: 11,
                color: warn ? Colors.orange.shade800 : Colors.grey,
                fontWeight: warn ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (ctrl.addresses.length > 1)
              TextButton(
                style: _linkStyle,
                onPressed: () => _pick(context),
                child: const Text('주소 바꾸기', style: TextStyle(fontSize: 11)),
              ),
            TextButton(
              style: _linkStyle,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => HotspotPage(ctrl: ctrl)),
              ),
              child: const Text(
                '안 붙어요 · 전용 Wi-Fi',
                style: TextStyle(fontSize: 11),
              ),
            ),
            TextButton(
              style: _linkStyle,
              onPressed: ctrl.tunnelStarting
                  ? null
                  : () => openInternetAccess(context, ctrl),
              child: Text(
                ctrl.tunnelStarting ? '인터넷 개방 중…' : '인터넷으로 열기',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        if (warn)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              'VPN 주소입니다 — 같은 자리 참가자는 닿지 못합니다',
              style: TextStyle(fontSize: 10, color: Colors.orange),
            ),
          ),
      ],
    );
  }

  /// 터널 주소 입력/해제.
  Future<void> _editExternal(BuildContext context) =>
      showExternalUrlDialog(context, ctrl);

  Future<void> _pick(BuildContext context) => showAddressPicker(context, ctrl);
}

Future<void> openInternetAccess(
  BuildContext context,
  HostController ctrl,
) async {
  if (!TunnelService.installed) {
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('인터넷으로 열기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '같은 Wi-Fi 밖의 참가자도 접속하려면 무료 도구 '
              'cloudflared 가 필요합니다.\n\n'
              '터미널을 열고 아래 한 줄을 붙여넣어 설치한 뒤 다시 눌러 주세요.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    color: const Color(0xFFEEF3FA),
                    child: const Text(
                      TunnelService.installCommand,
                      style: TextStyle(fontFamily: 'Menlo', fontSize: 12.5),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '복사',
                  icon: const Icon(Icons.copy, size: 17),
                  onPressed: () => Clipboard.setData(
                    const ClipboardData(text: TunnelService.installCommand),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.pop(dialog);
                showExternalUrlDialog(context, ctrl);
              },
              child: const Text(
                '이미 터널 주소가 있어요 — 직접 입력',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
    return;
  }

  final fail = await ctrl.startTunnel();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(fail ?? '인터넷 개방 완료 — QR 이 새 주소로 바뀌었습니다')),
  );
}

Future<void> showExternalUrlDialog(
  BuildContext context,
  HostController ctrl,
) async {
  final field = TextEditingController(text: ctrl.externalBase ?? '');
  String? errorText;
  await showDialog<void>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setLocal) => AlertDialog(
        title: const Text('인터넷 주소로 열기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '호스트에서 터널을 띄운 뒤 나온 주소를 붙여넣으세요.\n'
              '예: cloudflared tunnel --url http://localhost:8765',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: field,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'https://xxxx.trycloudflare.com',
                isDense: true,
                errorText: errorText,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ctrl.setExternalBase(null);
              Navigator.pop(dialog);
            },
            child: const Text('해제 (로컬 주소로)'),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.setExternalBase(field.text)) {
                Navigator.pop(dialog);
              } else {
                setLocal(() => errorText = '주소 형식이 올바르지 않습니다');
              }
            },
            child: const Text('사용'),
          ),
        ],
      ),
    ),
  );
  field.dispose();
}

Future<void> showAddressPicker(
  BuildContext context,
  HostController ctrl,
) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      // 주소가 여럿인 맥(유선·Wi-Fi·VPN·bridge…)에서는 목록이 길어져
      // 시트 높이를 넘긴다. 넘치면 노란 줄무늬가 뜨고 아래 항목은 **누를 수도
      // 없다** — 하필 거기 있는 것이 "전용 Wi-Fi"·"인터넷으로 열기" 다.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('접속 주소 선택'),
              subtitle: Text('참가자가 붙지 못하면 다른 주소를 골라보세요'),
            ),
            for (var i = 0; i < ctrl.addresses.length; i++)
              ListTile(
                leading: Icon(
                  i == ctrl.addressIndex
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                ),
                title: Text(ctrl.addresses[i].ip),
                subtitle: Text(
                  '${ctrl.addresses[i].label} · ${ctrl.addresses[i].interfaceName}',
                ),
                onTap: () {
                  ctrl.selectAddress(i);
                  Navigator.pop(sheet);
                },
              ),
            TextButton.icon(
              onPressed: () async {
                await ctrl.refreshAddresses();
                if (sheet.mounted) Navigator.pop(sheet);
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('네트워크 다시 검색 (핫스팟 켠 뒤)'),
            ),
            const Divider(height: 8),
            // 이 시트는 홈 화면의 주소 줄에서도 열린다. 여기 없으면 주소가
            // 하나도 안 잡힐 때 — 전용 Wi-Fi 가 정확히 필요한 그 상황에 —
            // 안내로 가는 길이 앱 어디에도 없다.
            ListTile(
              leading: const Icon(Icons.wifi_tethering, size: 20),
              title: const Text('전용 Wi-Fi 만들기'),
              subtitle: const Text('공유기 없이 참가자를 내 기기에 직접 붙인다'),
              onTap: () {
                Navigator.pop(sheet);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => HotspotPage(ctrl: ctrl)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload, size: 20),
              title: const Text('밖에 있는 사람 들이기'),
              subtitle: const Text('랑데부 서버로 나가서 붙는다 · 포트를 안 연다'),
              onTap: () {
                Navigator.pop(sheet);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => RelayPage(ctrl: ctrl)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.public, size: 20),
              title: const Text('인터넷으로 열기 (자동)'),
              subtitle: const Text('버튼 한 번으로 어느 망에서든 접속되게 엽니다'),
              onTap: () {
                Navigator.pop(sheet);
                openInternetAccess(context, ctrl);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link, size: 20),
              title: const Text('터널 주소 직접 입력'),
              subtitle: const Text('이미 띄워 둔 터널이 있을 때'),
              onTap: () {
                Navigator.pop(sheet);
                showExternalUrlDialog(context, ctrl);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}
