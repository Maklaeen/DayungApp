import 'package:capstone_app/ui/theme/branding.dart';
import 'package:flutter/material.dart';

class PinPad extends StatelessWidget {
  final String title;
  final String subtitle;
  final int filledCount;
  final String? error;
  final void Function(String) onDigit;
  final VoidCallback onDelete;
  final Widget? bottomAction;

  const PinPad({
    super.key,
    required this.title,
    required this.subtitle,
    required this.filledCount,
    required this.onDigit,
    required this.onDelete,
    this.error,
    this.bottomAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final subtextColor = theme.colorScheme.onSurfaceVariant;

    return Column(
      children: [
        const Spacer(),
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            fontFamily: 'Montserrat',
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(fontSize: 14, color: subtextColor),
        ),
        const SizedBox(height: 32),
        // Dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (i) {
            final filled = i < filledCount;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 10),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? kPrimary : Colors.transparent,
                border: Border.all(
                  color: filled
                      ? kPrimary
                      : theme.colorScheme.outline.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
            );
          }),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error!,
            style: TextStyle(
              color: theme.colorScheme.error,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const Spacer(),
        // Numpad
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Column(
            children: [
              for (final row in [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
                ['', '0', '⌫'],
              ])
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: row.map((key) {
                    if (key.isEmpty) {
                      return const SizedBox(width: 72, height: 72);
                    }
                    return _PinKey(
                      label: key,
                      isDark: isDark,
                      textColor: textColor,
                      subtextColor: subtextColor,
                      onTap: () => key == '⌫' ? onDelete() : onDigit(key),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (bottomAction != null) bottomAction!,
        const SizedBox(height: 32),
      ],
    );
  }
}

class _PinKey extends StatelessWidget {
  final String label;
  final bool isDark;
  final Color textColor;
  final Color subtextColor;
  final VoidCallback onTap;

  const _PinKey({
    required this.label,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDelete = label == '⌫';
    final keyBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDelete ? Colors.transparent : keyBg,
          boxShadow: isDelete
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isDark ? 0.3 : 0.06,
                    ),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isDelete ? 22 : 26,
              fontWeight: FontWeight.w600,
              color: isDelete ? subtextColor : textColor,
            ),
          ),
        ),
      ),
    );
  }
}
