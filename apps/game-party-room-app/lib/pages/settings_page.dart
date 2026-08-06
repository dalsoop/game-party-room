import 'package:flutter/material.dart';

import '../games/game_catalog.dart';
import '../host_controller.dart';
import '../server/mc_service.dart';
import 'cli_page.dart';
import 'diagnostics_page.dart';
import 'help_page.dart';
import 'mc_cli_choices.dart';
import '../settings/game_rule_spec.dart';

/// 호스트 설정 — 접속·방·게임 규칙·화면을 한 곳에서.
///
/// 예전에는 방 초기화(앱바 아이콘)·주소 변경(QR 아래 링크)·전용 Wi-Fi(그 옆 링크)·
/// 터널 주소(시트 안쪽)가 흩어져 있어, 문제가 나면 어디를 눌러야 할지 매번 찾아야 했다.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.ctrl,
    required this.onOpenAddress,
    required this.onOpenExternal,
    required this.onOpenHotspot,
  });

  final HostController ctrl;
  final VoidCallback onOpenAddress;
  final VoidCallback onOpenExternal;
  final VoidCallback onOpenHotspot;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final s = ctrl.settings;
        return Scaffold(
          appBar: AppBar(title: const Text('설정')),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _group('접속'),
              ListTile(
                leading: const Icon(Icons.lan_outlined),
                title: const Text('현재 주소'),
                subtitle: Text(
                  ctrl.usingExternal
                      ? '인터넷 주소 · 어디서든 접속 가능'
                      : (ctrl.address == null
                            ? '주소 없음'
                            : '${ctrl.address!.label} · ${ctrl.address!.interfaceName}'),
                ),
              ),
              if (!ctrl.usingExternal && ctrl.addresses.length > 1)
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: const Text('주소 바꾸기'),
                  subtitle: Text('후보 ${ctrl.addresses.length}개'),
                  onTap: onOpenAddress,
                ),
              ListTile(
                leading: const Icon(Icons.public),
                title: const Text('인터넷 주소로 열기'),
                subtitle: const Text('터널 주소를 넣으면 어느 망에서든 접속됩니다'),
                onTap: onOpenExternal,
              ),
              ListTile(
                leading: const Icon(Icons.wifi_tethering),
                title: const Text('전용 Wi-Fi 안내'),
                subtitle: const Text('핫스팟을 켜면 대역·VPN 문제가 사라집니다'),
                onTap: onOpenHotspot,
              ),

              _group('화면·소리'),
              SwitchListTile(
                secondary: const Icon(Icons.visibility_off_outlined),
                title: const Text('비밀 가리기'),
                subtitle: const Text('역할표·라이어 제시어를 가림막 뒤에 둡니다'),
                value: s.hideSecrets,
                onChanged: s.setHideSecrets,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.qr_code_2),
                title: const Text('QR 크게'),
                subtitle: const Text('TV·프로젝터로 띄울 때'),
                value: s.bigQr ?? MediaQuery.of(context).size.width > 700,
                onChanged: s.setBigQr,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.volume_up_outlined),
                title: const Text('진행 효과음'),
                subtitle: const Text('출발·골인·당첨·낮밤 전환에만 소리가 납니다'),
                value: ctrl.settings.soundEnabled,
                onChanged: ctrl.settings.setSoundEnabled,
              ),

              // 종목이 선언한 규칙만 그린다 — 이 화면은 게임을 모른다.
              for (final game in GameCatalog.all)
                if (game.rules.isNotEmpty) ...[
                  _group('${game.title} 규칙'),
                  for (final spec in game.rules)
                    _ruleTile(context, ctrl, game.id, spec),
                ],

              _group('LLM 사회자'),
              SwitchListTile(
                secondary: const Icon(Icons.record_voice_over_outlined),
                title: const Text('사회자 켜기'),
                subtitle: const Text(
                  '게임의 결정적 순간마다 한 문장이 단톡에 뜹니다.\n'
                  '게임 규칙에는 관여하지 않아 꺼져 있어도 모두 정상 진행됩니다.',
                ),
                value: ctrl.settings.mcEnabled,
                onChanged: (v) => ctrl.settings.setMc(enabled: v),
              ),
              if (ctrl.settings.mcEnabled) ...[
                // 터미널 구독을 1순위로 — 이미 로그인돼 있으면 키가 필요 없다.
                ...McCliChoices.tiles(context, ctrl),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('직접 서버 주소 쓰기'),
                  subtitle: Text(
                    ctrl.settings.mcProvider == 'http'
                        ? '사용 중 · ${ctrl.settings.mcModel} · ${ctrl.settings.mcBaseUrl}'
                        : 'OpenAI 호환 주소(Ollama·LM Studio·사내 게이트웨이)',
                  ),
                  trailing: Icon(
                    ctrl.settings.mcProvider == 'http'
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: ctrl.settings.mcProvider == 'http'
                        ? const Color(0xFF2FB3FF)
                        : Colors.grey,
                  ),
                  onTap: () => _showMcDialog(context, ctrl),
                ),
                ListTile(
                  leading: const Icon(Icons.theater_comedy_outlined),
                  title: const Text('사회자 성격'),
                  trailing: DropdownButton<String>(
                    value: ctrl.settings.mcPersona,
                    onChanged: (v) => ctrl.settings.setMc(persona: v),
                    items: [
                      for (final p in McPersona.values)
                        DropdownMenuItem(value: p.name, child: Text(p.label)),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: const Text('사회자 시험 삼아 시켜보기'),
                  subtitle: const Text('지금 고른 통로로 실제 한 문장을 받아봅니다'),
                  onTap: () => _probeMc(context, ctrl),
                ),
              ],

              _group('정보'),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('도움말'),
                subtitle: const Text('접속이 안 될 때·진행 요령'),
                onTap: () => HelpPage.open(context),
              ),
              ListTile(
                leading: Icon(
                  Icons.terminal,
                  color: CliPage.resolve() == null ? Colors.grey : null,
                ),
                title: const Text('명령줄에서 조종하기'),
                subtitle: Text(
                  CliPage.resolve() == null
                      ? 'CLI 가 PATH 에 없습니다 — 설치 한 줄을 보여줍니다'
                      : '화면 없이 상태 확인·판 진행 (partyroom)',
                  style: TextStyle(
                    fontSize: 12,
                    color: CliPage.resolve() == null ? Colors.orange : null,
                  ),
                ),
                onTap: () => CliPage.open(context, ctrl),
              ),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('오류 기록'),
                subtitle: const Text('이 맥에만 남습니다 · 전송되지 않습니다'),
                onTap: () => DiagnosticsPage.open(context),
              ),
              ListTile(
                leading: const Icon(Icons.text_fields_outlined),
                title: const Text('서체·라이선스'),
                subtitle: const Text('넥슨 Lv2 고딕 사용 고지'),
                onTap: () => _showLicenses(context),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  /// 지금 고른 통로로 실제 한 문장을 받아 본다 — 설정이 맞는지 확인하는
  /// 가장 정직한 방법은 진짜로 시켜 보는 것이다.
  static Future<void> _probeMc(
    BuildContext context,
    HostController ctrl,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('사회자에게 물어보는 중…')));
    final r = await ctrl.probeMc();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(r.ok ? '사회자: ${r.sample}' : '실패: ${r.error}'),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  /// LLM 연결 설정 — OpenAI 호환 엔드포인트 하나로 통일했으므로
  /// 주소·모델·키 세 칸이면 어떤 제공자든 붙는다.
  static void _showMcDialog(BuildContext context, HostController ctrl) {
    final base = TextEditingController(text: ctrl.settings.mcBaseUrl);
    final model = TextEditingController(text: ctrl.settings.mcModel);
    final key = TextEditingController(text: ctrl.settings.mcApiKey);
    String? result;
    bool testing = false;

    showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setLocal) => AlertDialog(
          title: const Text('사회자 연결'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'OpenAI 호환 주소면 무엇이든 됩니다 — '
                    'Ollama(로컬), LM Studio, OpenAI, 사내 게이트웨이.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: base,
                    decoration: const InputDecoration(
                      labelText: '서버 주소',
                      hintText: 'http://localhost:11434/v1',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: model,
                    decoration: const InputDecoration(
                      labelText: '모델',
                      hintText: 'llama3.2 · gpt-4o-mini …',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: key,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'API 키 (로컬 모델이면 비워 둠)',
                      isDense: true,
                    ),
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      result!,
                      style: TextStyle(
                        fontSize: 12,
                        color: result!.startsWith('연결됨')
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: testing
                  ? null
                  : () async {
                      ctrl.settings.setMc(
                        baseUrl: base.text,
                        model: model.text,
                        apiKey: key.text,
                      );
                      setLocal(() {
                        testing = true;
                        result = '확인 중…';
                      });
                      final r = await ctrl.probeMc();
                      setLocal(() {
                        testing = false;
                        result = r.ok
                            ? '연결됨 — "${r.sample}"'
                            : '실패: ${r.error}';
                      });
                    },
              child: const Text('연결 테스트'),
            ),
            FilledButton(
              onPressed: () {
                ctrl.settings.setMc(
                  baseUrl: base.text,
                  model: model.text,
                  apiKey: key.text,
                );
                Navigator.pop(dialog);
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    ).then((_) {
      base.dispose();
      model.dispose();
      key.dispose();
    });
  }

  /// 배포 조건인 고지들 — 넥슨 서체는 무료·상업 사용이 허용되지만
  /// **사용 사실 고지가 라이선스 조건**이다. 눈에 띄는 곳에 둔다.
  static void _showLicenses(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('서체·라이선스'),
        content: const SingleChildScrollView(
          child: Text(
            '서체\n'
            '이 앱에는 넥슨에서 제공한 넥슨 Lv2 고딕 서체가 적용되어 있습니다.\n'
            '넥슨 Lv2 고딕의 지식재산권은 (주)넥슨코리아에 있으며, 서체는 넥슨의 '
            '폰트 라이선스 조건에 따라 무료로 사용되었습니다.\n\n'
            '구슬 룰렛\n'
            '구슬 룰렛 종목은 lazygyu 의 Marble Roulette(MIT License)의 진행 '
            '방식을 참고해 독자적으로 구현했습니다. 원 프로젝트의 코드는 '
            '포함되어 있지 않습니다.\n\n'
            '오픈소스\n'
            'Flutter · shelf · web_socket_channel 등 오픈소스 소프트웨어를 '
            '사용합니다.',
            style: TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  static Widget _group(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        color: Colors.grey,
      ),
    ),
  );

  /// 선언된 규칙 하나를 위젯으로. 새 규칙 종류가 생기면 여기만 는다.
  static Widget _ruleTile(
    BuildContext context,
    HostController ctrl,
    String gameId,
    GameRuleSpec spec,
  ) {
    final s = ctrl.settings;
    switch (spec) {
      case ToggleRule():
        return SwitchListTile(
          title: Text(spec.label),
          subtitle: spec.help == null ? null : Text(spec.help!),
          value: s.rule<bool>(gameId, spec.key, spec.initial),
          onChanged: (v) => s.setRule(gameId, spec.key, v),
        );

      case ChoiceRule():
        final cur = s.rule<String>(gameId, spec.key, spec.initial);
        return ListTile(
          title: Text(spec.label),
          subtitle: spec.help == null ? null : Text(spec.help!),
          trailing: Text(spec.options[cur] ?? cur),
          onTap: () async {
            final picked = await showModalBottomSheet<String>(
              context: context,
              builder: (sheet) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in spec.options.entries)
                      ListTile(
                        title: Text(e.value),
                        leading: Icon(
                          e.key == cur
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 20,
                        ),
                        onTap: () => Navigator.pop(sheet, e.key),
                      ),
                  ],
                ),
              ),
            );
            if (picked != null) s.setRule(gameId, spec.key, picked);
          },
        );

      case MultiChoiceRule():
        final cur = List<String>.from(
          s.rule<List<dynamic>>(gameId, spec.key, spec.initial).cast<String>(),
        );
        return ExpansionTile(
          title: Text(spec.label),
          subtitle: Text('${cur.length}개 선택됨'),
          children: [
            for (final e in spec.options.entries)
              CheckboxListTile(
                dense: true,
                title: Text(e.value),
                value: cur.contains(e.key),
                onChanged: (on) {
                  final next = List<String>.from(cur);
                  if (on == true) {
                    next.add(e.key);
                  } else {
                    next.remove(e.key);
                  }
                  // 전부 끄면 제시어를 못 뽑는다 — 최소 개수를 지킨다.
                  if (next.length < spec.minSelected) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('최소 ${spec.minSelected}개는 남겨야 합니다'),
                      ),
                    );
                    return;
                  }
                  s.setRule(gameId, spec.key, next);
                },
              ),
          ],
        );
    }
  }
}
