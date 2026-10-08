import 'package:flutter/material.dart';

/// The app-wide backdrop: the brand's dark navy artwork with its two faint violet curves, dimmed
/// so that text and message bubbles stay the brightest things on screen. One static image.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF050816),
        image: DecorationImage(
          image: AssetImage('assets/brand/backdrop.jpg'),
          fit: BoxFit.cover,
          opacity: .38,
        ),
      ),
      // The curves are brightest in the lower half, which is where chat lists and the composer
      // are: a shade that deepens towards the bottom keeps them behind the content.
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00050816), Color(0x8C050816)],
            stops: [0.35, 1],
          ),
        ),
        child: child,
      ),
    );
  }
}
