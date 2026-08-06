import 'package:flutter/material.dart';
import 'package:party_room_server/party_room_server.dart';

import '../games/game_catalog.dart';
import '../host_controller.dart';
import '../server/host_address.dart';
import 'chat_page.dart';
import 'lobby/address_and_internet.dart';
import 'lobby_page.dart';

/// 방 목록 — 앱의 집.
///
/// 예전에는 앱을 켜면 곧장 방 하나가 있었다. 친구 그룹마다 방을 따로 두고
/// 쓰려면(금요 모임·회사·가족) 그 하나가 병목이 된다 — 다른 그룹을 부르려면
/// 쓰던 방을 갈아엎어야 했다.
///
/// 이제 방은 여럿이고 **동시에 산다**. 각자 QR 을 갖고, 한 방에서 마피아가
/// 도는 동안 다른 방은 대기한다.
class RoomsPage extends StatefulWidget {
  const RoomsPage({super.key, required this.ctrl});

  final HostController ctrl;

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  HostController get ctrl => widget.ctrl;

  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// 목록 순서 — **지금 무슨 일이 일어나는 방**이 위로 온다.
  ///
  /// 만든 순서대로 두면 파티 중에 쓰는 방이 아래로 밀린다. 판이 도는 방,
  /// 사람이 있는 방, 그 다음이 나머지다. 닫힌 방은 늘 맨 아래.
  List<Room> _sorted(List<Room> rooms) {
    int rank(Room r) {
      if (!r.open) return 3;
      if (r.activeGame != null) return 0;
      if (r.players.any((p) => p.connected)) return 1;
      return 2;
    }

    final q = _query.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? rooms.toList()
        : rooms
              .where(
                (r) =>
                    r.name.toLowerCase().contains(q) ||
                    r.roomToken.toLowerCase().contains(q),
              )
              .toList();
    filtered.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return b.createdAt.compareTo(a.createdAt); // 최근 만든 것이 위
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final ready = ctrl.server != null && ctrl.error == null;
        final all = ctrl.rooms;
        final rooms = _sorted(all);
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/img/appicon.png',
                    width: 26,
                    height: 26,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 9),
                const Text('파티룸'),
              ],
            ),
            actions: [
              if (ready)
                IconButton(
                  tooltip: '단톡·자료함',
                  onPressed: () => ChatPage.open(context, ctrl),
                  icon: const Icon(Icons.forum_outlined),
                ),
              IconButton(
                tooltip: '설정',
                onPressed: () => openSettings(context, ctrl),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          floatingActionButton: ready
              ? FloatingActionButton.extended(
                  onPressed: () => _newRoom(context),
                  icon: const Icon(Icons.add),
                  label: const Text('새 방'),
                )
              : null,
          body: ctrl.error != null
              ? _error(context)
              : !ready
              // 스피너만 띄우면 왜 기다리는지 모른다.
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 14),
                      Text(
                        '방을 여는 중…',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      children: [
                        _AddressBar(ctrl: ctrl),
                        // 방이 몇 개 안 되면 검색칸이 자리만 먹는다.
                        if (all.length >= 6)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: TextField(
                              controller: _query,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                isDense: true,
                                prefixIcon: const Icon(Icons.search, size: 20),
                                hintText: '방 이름이나 코드로 찾기',
                                suffixIcon: _query.text.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.close, size: 18),
                                        onPressed: () =>
                                            setState(() => _query.clear()),
                                      ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: all.isEmpty
                              ? const _Empty()
                              : rooms.isEmpty
                              ? const Center(
                                  child: Text(
                                    '찾는 방이 없습니다',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    88,
                                  ),
                                  itemCount: rooms.length,
                                  itemBuilder: (context, i) => _RoomCard(
                                    ctrl: ctrl,
                                    room: rooms[i],
                                    onOpen: () => _enter(context, rooms[i]),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  void _enter(BuildContext context, Room room) {
    ctrl.selectRoom(room.roomToken);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LobbyPage(ctrl: ctrl)),
    );
  }

  Future<void> _newRoom(BuildContext context) async {
    final name = await _askName(context, '새 방', '');
    if (name == null) return;
    final room = ctrl.createRoom(name);
    if (!context.mounted) return;
    if (room != null) {
      _enter(context, room);
      return;
    }
    // 조용히 아무 일도 안 일어나면 호스트는 왜 안 생기는지 모른다 —
    // 서버가 정원을 이유로 거절했다는 사실을 말해 준다.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ctrl.createRoomError ?? '방을 열지 못했습니다')),
    );
  }

  Widget _error(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, size: 40, color: Colors.orange),
          const SizedBox(height: 12),
          Text(
            ctrl.error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.6),
          ),
        ],
      ),
    ),
  );
}

