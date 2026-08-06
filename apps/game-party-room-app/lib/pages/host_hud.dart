import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 호스트 화면의 공용 HUD 어법.
///
/// 참가자 폰(각진 패널·상단 지휘줄·하늘색 강조)과 같은 문법을 큰 화면에도
/// 쓴다. 종목마다 제각각이면 같은 앱으로 안 보인다 — 구슬 룰렛·사다리타기가
/// 먼저 이 어법으로 만들어졌고, 여기 모아 나머지 종목이 따라온다.
///
/// 색은 [MarbleTheme] 이 아니라 여기가 정본이다(그쪽이 이걸 참조한다).
class HostHud {
  static const ground = Color(0xFF05070F);
  static const plate = Color(0xFF10182E);
  static const panel = Color(0xFF0A0F1E);
  static const line = Color(0xFF223055);
  static const sky = Color(0xFF2FB3FF);
  static const skyInk = Color(0xFF0E7FC4);
  static const ink = Color(0xFFDFE6FF);
  static const dim = Color(0xFF7C89B4);
  static const ok = Color(0xFF2ED573);
  static const red = Color(0xFFFF4757);
  static const notch = 18.0;
}

/// 오른위·왼아래를 대각선으로 자른 판.
class NotchClipper extends CustomClipper<Path> {
  const NotchClipper({this.size = HostHud.notch});

  final double size;

  @override
  Path getClip(Size s) {
    final n = size;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(s.width - n, 0)
      ..lineTo(s.width, n)
      ..lineTo(s.width, s.height)
      ..lineTo(n, s.height)
      ..lineTo(0, s.height - n)
      ..close();
  }

  @override
  bool shouldReclip(covariant NotchClipper old) => old.size != size;
}

/// 각진 패널 — 테두리색 판 위에 내용판을 2px 들여 겹친다.
class HudPanel extends StatelessWidget {
  const HudPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.notch = HostHud.notch,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double notch;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: NotchClipper(size: notch),
      child: Container(
        color: HostHud.line,
        padding: const EdgeInsets.all(1.5),
        child: ClipPath(
          clipper: NotchClipper(size: notch),
          child: Container(
            color: HostHud.panel,
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 상단 지휘줄 — 왼쪽에 종목, 오른쪽에 지금 상황.
class HudCommandBar extends StatelessWidget {
  const HudCommandBar({
    super.key,
    required this.title,
    this.subtitle,
    this.status,
    this.onEnd,
  });

  final String title;
  final String? subtitle;

  /// 오른쪽에 실시간으로 바뀌는 한 줄(라운드·진행률 등).
  final String? status;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: HostHud.plate,
      padding: const EdgeInsets.fromLTRB(18, 11, 12, 10),
      child: Row(
        children: [
          Transform.rotate(
            angle: math.pi / 4,
            child: Container(width: 9, height: 9, color: HostHud.sky),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: HostHud.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 14),
            Text(
              subtitle!,
              style: const TextStyle(color: HostHud.dim, fontSize: 13),
            ),
          ],
          const Spacer(),
          if (status != null && status!.isNotEmpty)
            Text(
              status!,
              style: const TextStyle(
                color: HostHud.sky,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (onEnd != null) ...[
            const SizedBox(width: 12),
            TextButton(
              onPressed: onEnd,
              child: const Text(
                '게임 종료',
                style: TextStyle(color: HostHud.dim, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 진행 버튼 — 오른아래를 자른 큰 실행 버튼.
class HudButton extends StatelessWidget {
  const HudButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = HudTone.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final HudTone tone;

  @override
  Widget build(BuildContext context) {
    final bg = switch (tone) {
      HudTone.primary => HostHud.sky,
      HudTone.quiet => HostHud.plate,
      HudTone.danger => HostHud.red,
    };
    // GestureDetector 를 ClipPath 바깥에 둔다 — 안쪽에 두면 잘린 모서리
    // 영역에서 탭이 새고, 플랫폼에 따라 히트테스트가 통째로 막히기도 한다.
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: ClipPath(
        clipper: const NotchClipper(size: 13),
        child: Container(
          color: onPressed == null ? const Color(0xFF1A2340) : bg,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 20,
                    color: onPressed == null ? HostHud.dim : Colors.white,
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: onPressed == null ? HostHud.dim : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum HudTone { primary, quiet, danger }

/// 지금 무슨 일이 일어나고 있는지 한 줄 — 큰 화면에서 멀리서도 읽힌다.
class HudStatusStrip extends StatelessWidget {
  const HudStatusStrip({super.key, required this.text, this.accent});

  final String text;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const NotchClipper(size: 12),
      child: Container(
        width: double.infinity,
        color: const Color(0xFF141C36),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Container(width: 4, height: 22, color: accent ?? HostHud.sky),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: HostHud.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 사회자 대사 — 있을 때만 뜨는 한 줄. 게임 정보가 아니라 분위기라서
/// 상태줄과 다른 색(보라)으로 두고, 없으면 자리도 차지하지 않는다.
class HudMcLine extends StatelessWidget {
  const HudMcLine({super.key, required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    if (line.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ClipPath(
        clipper: const NotchClipper(size: 12),
        child: Container(
          width: double.infinity,
          color: const Color(0xFF1B1733),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.record_voice_over,
                size: 18,
                color: Color(0xFFA55EEA),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  line,
                  style: const TextStyle(
                    color: Color(0xFFE8DFFF),
                    fontSize: 16,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 종목 배너 — 아래 가장자리를 자르고 하늘색 밑줄. 폰의 .banner 와 같은 어법.
class HudBanner extends StatelessWidget {
  const HudBanner({super.key, required this.asset, this.height = 128});

  final String asset;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const NotchClipper(size: 14),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: HostHud.sky, width: 3)),
        ),
        child: Image.asset(
          asset,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

/// 호스트 게임 화면의 공통 껍데기 — 지휘줄 + 어두운 바탕 + 본문.
class HudScaffold extends StatelessWidget {
  const HudScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.status,
    this.onEnd,
  });

  final String title;
  final String? subtitle;
  final String? status;
  final VoidCallback? onEnd;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HostHud.ground,
      body: SafeArea(
        child: Column(
          children: [
            HudCommandBar(
              title: title,
              subtitle: subtitle,
              status: status,
              onEnd: onEnd,
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
