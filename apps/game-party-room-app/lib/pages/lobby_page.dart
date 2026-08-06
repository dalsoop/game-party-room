import 'package:party_room_server/party_room_server.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../games/game_catalog.dart';
import '../host_controller.dart';
import 'chat_page.dart';
import 'lobby/address_and_internet.dart';
import 'lobby/player_list.dart';
import 'help_page.dart';
import 'hotspot_page.dart';
import 'settings_page.dart';

/// 접속 주소 고르기.
///
/// 호스트에 인터페이스가 여러 개면(Wi-Fi + VPN + 핫스팟) 어느 주소가 참가자에게
/// 닿는지는 자리마다 다르다. "안 붙어요" 가 나왔을 때 호스트가 바로 바꿀 수 있게 둔다.

/// 로비: QR + 참가자 + 게임 선택. 게임 시작 시 해당 게임 페이지로 push.
class LobbyPage extends StatefulWidget {
  const LobbyPage({super.key, required this.ctrl});

  final HostController ctrl;

  @override
  State<LobbyPage> createState() => _LobbyPageState();
}

class _LobbyPageState extends State<LobbyPage> {
  HostController get ctrl => widget.ctrl;
  bool _resumedToGame = false;

  @override
  void initState() {
    super.initState();
    // 복구된 게임이 있으면 해당 게임 페이지로 자동 진입
    ctrl.addListener(_maybeResumeGame);
  }

  @override
  void dispose() {
    ctrl.removeListener(_maybeResumeGame);
    super.dispose();
  }

