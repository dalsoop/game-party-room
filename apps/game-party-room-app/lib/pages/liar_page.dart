import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:party_room_server/party_room_server.dart';
import 'package:image_picker/image_picker.dart';

import '../host_controller.dart';
import 'host_hud.dart';
import 'secret_veil.dart';

/// 라이어 게임 진행 전용 페이지.
class LiarPage extends StatelessWidget {
  const LiarPage({super.key, required this.ctrl});

  final HostController ctrl;

  /// 로비에서 호출: 랜덤/커스텀 선택 다이얼로그 → 게임 시작 → 페이지 진입.
  static Future<void> startFlow(
    BuildContext context,
    HostController ctrl,
  ) async {
    final setup = await showDialog<_LiarSetup>(
      context: context,
      builder: (_) => const _LiarSetupDialog(),
    );
    if (setup == null) return;
    bool ok;
    if (setup.custom) {
      ok = ctrl.games.startLiarCustom(
        setup.category,
        setup.word,
        setup.imageBytes,
      );
    } else {
      ok = ctrl.games.startLiar();
    }
    if (!ok) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('라이어 게임은 3명 이상 필요합니다')));
      }
      return;
    }
    if (context.mounted) {
      // 이 Future 는 밀어 넣은 화면이 닫힐 때 끝난다 — 여기서 기다릴 것이
      // 아니다. 빠뜨린 게 아니라는 걸 unawaited 로 밝힌다.
      unawaited(
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => LiarPage(ctrl: ctrl)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        if (ctrl.games.liar == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          });
          return const SizedBox.shrink();
        }
        final game = ctrl.games.liar!;
        return HudScaffold(
          title: '라이어 게임',
          onEnd: () {
            ctrl.games.endGame();
            Navigator.pop(context);
          },
          // 마피아와 같은 조종석 배치다: 위에 지금 상황, 가운데 명단,
          // 아래 조작. 예전에는 맨 위가 장식 사진이었고 "누가 아직 안
          // 골랐나" 는 화면 어디에도 없어서, 사회자가 언제 마감할지를
          // 감으로 정해야 했다.
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 상태줄에 라이어와 제시어가 그대로 나온다 — 어깨너머로 새면
                // 게임이 끝난다. 경고문 대신 기본으로 가리고, 볼 때만 꾹 누른다.
                SecretVeil(
                  enabled: ctrl.settings.hideSecrets,
                  label: '라이어·제시어 — 꾹 눌러 확인',
                  child: HudStatusStrip(
                    text: ctrl.games.gameStatus.isEmpty
                        ? '진행 중'
                        : ctrl.games.gameStatus,
                    accent: const Color(0xFFA55EEA),
                  ),
                ),
                HudMcLine(line: ctrl.mcLine),
                const SizedBox(height: 14),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _roster(game),
                  ),
                ),
                const SizedBox(height: 14),
                HudButton(
                  icon: Icons.how_to_vote,
                  label: '토론 끝 — 지목 투표 시작',
                  onPressed: ctrl.games.liarVote,
                ),
                const SizedBox(height: 10),
                HudButton(
                  icon: Icons.campaign,
                  label: '투표 마감 & 결과 발표',
                  tone: HudTone.quiet,
                  onPressed: ctrl.games.liarCloseVote,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 명단 — 누가 들어와 있고 누가 골랐나.
  ///
  /// 이 판에서 사회자가 판단할 것은 하나다: **언제 마감하나.** 그런데
  /// 그 판단에 필요한 "아직 안 고른 사람" 이 화면에 없어서 감으로 정해야
  /// 했다. 제시어는 여전히 가리지만(위 상태줄), 누가 골랐는지는 안 가린다 —
  /// 그건 비밀이 아니라 진행 정보다.
  Widget _roster(LiarGame game) {
    final seats = game.seats;
    final voted = game.votedBy;

    return HudPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                game.voteOpen
                    ? '${seats.length}명 중 ${voted.length}명 지목 완료'
                    : '${seats.length}명 참여 중',
                style: const TextStyle(color: HostHud.dim, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: GridView(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisExtent: 52,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final s in seats)
                  _SeatCard(
                    nickname: s.nickname,
                    done: game.voteOpen && voted.contains(s.session),
                    waiting: game.voteOpen && !voted.contains(s.session),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 명단 한 칸 — 투표 중에는 골랐는지가 한눈에 보여야 한다.
class _SeatCard extends StatelessWidget {
  const _SeatCard({
    required this.nickname,
    required this.done,
    required this.waiting,
  });

  final String nickname;
  final bool done;
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF141C36),
        border: Border.all(color: done ? HostHud.ok : HostHud.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              nickname,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: HostHud.ink,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (done)
            const Icon(Icons.check_circle, size: 17, color: HostHud.ok)
          else if (waiting)
            const Text(
              '대기',
              style: TextStyle(color: HostHud.dim, fontSize: 12.5),
            ),
        ],
      ),
    );
  }
}

class _LiarSetup {
  _LiarSetup({
    required this.custom,
    this.category = '',
    this.word = '',
    this.imageBytes,
  });
  final bool custom;
  final String category;
  final String word;
  final List<int>? imageBytes;
}

/// 라이어 설정: 랜덤 제시어 또는 사회자 커스텀(글자+이미지).
class _LiarSetupDialog extends StatefulWidget {
  const _LiarSetupDialog();

  @override
  State<_LiarSetupDialog> createState() => _LiarSetupDialogState();
}

class _LiarSetupDialogState extends State<_LiarSetupDialog> {
  bool _custom = false;
  final _category = TextEditingController(text: '음식');
  final _word = TextEditingController();
  Uint8List? _image;

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _image = bytes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('라이어 게임 설정'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('랜덤 제시어')),
                ButtonSegment(value: true, label: Text('직접 만들기')),
              ],
              selected: {_custom},
              onSelectionChanged: (s) => setState(() => _custom = s.first),
            ),
            if (_custom) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _category,
                decoration: const InputDecoration(
                  labelText: '카테고리 (라이어에게도 보임)',
                ),
              ),
              TextField(
                controller: _word,
                decoration: const InputDecoration(labelText: '제시어 (라이어만 모름)'),
              ),
              const SizedBox(height: 12),
              if (_image != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(_image!, height: 120, fit: BoxFit.cover),
                ),
              TextButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.photo_library),
                label: Text(_image == null ? '이미지 추가 (선택)' : '이미지 변경'),
              ),
              if (_image != null)
                TextButton(
                  onPressed: () => setState(() => _image = null),
                  child: const Text('이미지 제거'),
                ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  '음식·장소·직업·동물·물건 중 무작위로 출제됩니다.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            if (_custom) {
              final w = _word.text.trim();
              if (w.isEmpty) return;
              Navigator.pop(
                context,
                _LiarSetup(
                  custom: true,
                  category: _category.text.trim().isEmpty
                      ? '자유'
                      : _category.text.trim(),
                  word: w,
                  imageBytes: _image,
                ),
              );
            } else {
              Navigator.pop(context, _LiarSetup(custom: false));
            }
          },
          child: const Text('시작'),
        ),
      ],
    );
  }
}
