import 'package:flutter/material.dart';

/// 처음 쓰는 호스트를 위한 한 페이지.
///
/// 기능 설명서가 아니라 **막히는 지점만** 모았다 — 사용성 테스트에서
/// 실제로 걸린 것들(참가자가 못 붙음, 게임 중 늦게 온 사람, 유령 참가자)과
/// 파티 진행 요령. 읽지 않아도 게임은 되게 만들었으니, 여기 오는 사람은
/// 이미 뭔가 안 되는 중이다. 답부터 준다.
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  static void open(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const HelpPage()),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('도움말')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: const [
              _Section(
                title: '시작하기',
                items: [
                  _Item(
                    '참가자는 앱을 깔지 않습니다',
                    '화면의 QR 을 폰 카메라로 찍으면 브라우저가 열립니다. '
                        '닉네임을 넣고 [입장하기] 를 누르면 끝입니다.',
                  ),
                  _Item(
                    '이 맥이 곧 서버입니다',
                    '별도 서버나 로그인이 없습니다. 앱을 닫으면 방도 닫힙니다. '
                        '(다시 켜면 직전 방과 참가자가 복구됩니다.)',
                  ),
                ],
              ),
              _Section(
                title: '참가자가 접속을 못 할 때',
                items: [
                  _Item(
                    '먼저: 같은 Wi-Fi 인지',
                    '기본 주소는 같은 네트워크 안에서만 닿습니다. '
                        '폰이 LTE 를 쓰고 있으면 안 됩니다.',
                  ),
                  _Item(
                    '카페·회사 Wi-Fi 라면',
                    '기기끼리 통신을 막아 둔 곳이 많습니다(AP 격리). '
                        'QR 아래 [안 붙어요 · 전용 Wi-Fi] 를 보세요.',
                  ),
                  _Item(
                    '어디서든 되게 하려면',
                    'QR 아래 [인터넷으로 열기] 를 누르면 인터넷 주소로 바뀝니다. '
                        '처음 한 번은 무료 도구 설치 안내가 뜹니다.',
                  ),
                  _Item(
                    '주소가 여러 개로 잡힐 때',
                    'VPN 을 켜 두면 엉뚱한 주소가 잡힐 수 있습니다. '
                        '[주소 바꾸기] 로 Wi-Fi 주소를 고르세요.',
                  ),
                ],
              ),
              _Section(
                title: '진행 중에',
                items: [
                  _Item(
                    '게임 도중 온 사람',
                    '입장은 됩니다. 이번 판은 못 끼고, 끝나면 자동으로 다음 판에 '
                        '참여됩니다. 그 사람 폰에도 그렇게 안내됩니다.',
                  ),
                  _Item(
                    '중간에 나간 사람',
                    '폰을 껐거나 브라우저를 닫으면 "끊김" 으로 표시됩니다. '
                        '다시 QR 을 찍으면 같은 자리로 돌아옵니다.',
                  ),
                  _Item(
                    '끊긴 사람이 쌓이면',
                    '참가자 목록 아래 [끊긴 참가자 정리] 로 한 번에 치웁니다. '
                        '방 정원은 20명입니다.',
                  ),
                  _Item(
                    '같은 Wi-Fi 안에서는 암호화되지 않습니다',
                    '기본 접속은 평문 HTTP 입니다 — 같은 네트워크에 있는 사람이 '
                        '작정하면 채팅·자료를 들여다볼 수 있습니다. 민감한 자료를 '
                        '나눌 자리라면 [인터넷으로 열기](HTTPS)를 쓰세요.',
                  ),
                  _Item(
                    '방은 지울 때까지 남습니다',
                    '앱이 꺼졌다 켜져도 참가자와 진행 상황이 돌아옵니다. '
                        '친구 그룹마다 방을 하나씩 두고 계속 쓰세요 — '
                        '같은 QR 이 다음 모임에도 통합니다.',
                  ),
                  _Item(
                    '안 쓸 때는 방을 닫아 두세요',
                    '방 목록에서 [닫기] 를 누르면 그 링크로는 못 들어옵니다. '
                        '방은 오래 남으니, 지난 모임 링크가 계속 살아 있는 게 '
                        '걸리면 이걸로 잠급니다.',
                  ),
                  _Item(
                    '호스트 화면을 보여주면 안 됩니다',
                    '마피아 역할표와 라이어 제시어가 있습니다. 기본으로 가려져 '
                        '있고, 꾹 누르는 동안만 보입니다.',
                  ),
                ],
              ),
              _Section(
                title: '방을 여러 개 쓰기',
                items: [
                  _Item(
                    '친구 그룹마다 방을 따로',
                    '앱을 켜면 방 목록이 나옵니다. [새 방] 으로 만들고 이름을 '
                        '붙이면(금요 모임, 회사 워크숍…) 각자 QR 과 단톡을 '
                        '갖습니다. 대화도 자료도 섞이지 않습니다.',
                  ),
                  _Item(
                    '방마다 따로 돌아갑니다',
                    '한 방에서 마피아가 도는 동안 다른 방은 그대로 대기합니다. '
                        '방 목록에 어느 방이 무엇을 하는 중인지 보입니다.',
                  ),
                  _Item(
                    '다시 쓰려면 [비우기]',
                    '참가자·대화·자료만 지우고 방은 남깁니다. 나눠준 QR 이 '
                        '그대로라 링크를 다시 뿌리지 않아도 됩니다. '
                        '아예 없앨 때만 [지우기] 를 쓰세요.',
                  ),
                ],
              ),
              _Section(
                title: '더 재미있게',
                items: [
                  _Item(
                    'TV·프로젝터에 띄우기',
                    '창을 키우면 QR 과 게임 화면이 함께 커집니다. '
                        '구슬 룰렛·사다리타기는 큰 화면일수록 좋습니다.',
                  ),
                  _Item(
                    'LLM 사회자',
                    '설정에서 켜면 결정적인 순간마다 사회자가 한마디 합니다. '
                        '터미널에 claude·codex 가 로그인돼 있으면 바로 됩니다.',
                  ),
                  _Item(
                    '단톡과 자료함',
                    '폰 왼쪽 아래 말풍선으로 방 전체 채팅과 사진·파일 공유가 '
                        '됩니다. 판이 시작되면 그 판의 칸이 따로 열려서, '
                        '나중에 "그때 그 판" 만 펼쳐 볼 수 있습니다. '
                        '아무도 말하지 않은 판의 칸은 남지 않습니다.',
                  ),
                  _Item(
                    '뽑기는 다시 돌릴 수 있습니다',
                    '구슬 룰렛·사다리타기 결과 화면의 [한 판 더] 로 같은 설정 '
                        '그대로 다시 돌립니다.',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.items});

  final String title;
  final List<_Item> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0E7FC4),
            ),
          ),
        ),
        ...items,
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item(this.title, this.body);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDBE4F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.55,
              color: Color(0xFF5F6C82),
            ),
          ),
        ],
      ),
    );
  }
}
