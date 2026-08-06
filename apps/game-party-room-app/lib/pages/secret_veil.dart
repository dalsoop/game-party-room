import 'package:flutter/material.dart';

/// 호스트 화면의 비밀 정보를 가리는 막.
///
/// 호스트 화면은 참가자에게 노출되기 쉽다 — 라이어 게임은 상태줄에 라이어와 제시어를
/// 그대로 띄우고 "참가자에게 화면을 보여주지 마세요!" 경고문 하나로 버티고 있었다.
/// 참가자 SPA 가 쓰는 "꾹 눌러 확인" 패턴을 호스트에도 그대로 가져온다.
class SecretVeil extends StatefulWidget {
  const SecretVeil({
    super.key,
    required this.child,
    required this.enabled,
    this.label = '꾹 눌러 확인',
  });

  final Widget child;

  /// 설정에서 끄면 그냥 통과시킨다.
  final bool enabled;

  /// 막에 적을 안내. **빈 문자열이면 줄무늬만 남긴다.**
  ///
  /// 같은 안내가 이미 위에 한 번 적혀 있는데 칸마다 또 적으면 말만 늘어난다
  /// — 명단 카드처럼 여럿이 늘어서는 자리에서는 특히 그렇다. 좁다고 문구를
  /// 잘라 쓰면("꾹") 조각난 말이 되어 더 나쁘다.
  ///
  /// 화면에 글자가 없어도 스크린리더에는 늘 안내가 간다.
  final String label;

  @override
  State<SecretVeil> createState() => _SecretVeilState();
}

class _SecretVeilState extends State<SecretVeil> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: _revealed ? 0 : 1,
            duration: const Duration(milliseconds: 160),
            child: IgnorePointer(
              ignoring: _revealed,
              child: GestureDetector(
                // 누르는 동안만 공개 — 손을 떼면 즉시 다시 가려진다.
                onTapDown: (_) => setState(() => _revealed = true),
                onTapUp: (_) => setState(() => _revealed = false),
                onTapCancel: () => setState(() => _revealed = false),
                child: Semantics(
                  // 눈으로는 줄무늬만 보여도 스크린리더에는 늘 안내가 간다.
                  label: widget.label.isEmpty
                      ? '비밀 정보. 꾹 눌러 확인'
                      : '비밀 정보. ${widget.label}',
                  button: true,
                  child: CustomPaint(
                    painter: _StripePainter(),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        // 안내를 안 적기로 한 자리(명단 카드처럼 위에 이미
                        // 한 번 적혀 있는 곳)는 줄무늬만 남긴다.
                        if (widget.label.isEmpty) {
                          return const SizedBox.expand();
                        }
                        // 가리는 자리가 늘 큰 판은 아니다. 아이콘까지 넣으면
                        // 낮은 칸에서는 칸보다 커져 삐져나온다.
                        final tight = box.maxHeight < 46;
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!tight) ...[
                                const Icon(
                                  Icons.visibility_off,
                                  color: Color(0xFF9DB8FF),
                                  size: 26,
                                ),
                                const SizedBox(height: 2),
                              ],
                              Text(
                                widget.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: const Color(0xFF9DB8FF),
                                  fontWeight: FontWeight.w800,
                                  fontSize: tight ? 11.5 : 13,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 참가자 화면의 가림막과 같은 사선 줄무늬.
class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)));
    canvas.drawRect(rect, Paint()..color = const Color(0xFF1D2B50));
    final stripe = Paint()..color = const Color(0xFF26365F);
    const w = 12.0;
    for (var x = -size.height; x < size.width; x += w * 2) {
      canvas.drawPath(
        Path()
          ..moveTo(x, size.height)
          ..lineTo(x + size.height, 0)
          ..lineTo(x + size.height + w, 0)
          ..lineTo(x + w, size.height)
          ..close(),
        stripe,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
