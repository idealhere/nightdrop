import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app-wide backdrop: a night sky fading into low mountain ridges and a pine forest along the
/// bottom edge. Deliberately low-contrast and static, so text and lists stay readable on top of it
/// and it costs nothing to keep on screen.
class NightForestBackground extends StatelessWidget {
  const NightForestBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(child: CustomPaint(painter: _NightForestPainter())),
        child,
      ],
    );
  }
}

class _NightForestPainter extends CustomPainter {
  const _NightForestPainter();

  static const _sky = Color(0xFF10172B);
  static const _ground = Color(0xFF070A12);
  static const _farRidge = Color(0xFF0B1122);
  static const _nearRidge = Color(0xFF090E1B);
  static const _pines = Color(0xFF060A13);

  // Fractions of the screen (stars) and of the forest band (ridges: x across, y down the band).
  static const _stars = <Offset>[
    Offset(.12, .06), Offset(.28, .11), Offset(.47, .04), Offset(.63, .13), Offset(.81, .07),
    Offset(.92, .17), Offset(.07, .22), Offset(.36, .26), Offset(.72, .29), Offset(.55, .20),
  ];
  static const _far = <Offset>[
    Offset(0, .65), Offset(.08, .42), Offset(.16, .57), Offset(.25, .30), Offset(.34, .55),
    Offset(.44, .38), Offset(.52, .52), Offset(.61, .26), Offset(.70, .51), Offset(.79, .37),
    Offset(.89, .54), Offset(1, .34),
  ];
  static const _near = <Offset>[
    Offset(0, .83), Offset(.11, .65), Offset(.21, .77), Offset(.33, .60), Offset(.45, .78),
    Offset(.56, .65), Offset(.68, .79), Offset(.81, .63), Offset(.91, .76), Offset(1, .65),
  ];
  // Pines as (centre x, height, width) on a 200-unit-tall band, measured from the screen edge.
  static const _trees = <List<double>>[
    [22, 150, 52], [60, 115, 44], [98, 165, 58], [140, 105, 42], [176, 130, 48], [238, 72, 34],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_sky, _ground],
          stops: [0, .6],
        ).createShader(rect),
    );

    final star = Paint()..color = const Color(0x55FFFFFF);
    for (final s in _stars) {
      canvas.drawCircle(Offset(s.dx * size.width, s.dy * size.height), .8, star);
    }

    final band = math.min(size.height * .24, 200.0);
    final top = size.height - band;
    _ridge(canvas, size, top, band, _far, _farRidge);
    _ridge(canvas, size, top, band, _near, _nearRidge);

    final scale = band / 200;
    final pine = Paint()..color = _pines;
    for (final t in _trees) {
      final x = t[0] * scale;
      _pine(canvas, x, size.height, t[1] * scale, t[2] * scale, pine);
      _pine(canvas, size.width - x, size.height, t[1] * scale, t[2] * scale, pine);
    }
  }

  void _ridge(
      Canvas canvas, Size size, double top, double band, List<Offset> points, Color color) {
    final path = Path()..moveTo(0, size.height);
    for (final p in points) {
      path.lineTo(p.dx * size.width, top + p.dy * band);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _pine(Canvas canvas, double cx, double base, double h, double w, Paint paint) {
    void tier(double apex, double foot, double half) {
      canvas.drawPath(
        Path()
          ..moveTo(cx, base - apex)
          ..lineTo(cx + half, base - foot)
          ..lineTo(cx - half, base - foot)
          ..close(),
        paint,
      );
    }

    tier(h, h * .38, w * .28);
    tier(h * .78, h * .30, w * .40);
    tier(h * .52, 0, w * .5);
  }

  @override
  bool shouldRepaint(covariant _NightForestPainter oldDelegate) => false;
}
