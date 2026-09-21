import 'package:flutter/material.dart';

class DayungBackButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool enabled;

  const DayungBackButton({
    super.key,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: enabled ? 0.2 : 0.08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: Colors.white.withValues(alpha: enabled ? 0.3 : 0.12),
        ),
      ),
      child: IconButton(
        tooltip: 'Back',
        padding: EdgeInsets.zero,
        onPressed: enabled ? onPressed : null,
        icon: const Icon(Icons.arrow_back_rounded, size: 21),
      ),
    );
  }
}