  /// 복구된 판이 있으면 그 화면으로 자동 진입.
  ///
  /// 어느 종목인지는 **카탈로그에 묻는다** — 예전에는 여기에 마피아·라이어·
  /// 투표만 손으로 나열돼 있어서, 구슬·사다리는 판이 돌고 있어도 돌아갈
  /// 길이 없었다. 종목이 늘 때 이 파일을 고치지 않는 것이 목적이다.
  void _maybeResumeGame() {
    if (_resumedToGame || !mounted) return;
    if (ctrl.server == null || ctrl.url == null) return;
    final entry = GameCatalog.liveOf(ctrl);
    if (entry == null) return;
    _resumedToGame = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      openLiveGame(context, ctrl, entry).then((_) => _resumedToGame = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/img/app_emblem.jpg',
                width: 30,
                height: 30,
              ),
            ),
            const SizedBox(width: 8),
            const Text('파티룸'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '도움말',
            onPressed: () => HelpPage.open(context),
            icon: const Icon(Icons.help_outline),
          ),
          IconButton(
            tooltip: '설정',
            onPressed: () => openSettings(context, ctrl),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          if (ctrl.error != null) return Center(child: Text(ctrl.error!));
          if (ctrl.url == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _body(context);
        },
      ),
    );
  }

  Widget _body(BuildContext context) {
    final room = ctrl.room!;
    // 창이 넓으면(데스크톱·TV 진행판) 세로 한 줄로 늘어놓지 않는다 —
    // 왼쪽에 방 정보·참가자, 오른쪽에 게임 그리드. 스크롤 없이 다 보인다.
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 980
          ? _wideBody(context, room)
          : _narrowBody(context, room),
    );
  }

  /// QR·방 코드·주소 — 두 레이아웃이 함께 쓴다.
  Widget _roomInfo(BuildContext context, Room room, double qrSize) {
    return Column(
      children: [
        if (ctrl.restored)
          const Chip(
            label: Text('이전 방 복구됨'),
            avatar: Icon(Icons.restore, size: 18),
          ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A1D2B50),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: QrImageView(data: ctrl.url!, size: qrSize),
        ),
        const SizedBox(height: 6),
        Text(
          '방 코드: ${room.roomToken}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        SelectableText(
          ctrl.url!,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        AddressPicker(ctrl: ctrl),
      ],
    );
  }

  /// QR 을 얼마나 크게 그릴지.
  ///
  /// 예전에는 `width > 700 ? 280 : 130` 이었다 — **폭으로 세로 예산을 정하고
  /// 있었다.** 그 결과 기본 창(800×632)에서 가장 큰 QR 이 걸려, 참가자 목록도
  /// 게임 목록도 스크롤 밖으로 밀려났다(실측: 4명이 들어와 있는데 호스트
  /// 화면에는 QR 과 방 코드밖에 안 보였다).
  ///
  /// 이제 두 가지를 본다 —
  /// - **세로 여유**: 높이의 1/3 을 넘지 않는다.
  /// - **아무도 안 들어왔는가**: 빈 방에서는 QR 이 주인공이지만, 들어오고
  ///   나면 누가 왔는지와 무엇을 할지가 더 급하다.
  static double _qrSize(BuildContext context, int connected) {
    final budget = MediaQuery.of(context).size.height * 0.34;
    return budget.clamp(120.0, connected == 0 ? 280.0 : 190.0);
  }

  Widget _narrowBody(BuildContext context, Room room) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              _roomInfo(
                context,
                room,
                _qrSize(context, ctrl.games.connectedCount),
              ),
              const Divider(height: 24),
              // 인원은 파티 내내 호스트가 제일 자주 보는 숫자다. 좁은
              // 레이아웃에서는 참가자 목록이 게임 목록 아래에 있어서, 이게
              // 없으면 몇 명 들어왔는지 보려고 카드 다섯 장을 지나쳐야 한다.
              Row(
                children: [
                  const Text(
                    '게임 선택',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    '${ctrl.games.connectedCount}명 접속 중',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF2FB3FF),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (GameCatalog.liveOf(ctrl) case final live?)
                _LiveGameBar(ctrl: ctrl, entry: live),
              // 종목 목록은 GameCatalog 가 정본 — 여기서 게임을 나열하지 않는다.
              for (final game in GameCatalog.all)
                _GameBanner(
                  image: game.bannerAsset,
                  title: game.title,
                  sub: game.subtitle,
                  // 눌러보고 스낵바로 알게 하지 않는다 — 미리 보여준다.
                  ready:
                      ctrl.games.connectedCount >= game.meta.minPlayers &&
                      GameCatalog.liveOf(ctrl) == null,
                  shortBy: game.meta.minPlayers - ctrl.games.connectedCount,
                  onTap: () => game.open(context, ctrl),
                ),
              const Divider(height: 24),
              PlayerList(room: room, statusText: ctrl.games.gameStatus),
              const SizedBox(height: 10),
              _ChatEntry(ctrl: ctrl, room: room),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wideBody(BuildContext context, Room room) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 방 정보 + 참가자 — 고정 폭. QR 는 참가자가 멀리서 찍는 물건이라
        // 넓은 화면에서도 크기를 유지한다.
        SizedBox(
          width: 400,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _roomInfo(context, room, 240),
                const Divider(height: 28),
                PlayerList(room: room, statusText: ctrl.games.gameStatus),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        // 게임 그리드 — 남는 폭을 카드가 나눠 갖는다.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
                child: Row(
                  children: [
                    const Text(
                      '게임 선택',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${ctrl.games.connectedCount}명 접속 중',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF2FB3FF),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (GameCatalog.liveOf(ctrl) case final live?)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                  child: _LiveGameBar(ctrl: ctrl, entry: live),
                ),
              Expanded(
                child: GridView.extent(
                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 12),
                  maxCrossAxisExtent: 520,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 2.4,
                  children: [
                    for (final game in GameCatalog.all)
                      _GameBanner(
                        image: game.bannerAsset,
                        title: game.title,
                        sub: game.subtitle,
                        ready:
                            ctrl.games.connectedCount >= game.meta.minPlayers &&
                            GameCatalog.liveOf(ctrl) == null,
                        shortBy:
                            game.meta.minPlayers - ctrl.games.connectedCount,
                        onTap: () => game.open(context, ctrl),
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
              // 단톡과 자료함 — 파티의 상시 채널이라 로비에 늘 보인다.
              SizedBox(
                height: 252,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [const SizedBox(width: 14), SizedBox(width: 320)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GameBanner extends StatelessWidget {
  const _GameBanner({
    required this.image,
    required this.title,
    required this.sub,
    required this.onTap,
    this.ready = true,
    this.shortBy = 0,
    this.padding = const EdgeInsets.only(bottom: 12),
  });

  final String image;
  final String title;
  final String sub;
  final VoidCallback onTap;

  /// 목록에선 아래 간격, 그리드에선 0 — 간격은 그리드가 관리한다.
  final EdgeInsetsGeometry padding;

  /// 지금 인원으로 시작할 수 있는가.
  final bool ready;

  /// 몇 명 모자라는가(시작 가능하면 0 이하).
  final int shortBy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: 2.4,
                child: Image.asset(image, fit: BoxFit.cover),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: .65),
                      ],
                      stops: const [.45, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: ready
                        ? const Color(0xFF2ED573).withValues(alpha: .9)
                        : Colors.black.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    ready ? '시작 가능' : '$shortBy명 더 필요',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 10,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            sub,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.play_circle_fill,
                      color: Color(0xFF2FB3FF),
                      size: 34,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 원클릭 인터넷 개방.
///
/// cloudflared 가 있으면 즉시 터널을 띄우고, 없으면 설치 한 줄을 복사
/// 버튼과 함께 보여 준다 — 터미널에 명령을 "쳐 보라" 고 하는 것과
/// 붙여넣게 하는 것 사이의 거리가 판매 가능/불가의 거리다.

/// 터널 주소 입력/해제 — 로비 링크와 설정 화면이 함께 쓴다.

/// 접속 주소 후보 시트 — 로비 링크와 설정 화면이 함께 쓴다.

/// 그 방의 단톡·자료함으로 가는 입구.
///
/// 대화와 자료는 이제 로비에 얹힌 카드가 아니라 자기 자리가 있다
/// ([ChatPage]) — 여기서는 있다는 사실과 최근 기록 수만 알린다.
class _ChatEntry extends StatelessWidget {
  const _ChatEntry({required this.ctrl, required this.room});

  final HostController ctrl;
  final Room room;

  @override
  Widget build(BuildContext context) {
    final msgs = room.channels.sections.fold<int>(
      0,
      (n, s) => n + s.messages.length,
    );
    final files = room.sharedFiles.length;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDBE4F0)),
      ),
      child: ListTile(
        leading: const Icon(Icons.forum_outlined),
        title: const Text('단톡·자료함', style: TextStyle(fontSize: 14.5)),
        subtitle: Text(
          msgs == 0 && files == 0
              ? '참가자 폰의 말풍선 버튼과 이어집니다'
              : '대화 $msgs · 자료 $files',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => ChatPage.open(context, ctrl),
      ),
    );
  }
}

/// 설정 열기 — 방 목록과 로비가 함께 쓴다.
void openSettings(BuildContext context, HostController ctrl) => Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => SettingsPage(
      ctrl: ctrl,
      onOpenAddress: () => showAddressPicker(context, ctrl),
      onOpenExternal: () => showExternalUrlDialog(context, ctrl),
      onOpenHotspot: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => HotspotPage(ctrl: ctrl)),
      ),
    ),
  ),
);

/// 진행 중인 판의 화면으로 (재)진입한다.
///
/// 어느 화면인지는 종목이 [GameEntry.livePage] 로 선언한다 — 로비는 종목을
/// 모른다.
Future<void> openLiveGame(
  BuildContext context,
  HostController ctrl,
  GameEntry entry,
) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => entry.livePage(ctrl)),
);

/// "판이 돌고 있다" 를 로비에 세운다.
///
/// 이게 없으면 화면을 벗어난 호스트가 돌아갈 길도, 판이 살아 있다는 사실을
/// 알 방법도 없다 — 참가자 폰은 대기 화면인데 로비는 평소와 똑같아 보인다.
class _LiveGameBar extends StatelessWidget {
  const _LiveGameBar({required this.ctrl, required this.entry});

  final HostController ctrl;
  final GameEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2436),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.play_circle_fill,
            color: Color(0xFF2FB3FF),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.title} 진행 중',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (ctrl.games.gameStatus.isNotEmpty)
                  Text(
                    ctrl.games.gameStatus,
                    style: const TextStyle(
                      color: Color(0xFF9AA7BC),
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => openLiveGame(context, ctrl, entry),
            child: const Text('이어서 보기'),
          ),
          TextButton(
            onPressed: () => ctrl.games.endGame(),
            child: const Text(
              '판 끝내기',
              style: TextStyle(color: Color(0xFFFF8A8A)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 칸·발화자의 **표시 이름**은 화면이 붙인다.
///
/// 서버(party_room_server)는 Flutter 를 모르는 순수 Dart 라 `kind`·`gameName`·
/// `round`·`speaker` 같은 사실만 싣는다. 여기서 사람이 읽는 말로 옮긴다 —
/// 참가자 SPA 의 `labelOf`/`speakerName` 과 같은 규칙이다.
String sectionLabel(ChatSection s) => s.kind == SectionKind.room
    ? '전체'
    : '${s.gameName ?? "게임"} ${s.round ?? 1}판';

String speakerLabel(Map<String, dynamic> m) => switch (m['speaker']) {
  Speaker.host => '호스트',
  Speaker.mc => '사회자',
  _ => (m['nickname'] as String?) ?? '',
};

/// 칸 고르기 — 단톡·자료함이 함께 쓴다.
///
/// '전체' 는 방이 열려 있는 내내 살고, 판마다 칸이 하나씩 열린다. 끝난 판은
/// 흐리게 두되 지우지 않는다 — 나중에 그 판만 펼쳐 보는 게 이 구조의 목적이다.

/// 단톡 — 호스트도 같은 방 채널로 말한다.

/// 자료함 — 호스트가 파일을 올리고, 참가자 업로드도 여기 나타난다.
///
/// 단톡과 같은 칸을 쓴다: 판마다 자기 자료가 모이고, 파티가 끝난 뒤
/// "마피아 3판 때 찍은 사진" 을 그 칸에서 바로 찾는다.
