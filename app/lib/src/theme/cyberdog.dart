import 'package:flutter/material.dart';

/// CyberDog design tokens used by the chat screen. One place for the colours, radii and glows so
/// the rest of the app can adopt them screen by screen.
abstract final class CyberDog {
  static const accent = Color(0xFF1F6FFF);
  static const accentLight = Color(0xFF2A7BFF);
  static const accentDark = Color(0xFF1557D8);

  /// The ink of an earned rank. (The name dates from the violet palette.)
  static const violetSoft = Color(0xFF1557D8);
  static const hairline = Color(0x3D7A9BD6);
  static const hairlineBright = Color(0x991F6FFF);
  static const panel = Color(0xFFFFFFFF);
  static const rankInk = Color(0xFF8E99AA);

  static const outgoing = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    // Deep enough at both ends for the white text of an outgoing message.
    colors: [Color(0xFF1F7BFF), Color(0xFF1A5AE8)],
  );

  /// The only glow in the chat: a faint one under the send button, slightly stronger on press.
  static const glow = [BoxShadow(color: Color(0x4D1F6FFF), blurRadius: 12)];
  static const glowPressed = [BoxShadow(color: Color(0x801F6FFF), blurRadius: 16)];
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

/// The CyberDog logo: the brand's dog head, as a picture. Falls back to the drawn mark if the
/// image cannot be loaded.
class CyberDogLogo extends StatelessWidget {
  const CyberDogLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/logo-icon.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => CyberDogMark(size: size),
    );
  }
}

/// A round avatar for a person or a group: a soft gradient picked from the name or id, so each
/// chat keeps its own colour, with the first letter of the name — or the group sign — in white.
class CyberDogAvatar extends StatelessWidget {
  const CyberDogAvatar({
    super.key,
    required this.seed,
    required this.label,
    this.group = false,
    this.radius = 26,
  });

  /// What the colour is picked from: stays the same for the same chat.
  final String seed;

  /// The name; its first letter is shown.
  final String label;
  final bool group;
  final double radius;

  static const _palettes = <List<Color>>[
    [Color(0xFF7A5CFF), Color(0xFF2B2A6B)],
    [Color(0xFF6FB6FF), Color(0xFF1F6FFF)],
    [Color(0xFFFF8FB8), Color(0xFF8A6BD1)],
    [Color(0xFF3F7BD6), Color(0xFF0B1630)],
    [Color(0xFF5AD1C0), Color(0xFF2C8E86)],
    [Color(0xFF8FA3BF), Color(0xFF51627A)],
    [Color(0xFF6BC48A), Color(0xFF1D5A3A)],
    [Color(0xFF2AA8FF), Color(0xFF5A5CFF)],
  ];

  /// The gradient for [seed]: a plain sum of its characters, so it does not change between runs.
  static List<Color> paletteFor(String seed) {
    var sum = 0;
    for (final unit in seed.codeUnits) {
      sum = (sum + unit) & 0x7fffffff;
    }
    return _palettes[sum % _palettes.length];
  }

  @override
  Widget build(BuildContext context) {
    final letter = label.trim().isEmpty ? '' : String.fromCharCode(label.trim().runes.first).toUpperCase();
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: paletteFor(seed),
        ),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x2E1C3E78), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: group || letter.isEmpty
          ? Icon(group ? Icons.groups_rounded : Icons.person_rounded, color: Colors.white, size: radius)
          : Text(
              letter,
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * .82,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

/// A user's rank inside CyberDog, shown as a small, deliberately quiet badge. CyberDog is the
/// app; a rank such as NightDog is a status within it. The rank arrives as an id so new ranks can
/// be added to [_labels] without touching the screens that show the badge.
class UserRankBadge extends StatelessWidget {
  const UserRankBadge({super.key, required this.rank});

  /// The rank every user has until more ranks exist.
  static const defaultRank = 'nightdog';

  static const _labels = {'nightdog': 'NIGHTDOG', 'cyberdog': 'CYBERDOG'};

  /// Ranks that have been earned are drawn in the brand blue; the starting rank stays muted.
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

/// The send button: a round blue button with an arrow. On press the arrow nudges up and the glow
/// strengthens slightly.
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
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: CyberDog.outgoing,
            shape: BoxShape.circle,
            boxShadow: _down ? CyberDog.glowPressed : CyberDog.glow,
          ),
          alignment: Alignment.center,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 120),
            offset: _down ? const Offset(0, -.1) : Offset.zero,
            child: const Icon(Icons.arrow_upward_rounded, size: 24, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
