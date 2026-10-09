import 'package:flutter/material.dart';

/// The CyberDog wordmark: mixed case, with "Dog" in the light cyan of the logo.
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key, this.fontSize = 20});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      const TextSpan(
        text: 'Cyber',
        children: [
          TextSpan(text: 'Dog', style: TextStyle(color: Color(0xFF22B4F2))),
        ],
      ),
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: .2,
        color: scheme.onSurface,
      ),
    );
  }
}
