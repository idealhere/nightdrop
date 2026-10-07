import 'package:flutter/material.dart';

/// The CyberDog wordmark, with "Dog" in the accent colour.
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key, this.fontSize = 20});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        text: 'CYBER',
        children: [
          TextSpan(text: 'DOG', style: TextStyle(color: scheme.secondary)),
        ],
      ),
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: 2,
        color: scheme.onSurface,
      ),
    );
  }
}