/// 이름 묻기 — 새 방·이름 바꾸기가 함께 쓴다.
Future<String?> _askName(
  BuildContext context,
  String title,
  String initial,
) async {
  final c = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLength: 20,
        decoration: const InputDecoration(
          hintText: '금요 모임, 회사 워크숍…',
          helperText: '비워 두면 방 코드로 부릅니다',
        ),
        onSubmitted: (v) => Navigator.pop(dialog, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialog, c.text),
          child: const Text('확인'),
        ),
      ],
    ),
  );
  c.dispose();
  return name;
}

/// 입장 비밀번호 묻기. 빈 값으로 확인하면 해제.
///
/// 방 토큰이 여전히 주 관문이고 이건 두 번째 자물쇠다 — 링크가 엉뚱한
/// 단톡방으로 넘어갔을 때를 막는 용도라는 걸 화면에서 말해 준다.
Future<String?> _askPin(BuildContext context, bool has) async {
  final c = TextEditingController();
  final pin = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(has ? '비밀번호 바꾸기' : '비밀번호 걸기'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'QR 을 찍은 사람도 이 숫자를 넣어야 들어옵니다.\n'
            '링크가 엉뚱한 단톡방으로 넘어갔을 때를 막습니다.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF5F6C82)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            maxLength: 4,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: '숫자 4자리',
              helperText: has ? '비우고 확인하면 해제됩니다' : null,
            ),
            onSubmitted: (v) => Navigator.pop(dialog, v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialog, c.text.trim()),
          child: const Text('확인'),
        ),
      ],
    ),
  );
  c.dispose();
  return pin;
}

/// 방 이름 — 비어 있으면 코드로 부른다. 화면이 붙이는 이름이다.
String roomLabel(Room room) =>
    room.name.isEmpty ? '방 ${room.roomToken}' : room.name;

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.ctrl,
    required this.room,
    required this.onOpen,
  });

  final HostController ctrl;
  final Room room;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final connected = room.players.where((p) => p.connected).length;
    final live = GameCatalog.byId(room.activeGame?.id ?? '');
    final selected = room.roomToken == ctrl.room?.roomToken;
    // 배경을 상자에 칠하고 그 안에 ListTile 을 넣으면, 누를 때 번지는
    // 물결이 상자 뒤에 가려 **아무 반응도 없어 보인다**. 배경은 Material 이
    // 칠하게 넘긴다 — 방을 눌렀는지 아닌지가 안 보이면 두 번 누르게 된다.
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        // shape 와 borderRadius 는 함께 못 준다 — 모양은 shape 하나로.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? const Color(0xFF2FB3FF) : const Color(0xFFDBE4F0),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          onTap: onOpen,
          title: Row(
            children: [
              Flexible(
                child: Text(
                  roomLabel(room),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (room.hasPin) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: Color(0xFF7C8698),
                ),
              ],
              if (!room.open) ...[
                const SizedBox(width: 8),
                const _Chip(text: '닫힘', color: Colors.grey),
              ],
              if (live != null) ...[
                const SizedBox(width: 8),
                _Chip(text: live.title, color: const Color(0xFF2FB3FF)),
              ],
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '${room.roomToken} · '
              '${connected > 0 ? "$connected명 접속" : "대기"}'
              '${room.players.length > connected ? " · 끊김 ${room.players.length - connected}" : ""}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF7C8698)),
            ),
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (v) => _menu(context, v),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'toggle',
                child: Text(room.open ? '닫기 (입장 막기)' : '열기'),
              ),
              const PopupMenuItem(value: 'rename', child: Text('이름 바꾸기')),
              PopupMenuItem(
                value: 'pin',
                child: Text(room.hasPin ? '비밀번호 바꾸기·해제' : '비밀번호 걸기'),
              ),
              const PopupMenuItem(value: 'clear', child: Text('이 방 비우기')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('방 지우기', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, String action) async {
    switch (action) {
      case 'toggle':
        // 닫힌 방은 입장도 소켓 연결도 거절한다 — 이름 붙인 방에 수명
        // 타이머를 두지 않는 대신, 이 스위치가 그 책임을 진다.
        ctrl.setRoomOpen(room.roomToken, !room.open);
      case 'rename':
        final name = await _askName(context, '이름 바꾸기', room.name);
        if (name != null) ctrl.renameRoom(room.roomToken, name);
      case 'pin':
        final messenger = ScaffoldMessenger.of(context);
        final pin = await _askPin(context, room.hasPin);
        if (pin == null) return;
        if (!ctrl.setRoomPin(room.roomToken, pin.isEmpty ? null : pin)) {
          messenger.showSnackBar(
            const SnackBar(content: Text('숫자 4자리로 넣어주세요')),
          );
          return;
        }
        messenger.showSnackBar(
          SnackBar(content: Text(pin.isEmpty ? '비밀번호를 해제했습니다' : '비밀번호를 걸었습니다')),
        );
      case 'clear':
        // 지우기와 다르다 — 토큰이 살아 있어 나눠준 QR·링크가 계속 통한다.
        final messenger = ScaffoldMessenger.of(context);
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text('${roomLabel(room)} 비우기'),
            content: const Text(
              '참가자·대화·자료를 지우고 방은 그대로 둡니다.\n'
              '나눠준 QR 과 링크는 계속 통합니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('비우기'),
              ),
            ],
          ),
        );
        if (ok != true) return;
        await ctrl.clearRoom(room.roomToken);
        messenger.showSnackBar(const SnackBar(content: Text('방을 비웠습니다')));
      case 'delete':
        final messenger = ScaffoldMessenger.of(context);
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text('${roomLabel(room)} 지우기'),
            content: const Text('참가자·대화·자료가 모두 사라지고 이 방 링크는 통하지 않게 됩니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('지우기', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (ok != true) return;
        await ctrl.deleteRoom(room.roomToken);
        messenger.showSnackBar(const SnackBar(content: Text('방을 지웠습니다')));
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.meeting_room_outlined, size: 44, color: Colors.grey),
        SizedBox(height: 12),
        Text('아직 방이 없습니다', style: TextStyle(fontSize: 15)),
        SizedBox(height: 4),
        Text(
          '[새 방] 을 눌러 하나 만드세요.\n'
          '친구 그룹마다 따로 두면 QR 도 대화도 섞이지 않습니다.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: Color(0xFF7C8698)),
        ),
      ],
    ),
  );
}

