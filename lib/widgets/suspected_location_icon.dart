import 'package:flutter/material.dart';

class SuspectedLocationIcon extends StatelessWidget {
  const SuspectedLocationIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.orange,
        border: Border.all(
          color: Colors.white,
          width: 2,
        ),
      ),
      child: const Icon(
        Icons.help_outline,
        color: Colors.white,
        size: 12,
      ),
    );
  }
}