import 'package:flutter/material.dart';

class DayungBackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const DayungBackButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: IconButton(
        tooltip: 'Back',
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: const Icon(
          Icons.arrow_back_rounded,
          color: Colors.white,
          size: 21,
        ),
      ),
    );
  }
}
