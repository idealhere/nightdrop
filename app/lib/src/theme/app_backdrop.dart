import 'package:flutter/material.dart';

/// The app-wide backdrop: the brand's light white-and-silver scene, washed out so that text and
/// message bubbles stay in front. One static image.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF6F8FC),
        image: DecorationImage(
          image: AssetImage('assets/brand/backdrop-light.jpg'),
          fit: BoxFit.cover,
          opacity: .42,
        ),
      ),
      // The detail of the scene fades towards the bottom, which is where chat lists and the
      // composer are: the lower half is nearly plain.
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00F6F8FC), Color(0xE6F6F8FC)],
            stops: [0.2, 0.85],
          ),
        ),
        child: child,
      ),
    );
  }
}
