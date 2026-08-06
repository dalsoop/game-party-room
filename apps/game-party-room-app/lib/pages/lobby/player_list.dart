import 'package:flutter/material.dart';
import 'package:party_room_server/party_room_server.dart';

/// 참가자 명단 — 로비에서 "누가 들어와 있나" 를 보여주는 칸.

class PlayerList extends StatelessWidget {
  const PlayerList({super.key, required this.room, required this.statusText});

  final Room room;
  final String statusText;

  /// 끊긴 지 얼마나 됐는지 — 재접속을 기다릴지 정리할지의 판단 근거.
  static String _sinceLabel(DateTime? lastSeen) {
    if (lastSeen == null) return '연결 끊김';
    final d = DateTime.now().difference(lastSeen);
    if (d.inSeconds < 60) return '방금 끊김';
    if (d.inMinutes < 60) return '${d.inMinutes}분 전 끊김';
    return '${d.inHours}시간 전 끊김';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Player>>(
      stream: room.lobbyStream,
      initialData: room.players,
      builder: (context, snap) {
        final players = List<Player>.of(snap.data ?? const <Player>[])
          // 접속 중이 먼저 — 게임을 시작할 수 있는 인원이 먼저 보여야 한다.
          ..sort((a, b) {
            if (a.connected != b.connected) return a.connected ? -1 : 1;
            return a.nickname.compareTo(b.nickname);
          });
        final on = players.where((p) => p.connected).length;
        final off = players.length - on;

        return Column(
          children: [
            Row(
              children: [
                Text(
                  '참가자',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                _CountChip(label: '접속 $on', color: const Color(0xFF2ED573)),
                if (off > 0) ...[
                  const SizedBox(width: 6),
                  _CountChip(label: '끊김 $off', color: Colors.grey),
                ],
                const Spacer(),
                Text(
                  statusText,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF2FB3FF),
                  ),
                ),
              ],
            ),
            if (players.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'QR 스캔 대기 중…',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            for (final p in players) _PlayerRow(room: room, player: p),
            // 끊긴 참가자가 쌓이면 정원을 유령이 먹는다 — 한 번에 정리.
            if (off > 0 && room.activeGame == null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    final n = room.pruneDisconnected();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('끊긴 참가자 $n명을 정리했습니다')),
                    );
                  },
                  icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                  label: Text('끊긴 참가자 정리 ($off)'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: Color.lerp(color, Colors.black, .25),
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.room, required this.player});

  final Room room;
  final Player player;

  @override
  Widget build(BuildContext context) {
    final on = player.connected;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      // 색만으로 가르지 않는다 — 모양(채운 원/빈 원)과 문구가 함께 간다.
      leading: Icon(
        on ? Icons.circle : Icons.circle_outlined,
        size: 12,
        color: on ? const Color(0xFF2ED573) : Colors.grey,
      ),
      title: Text(
        player.nickname,
        style: TextStyle(
          color: on ? null : Colors.grey,
          decoration: on ? null : TextDecoration.lineThrough,
          decorationColor: Colors.grey.shade400,
        ),
      ),
      // 닉네임은 겹칠 수 있다 — 강퇴 같은 되돌릴 수 없는 조작을
      // 하기 전에 방이 발급한 식별자로 사람을 확인할 수 있어야 한다.
      subtitle: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            player.tag,
            style: const TextStyle(
              fontSize: 11,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (!on) ...[
            const SizedBox(width: 8),
            Text(
              PlayerList._sinceLabel(player.lastSeen),
              style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
            ),
          ],
        ],
      ),
      trailing: IconButton(
        tooltip: '강퇴',
        icon: const Icon(Icons.person_remove_outlined, size: 19),
        onPressed: () => room.kick(player.sessionToken),
      ),
    );
  }
}
