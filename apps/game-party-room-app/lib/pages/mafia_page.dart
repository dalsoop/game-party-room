import 'package:flutter/material.dart';
import 'package:party_room_server/party_room_server.dart';

import '../host_controller.dart';
import 'host_hud.dart';
import 'secret_veil.dart';

/// 마피아 — 호스트 진행 화면.
///
/// 큰 화면에서 사회자가 보는 판이라 구슬 룰렛·사다리타기와 같은 네온 HUD
/// 어법을 쓴다([host_hud.dart]). 밤에는 강조색이 가라앉는다.
///
/// 배치의 뼈대는 **조종석**이다: 위에 지금 상황(상태 줄·사회자 대사),
/// 가운데에 명단, 아래에 조작. 예전에는 맨 위 150px 이 장식 사진이었고,
/// 화면에서 제일 밝고 제일 큰 것이 눌러야 할 버튼이 아니라 사진이었다.
/// 게다가 "누가 살아 있나" 가 화면 어디에도 없었다 — 그걸 말해야 하는
/// 사람이 못 보는 화면이었다. 규칙은 `mafia_page_layout_test.dart` 가 잰다.
class MafiaPage extends StatelessWidget {
  const MafiaPage({super.key, required this.ctrl});

  final HostController ctrl;

  /// 로비에서 진입 — 인원이 모자라면 안내만 하고 넘어가지 않는다.
  static void startFlow(BuildContext context, HostController ctrl) {
    if (!ctrl.games.startMafia()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('마피아는 4명 이상 필요합니다')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MafiaPage(ctrl: ctrl)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        // 게임이 꺼졌으면 로비로 복귀
        if (ctrl.games.mafia == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          });
          return const SizedBox.shrink();
        }
        final phase = ctrl.games.mafiaPhase;
        final isNight = phase == 'night';

        return HudScaffold(
          title: '마피아',
          subtitle: _phaseLabel(phase),
          onEnd: () {
            ctrl.games.endGame();
            Navigator.pop(context);
          },
          body: LayoutBuilder(
            builder: (context, box) {
              // 칸 수는 폭이 정한다(그리드 delegate). 조작은 어느 폭에서든
              // 맨 아래 같은 자리에 있어야 어두운 방에서 안 보고도 누른다.
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HudStatusStrip(
                      text: ctrl.games.gameStatus.isEmpty
                          ? '진행 중'
                          : ctrl.games.gameStatus,
                      accent: isNight ? const Color(0xFF7FD4FF) : HostHud.sky,
                    ),
                    HudMcLine(line: ctrl.mcLine),
                    const SizedBox(height: 14),
                    // 화면의 본문은 명단이다 — 사회자가 내내 보는 것.
                    //
                    // 남는 자리는 **명단 뒤로** 몰아 준다. Spacer 를 형제로
                    // 두면 둘이 공간을 반씩 나눠 가져, 인원이 많을 때 명단이
                    // 이유 없이 잘린다(실측: 700px 에서 셋째 줄이 잘렸다).
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: _roster(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ..._phaseButtons(context),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  static String _phaseLabel(String phase) => switch (phase) {
    'role' => '역할 배정',
    'night' => '밤',
    'day' => '낮',
    'vote' => '투표',
    'vote_closed' => '투표 결과',
    'ended' => '종료',
    _ => '',
  };

  List<Widget> _phaseButtons(BuildContext context) {
    final phase = ctrl.games.mafiaPhase;
    Widget btn(IconData icon, String label, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HudButton(icon: icon, label: label, onPressed: onTap),
    );

    return [
      if (phase == 'role' || phase == 'vote_closed')
        btn(Icons.nightlight_round, '밤 시작', ctrl.games.mafiaNight),
      if (phase == 'night')
        btn(Icons.wb_sunny, '낮 시작 (밤 결과 발표)', ctrl.games.mafiaDay),
      if (phase == 'day') btn(Icons.how_to_vote, '투표 시작', ctrl.games.mafiaVote),
      if (phase == 'vote')
        btn(Icons.campaign, '투표 마감 & 결과 발표', ctrl.games.mafiaCloseVote),
      if (phase == 'ended')
        btn(Icons.home, '로비로', () {
          ctrl.games.endGame();
          Navigator.pop(context);
        }),
    ];
  }

  /// 명단 — 이 화면의 본문.
  ///
  /// 사회자가 내내 보는 것은 "누가 살아 있나" 다. 예전에는 이 화면에 그게
  /// 아예 없었다 — 이름→역할 사본만 좁은 곁칸에 가려 둔 채라, 정작
  /// "남은 사람은…" 을 말해야 하는 사람이 죽은 사람을 못 봤다.
  ///
  /// 역할은 여전히 가린다(꾹 눌러 확인). 생사는 안 가린다 — 그건 이미
  /// 모두가 아는 것이고, 가리면 진행이 안 된다.
  Widget _roster() {
    final members = ctrl.games.mafia!.members;
    final alive = members.where((m) => m.alive).length;

    return HudPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        // 판때기는 명단만큼만 — 다섯 명짜리 판에서 빈 상자가 화면 아래까지
        // 내려오면 뭔가 안 그려진 것처럼 보인다.
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                '명단',
                style: TextStyle(
                  color: HostHud.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 9),
              Text(
                '${members.length}명 중 $alive명 생존',
                style: const TextStyle(color: HostHud.dim, fontSize: 13),
              ),
              const Spacer(),
              if (ctrl.settings.hideSecrets)
                const Row(
                  children: [
                    Icon(Icons.lock_outline, size: 14, color: HostHud.dim),
                    SizedBox(width: 5),
                    Text(
                      '역할은 꾹 눌러 확인',
                      style: TextStyle(color: HostHud.dim, fontSize: 12.5),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          // 카드는 이름 한 줄 + 역할 한 줄이면 된다. 높이는 **고정**한다 —
          // 비율로 두면 창을 좁힐수록 칸이 낮아져서 글자가 넘친다.
          // 판때기를 늘리지 않으려고 Expanded 가 아니라 shrinkWrap 이다.
          // 인원이 많으면 남은 높이까지만 쓰고 그 안에서 굴린다 —
          // Flexible 이 없으면 20명 판에서 화면 밖으로 넘친다.
          Flexible(
            child: GridView(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisExtent: 74,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [for (final m in members) _memberCard(m)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberCard(MafiaMember m) {
    final gone = !m.alive;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: gone ? const Color(0xFF0C1024) : const Color(0xFF141C36),
        border: Border.all(
          color: gone ? const Color(0xFF1B2440) : HostHud.line,
        ),
      ),
      child: Column(
        // 가림막이 글자 폭에만 걸리면 얼룩처럼 보인다 — 칸을 가로질러야
        // "가려 둔 것" 으로 읽힌다.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  m.nickname,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: gone ? HostHud.dim : HostHud.ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    // 죽은 사람은 한눈에 갈린다 — 색만으로는 급할 때 안 보인다.
                    decoration: gone ? TextDecoration.lineThrough : null,
                    decorationColor: HostHud.red,
                    decorationThickness: 2,
                  ),
                ),
              ),
              if (gone)
                const Text(
                  '탈락',
                  style: TextStyle(
                    color: HostHud.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          SecretVeil(
            enabled: ctrl.settings.hideSecrets,
            // 안내는 판 머리에 한 번만 — 카드마다 되풀이하면 말만 는다.
            label: '',
            child: Text(
              m.role.label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: m.role.isMafiaTeam ? HostHud.red : HostHud.dim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
