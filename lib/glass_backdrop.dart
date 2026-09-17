import 'dart:ui';

import 'package:flutter/widgets.dart';

/// 纯代码绘制的彩色光斑壁纸。
///
/// 液态玻璃需要“有内容的背景”才能看出折射与模糊效果，
/// 这里用几团被高斯模糊过的径向渐变代替图片资源，避免额外引入 assets。
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF04070F),
                Color(0xFF0C1533),
                Color(0xFF1A0E2E),
              ],
            ),
          ),
        ),
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: const Stack(
            fit: StackFit.expand,
            children: [
              _Blob(
                alignment: Alignment(-0.75, -0.75),
                size: 340,
                color: Color(0xFF2E6BFF),
              ),
              _Blob(
                alignment: Alignment(0.85, -0.35),
                size: 300,
                color: Color(0xFF9B3BFF),
              ),
              _Blob(
                alignment: Alignment(-0.5, 0.6),
                size: 360,
                color: Color(0xFF00C2A8),
              ),
              _Blob(
                alignment: Alignment(0.7, 0.75),
                size: 320,
                color: Color(0xFFFF4D8D),
              ),
              _Blob(
                alignment: Alignment(0.0, 0.05),
                size: 260,
                color: Color(0xFFFFB020),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required this.alignment,
    required this.size,
    required this.color,
  });

  final Alignment alignment;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.85),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}
