import 'package:flutter/material.dart';

/// The app-wide backdrop: a deep navy with one barely visible violet accent. Static and free of
/// imagery, so nothing competes with the conversation.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF050816),
        gradient: RadialGradient(
          center: Alignment(.5, -.35),
          radius: 1.1,
          colors: [Color(0xFF0E1030), Color(0xFF050816)],
        ),
      ),
      child: child,
    );
  }
}
