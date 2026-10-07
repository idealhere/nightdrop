import 'package:flutter/material.dart';

/// The Night Dog moon: a cream disc with a soft glow and a few craters.
class MoonMark extends StatelessWidget {
  const MoonMark({super.key, this.size = 26});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _MoonPainter()),
    );
  }
}

class _MoonPainter extends CustomPainter {
  const _MoonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      r * 1.2,
      Paint()
        ..color = const Color(0x40F0E2B6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .5),
    );
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFF0E2B6));
    final crater = Paint()..color = const Color(0xFFD9CA9B);
    canvas.drawCircle(c + Offset(-r * .32, -r * .30), r * .16, crater);
    canvas.drawCircle(c + Offset(r * .26, -r * .05), r * .21, crater);
    canvas.drawCircle(c + Offset(-r * .10, r * .40), r * .13, crater);
  }

  @override
  bool shouldRepaint(covariant _MoonPainter oldDelegate) => false;
}

/// The wordmark shown in headers: the moon followed by "Night Dog", with "Dog" in the accent.
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key, this.fontSize = 20, this.showMoon = true});

  final double fontSize;
  final bool showMoon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showMoon) ...[
          MoonMark(size: fontSize * 1.3),
          SizedBox(width: fontSize * .5),
        ],
        Text.rich(
          TextSpan(
            text: 'Night ',
            children: [
              TextSpan(text: 'Dog', style: TextStyle(color: scheme.secondary)),
            ],
          ),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}
