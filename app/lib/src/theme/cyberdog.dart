import 'package:flutter/material.dart';

/// CyberDog design tokens used by the chat screen. One place for the colours, radii and glows so
/// the rest of the app can adopt them screen by screen.
abstract final class CyberDog {
  static const violet = Color(0xFF8A6CF5);
  static const violetDeep = Color(0xFF5E45D4);
  static const violetSoft = Color(0xFFCFC2FF);
  static const hairline = Color(0x339B7CFF);
  static const hairlineBright = Color(0x809B7CFF);
  static const panel = Color(0xCC0C1126);
  static const rankInk = Color(0xFF8E97BD);

  static const outgoing = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violet, violetDeep],
  );
  static const glow = [BoxShadow(color: Color(0x4D8A6CF5), blurRadius: 16)];
  static const glowPressed = [BoxShadow(color: Color(0x998A6CF5), blurRadius: 22)];
}

/// The CyberDog mark: an angular dog's head facing right, drawn as one vector shape so it stays
/// sharp from 16 px up and costs no image asset. The muzzle doubles as a "send" arrow.
class CyberDogMark extends StatelessWidget {
  const CyberDogMark({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _MarkPainter(color ?? Theme.of(context).colorScheme.secondary),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.color);

  final Color color;

  // Outline on a 24-unit grid, then the eye as a cut-out (even-odd fill).
  static const _head = <Offset>[
    Offset(3.5, 21.5), Offset(6.8, 12.3), Offset(5.6, 2.5), Offset(10.2, 8), Offset(12.8, 2.2),
    Offset(15.3, 9.2), Offset(21.8, 12.6), Offset(19.9, 15.3), Offset(15.2, 15.9),
    Offset(11.3, 21.5),
  ];
  static const _eye = <Offset>[Offset(13.3, 10.7), Offset(16.1, 11.6), Offset(13.6, 12.5)];

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 24;
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final shape in [_head, _eye]) {
      path.moveTo(shape.first.dx * k, shape.first.dy * k);
      for (final p in shape.skip(1)) {
        path.lineTo(p.dx * k, p.dy * k);
      }
      path.close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) => oldDelegate.color != color;
}

/// A user's rank inside CyberDog, shown as a small, deliberately quiet badge. CyberDog is the
/// app; a rank such as NightDog is a status within it. The rank arrives as an id so new ranks can
/// be added to [_labels] without touching the screens that show the badge.
class UserRankBadge extends StatelessWidget {
  const UserRankBadge({super.key, required this.rank});

  /// The rank every user has until more ranks exist.
  static const defaultRank = 'nightdog';

  static const _labels = {'nightdog': 'NIGHTDOG'};

  final String rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0x408E97BD)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CyberDogMark(size: 9, color: CyberDog.rankInk),
          const SizedBox(width: 3),
          Text(
            _labels[rank] ?? rank.toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              height: 1.2,
              letterSpacing: .8,
              fontWeight: FontWeight.w600,
              color: CyberDog.rankInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// The send button: a violet rounded square carrying the mark. On press the mark nudges right
/// and the glow tightens for a moment.
class CyberDogSendButton extends StatefulWidget {
  const CyberDogSendButton({super.key, required this.onPressed, this.semanticLabel});

  final VoidCallback onPressed;
  final String? semanticLabel;

  @override
  State<CyberDogSendButton> createState() => _CyberDogSendButtonState();
}

class _CyberDogSendButtonState extends State<CyberDogSendButton> {
  bool _down = false;

  void _set(bool down) {
    if (mounted && _down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: CyberDog.outgoing,
            borderRadius: BorderRadius.circular(14),
            boxShadow: _down ? CyberDog.glowPressed : CyberDog.glow,
          ),
          alignment: Alignment.center,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 120),
            offset: _down ? const Offset(.1, 0) : Offset.zero,
            child: const CyberDogMark(size: 26, color: Color(0xFFF5F2FF)),
          ),
        ),
      ),
    );
  }
}