/// 지금 참가자가 붙을 주소 — **홈에 있어야 한다.**
///
/// 예전에는 방에 들어가야만 보였다. 그런데 파티에서 제일 먼저 나오는 말이
/// "뭐로 들어가?" 이고, 안 붙을 때 제일 먼저 볼 것도 "내가 어느 망에 있나"
/// 다. 방을 하나 열어야 그걸 볼 수 있으면 순서가 거꾸로다.
///
/// 특히 **VPN 이 붙어 있으면** 참가자가 닿을 수 없는 주소가 잡힐 수 있다.
/// 그때는 여기서 바로 보이고, 눌러서 바꿀 수 있어야 한다.
class _AddressBar extends StatelessWidget {
  const _AddressBar({required this.ctrl});

  final HostController ctrl;

  @override
  Widget build(BuildContext context) {
    final a = ctrl.address;
    final external = ctrl.usingExternal;
    // 참가자가 못 닿을 수 있는 주소인가 — 그러면 조용히 두면 안 된다.
    final risky = !external && a != null && a.kind == HostAddressKind.tunnel;
    final none = !external && a == null;

    final text = external
        ? ctrl.externalBase!
        : a == null
        ? '접속할 수 있는 주소가 없습니다'
        : '${a.ip}:${ctrl.server?.port ?? 8765}';
    final sub = external ? '인터넷으로 열려 있음' : a?.label ?? 'Wi-Fi 를 켜거나 핫스팟을 켜세요';

    final tone = none || risky ? Colors.orange : Colors.blueGrey;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: (none || risky)
            ? Colors.orange.withValues(alpha: 0.08)
            : const Color(0xFFF2F6FC),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          // 주소를 바꾸는 곳은 이미 있다 — 여기서는 그리로 보내기만 한다.
          onTap: () => showAddressPicker(context, ctrl),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  none || risky
                      ? Icons.warning_amber_rounded
                      : external
                      ? Icons.public
                      : Icons.wifi,
                  size: 18,
                  color: tone,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: tone == Colors.orange
                              ? Colors.orange.shade900
                              : const Color(0xFF25324A),
                        ),
                      ),
                      Text(
                        sub,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF7C89B4),
                        ),
                      ),
                    ],
                  ),
                ),
                if (ctrl.addresses.length > 1 || none)
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Color(0xFF7C89B4),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
