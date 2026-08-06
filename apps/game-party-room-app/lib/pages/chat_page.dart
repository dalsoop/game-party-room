import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:party_room_server/party_room_server.dart';

import '../host_controller.dart';
import 'lobby_page.dart' show sectionLabel, speakerLabel;
import 'rooms_page.dart' show roomLabel;

/// 단톡·자료함 — 로비에서 떼어낸 자기 자리.
///
/// 예전에는 로비 아래쪽 카드 두 장이었다. 파티 한 번 하고 끝나는 물건이면
/// 그걸로 됐는데, 친구들과 계속 쓰는 쪽으로 가면 대화와 자료가 **로비에
/// 얹힌 부속**이 아니라 그 자체로 찾아 들어가는 곳이 된다.
///
/// 방을 고르면 그 방의 칸(전체 + 판별)으로 통째로 바뀐다. 서로 다른 친구
/// 그룹의 대화가 한 화면에 섞이지 않는다.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.ctrl});

  final HostController ctrl;

  static void open(BuildContext context, HostController ctrl) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ChatPage(ctrl: ctrl)),
  );

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  HostController get ctrl => widget.ctrl;

  final _input = TextEditingController();
  final _scroll = ScrollController();

  String? _roomToken;
  String? _sectionId;
  bool _files = false;

  @override
  void initState() {
    super.initState();
    _roomToken = ctrl.room?.roomToken;
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 이 화면이 보고 있는 방.
  ///
  /// 열 때 보던 방으로 시작하고(initState), 그 뒤로는 **이 화면의 고르개가
  /// 정한다** — 단톡은 따로 열어 두고 다른 방을 보는 자리라 로비를 따라
  /// 움직이면 안 된다.
  ///
  /// 고른 방이 지워졌으면 보던 방으로, 그것도 없으면 아무 방으로 물러난다.
  Room? get _room =>
      ctrl.server?.byToken(_roomToken) ?? ctrl.room ?? ctrl.rooms.firstOrNull;

  String get _section {
    final r = _room;
    if (r == null) return RoomChannels.roomId;
    return r.channels.byId(_sectionId)?.id ?? r.channels.defaultId;
  }

  bool get _writable {
    final s = _room?.channels.byId(_section);
    return s == null || s.kind == SectionKind.room || s.live;
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty || !_writable) return;
    _room?.hostChat(text, sectionId: _section);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final room = _room;
        return Scaffold(
          appBar: AppBar(
            title: const Text('단톡·자료함'),
            actions: [
              if (room != null && ctrl.rooms.length > 1)
                PopupMenuButton<String>(
                  tooltip: '방 고르기',
                  onSelected: (t) => setState(() {
                    _roomToken = t;
                    _sectionId = null;
                  }),
                  itemBuilder: (_) => [
                    for (final r in ctrl.rooms)
                      PopupMenuItem(
                        value: r.roomToken,
                        child: Text(roomLabel(r)),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(roomLabel(room)),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          body: room == null
              ? const Center(
                  child: Text('방이 없습니다', style: TextStyle(color: Colors.grey)),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      children: [
                        if (ctrl.rooms.length == 1)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                roomLabel(room),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF5F6C82),
                                ),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                          child: _SectionTabs(
                            room: room,
                            selected: _section,
                            onSelect: (id) => setState(() => _sectionId = id),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, label: Text('대화')),
                              ButtonSegment(value: true, label: Text('자료')),
                            ],
                            selected: {_files},
                            onSelectionChanged: (v) =>
                                setState(() => _files = v.first),
                          ),
                        ),
                        Expanded(
                          child: _files
                              ? _filesView(context, room)
                              : _chatView(room),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _chatView(Room room) {
    final msgs = room.chatHistoryOf(_section);
    return Column(
      children: [
        Expanded(
          child: msgs.isEmpty
              ? Center(
                  child: Text(
                    room.channels.byId(_section)?.kind == SectionKind.game
                        ? '이 판의 대화가 여기 남습니다'
                        : '참가자 폰의 말풍선 버튼과 이어집니다',
                    style: const TextStyle(color: Colors.grey, fontSize: 12.5),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) => _Message(msg: msgs[i]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: _writable,
                  maxLength: room.limits.chatTextLength,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: _writable
                        ? '${sectionLabel(room.channels.byId(_section)!)}에 보내기'
                        : '끝난 판입니다 — 읽기만 됩니다',
                  ),
                ),
              ),
              IconButton(
                onPressed: _writable ? _send : null,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filesView(BuildContext context, Room room) {
    final files = room.sharedFilesIn(_section);
    return Column(
      children: [
        Expanded(
          child: files.isEmpty
              ? const Center(
                  child: Text(
                    '이 칸에 파일을 공유하면 전원 폰에 뜹니다',
                    style: TextStyle(color: Colors.grey, fontSize: 12.5),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  itemCount: files.length,
                  itemBuilder: (context, i) {
                    final f = files[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.insert_drive_file_outlined,
                        size: 20,
                      ),
                      title: Text(
                        f.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      subtitle: Text(
                        '${f.ownerName.isEmpty ? "호스트" : f.ownerName}'
                        ' · ${(f.size / 1024).round()}KB',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: IconButton(
                        tooltip: '공유 내리기',
                        icon: const Icon(Icons.close, size: 17),
                        onPressed: () => ctrl.removeSharedFile(f.id),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(
            children: [
              if (files.isNotEmpty)
                TextButton(
                  onPressed: () => _clear(context, room, files.length),
                  child: const Text('이 칸 비우기'),
                ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _writable ? () => _share(context) : null,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('파일 공유'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await openFiles();
    if (picked.isEmpty) return;
    final n = await ctrl.shareFiles([
      for (final f in picked) f.path,
    ], sectionId: _section);
    messenger.showSnackBar(SnackBar(content: Text('$n개 파일을 공유했습니다')));
  }

  Future<void> _clear(BuildContext context, Room room, int count) async {
    final messenger = ScaffoldMessenger.of(context);
    final label = sectionLabel(room.channels.byId(_section)!);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('$label 자료 비우기'),
        content: Text('$count개를 지웁니다. 참가자 폰에서도 사라집니다.'),
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
    final n = await ctrl.clearSectionFiles(_section);
    messenger.showSnackBar(SnackBar(content: Text('$n개를 지웠습니다')));
  }
}

/// 칸 고르기 — '전체' 는 스크롤 밖에 고정한다.
///
/// 판이 몇 번 돌면 탭이 넘치고, 스크롤하면 맨 왼쪽 '전체' 가 사라진다.
/// 하필 그게 끝난 판을 보고 있을 때 유일하게 쓸 수 있는 칸이다.
class _SectionTabs extends StatelessWidget {
  const _SectionTabs({
    required this.room,
    required this.selected,
    required this.onSelect,
  });

  final Room room;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final sections = room.channels.sections;
    final rest = sections.skip(1).toList();
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          _chip(sections.first),
          if (rest.isNotEmpty) const SizedBox(width: 6),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: rest.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) => _chip(rest[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(ChatSection s) {
    final sel = s.id == selected;
    final done = s.kind == SectionKind.game && !s.live;
    return GestureDetector(
      onTap: () => onSelect(s.id),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF1B2436) : const Color(0xFFEFF3F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          sectionLabel(s),
          style: TextStyle(
            fontSize: 12,
            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
            color: sel
                ? Colors.white
                : (done ? Colors.grey : const Color(0xFF5F6C82)),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.msg});
  final Map<String, dynamic> msg;

  @override
  Widget build(BuildContext context) {
    final speaker = msg['speaker'] as String? ?? Speaker.player;
    final staff = speaker != Speaker.player;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            speakerLabel(msg),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: switch (speaker) {
                Speaker.host => const Color(0xFF0E7FC4),
                Speaker.mc => const Color(0xFF7A5AF8),
                _ => const Color(0xFF1C2333),
              },
            ),
          ),
          if (!staff) ...[
            const SizedBox(width: 4),
            Text(
              msg['tag'] as String? ?? '',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg['text'] as String? ?? '',
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}
