import 'package:flutter/material.dart';

/// CyberDog design tokens used by the chat screen. One place for the colours, radii and glows so
/// the rest of the app can adopt them screen by screen.
abstract final class CyberDog {
  static const accent = Color(0xFF7657FF);
  static const accentLight = Color(0xFF9B7BFF);
  static const accentDark = Color(0xFF5638D7);
  static const violetSoft = Color(0xFFCFC2FF);
  static const hairline = Color(0x2E8278FF);
  static const hairlineBright = Color(0x80825AFF);
  static const panel = Color(0xFF0D1225);
  static const rankInk = Color(0xFF7F86A6);

  static const outgoing = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7556FF), Color(0xFF5D37EE)],
  );

  /// The only glow in the chat: a faint one under the send button, slightly stronger on press.
  static const glow = [BoxShadow(color: Color(0x337657FF), blurRadius: 12)];
  static const glowPressed = [BoxShadow(color: Color(0x667657FF), blurRadius: 16)];
}

/// The CyberDog mark: an angular dog's head facing right, drawn as a few vector strokes so it stays
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

  // The same shapes as logo-mark.svg, on a 24-unit grid: the profile, the front ear, the nose,
  // the throat and the eye. Traced from the brand artwork.
  static const _strokes = <List<Offset>>[
    [
      Offset(1.96, 18.25), Offset(2.32, 16.09), Offset(6.65, 8.53), Offset(7.19, 9.16), Offset(7.55, 6.73), Offset(10.43, 2.23), Offset(10.79, 7.36), Offset(13.04, 7.54), Offset(14.66, 8.08), Offset(15.56, 8.71), Offset(16.01, 10.15), Offset(19.7, 11.68), Offset(22.04, 12.22), Offset(20.69, 13.39), Offset(18.89, 15.38), Offset(12.77, 16.63), Offset(12.5, 17.0),
    ],
    [
      Offset(11.69, 7.27), Offset(13.85, 2.95), Offset(14.66, 8.08),
    ],
    [
      Offset(19.7, 11.68), Offset(19.79, 12.49), Offset(20.69, 13.39),
    ],
    [
      Offset(12.13, 17.54), Offset(11.23, 20.86), Offset(11.69, 21.77),
    ],
  ];
  static const _eye = <Offset>[Offset(12.22, 10.33), Offset(13.31, 10.02), Offset(14.38, 10.43), Offset(13.31, 10.83)];

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 24;
    final lines = Path();
    for (final stroke in _strokes) {
      lines.moveTo(stroke.first.dx * k, stroke.first.dy * k);
      for (final p in stroke.skip(1)) {
        lines.lineTo(p.dx * k, p.dy * k);
      }
    }
    canvas.drawPath(
      lines,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        // A little heavier at small sizes, so the mark still reads at 16-24 px.
        ..strokeWidth = (size.shortestSide < 20 ? 1.6 : 1.1) * k
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final eye = Path()..moveTo(_eye.first.dx * k, _eye.first.dy * k);
    for (final p in _eye.skip(1)) {
      eye.lineTo(p.dx * k, p.dy * k);
    }
    canvas.drawPath(eye..close(), Paint()..color = color);
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

  static const _labels = {'nightdog': 'NIGHTDOG', 'cyberdog': 'CYBERDOG'};

  /// Ranks that have been earned are drawn in the brand violet; the starting rank stays muted.
  static const _earned = {'cyberdog'};

  final String rank;

  @override
  Widget build(BuildContext context) {
    final ink = _earned.contains(rank) ? CyberDog.violetSoft : CyberDog.rankInk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: ink.withValues(alpha: .3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CyberDogMark(size: 9, color: ink),
          const SizedBox(width: 3),
          Text(
            _labels[rank] ?? rank.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              height: 1.2,
              letterSpacing: .8,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// The send button: a violet rounded square carrying the mark. On press the mark nudges right
/// and the glow strengthens slightly.
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
          width: 46,
          height: 42,
          decoration: BoxDecoration(
            gradient: CyberDog.outgoing,
            borderRadius: BorderRadius.circular(12),
            boxShadow: _down ? CyberDog.glowPressed : CyberDog.glow,
          ),
          alignment: Alignment.center,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 120),
            offset: _down ? const Offset(.1, 0) : Offset.zero,
            child: const CyberDogMark(size: 28, color: Color(0xFFF5F2FF)),
          ),
        ),
      ),
    );
  }
}
