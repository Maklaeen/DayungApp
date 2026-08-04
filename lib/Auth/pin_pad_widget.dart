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
  final Widget? topContent;

  const PinPad({
    super.key,
    required this.title,
    required this.subtitle,
    required this.filledCount,
    required this.onDigit,
    required this.onDelete,
    this.error,
    this.bottomAction,
    this.topContent,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 600;
    final keySize = isWide ? 80.0 : (size.width - 96) / 3 - 12;
    final clampedKey = keySize.clamp(64.0, 88.0);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isWide ? 48 : 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (topContent != null) ...[topContent!, const SizedBox(height: 28)],
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Montserrat',
                  color: kNeutralText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: kSubtleText,
                  fontFamily: 'OpenSans',
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 36),
              // PIN dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final filled = i < filledCount;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? kPrimary : Colors.transparent,
                      border: Border.all(
                        color: filled ? kPrimary : const Color(0xFFCBD5E1),
                        width: 2.5,
                      ),
                      boxShadow: filled
                          ? [
                              BoxShadow(
                                color: kPrimary.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                  );
                }),
              ),
              // Error message
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: error != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: kDanger.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: kDanger.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                color: kDanger,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  error!,
                                  style: const TextStyle(
                                    color: kDanger,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'OpenSans',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox(height: 0),
              ),
              const SizedBox(height: 40),
              // Numpad
              for (final row in [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
                ['', '0', '⌫'],
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: row.map((key) {
                      if (key.isEmpty) {
                        return SizedBox(width: clampedKey, height: clampedKey);
                      }
                      return _PinKey(
                        label: key,
                        size: clampedKey,
                        onTap: () => key == '⌫' ? onDelete() : onDigit(key),
                      );
                    }).toList(),
                  ),
                ),
              if (bottomAction != null) ...[
                const SizedBox(height: 8),
                bottomAction!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PinKey extends StatefulWidget {
  final String label;
  final double size;
  final VoidCallback onTap;

  const _PinKey({
    required this.label,
    required this.size,
    required this.onTap,
  });

  @override
  State<_PinKey> createState() => _PinKeyState();
}

class _PinKeyState extends State<_PinKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDelete = widget.label == '⌫';

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDelete
              ? Colors.transparent
              : _pressed
                  ? kPrimary.withValues(alpha: 0.12)
                  : Colors.white,
          border: isDelete
              ? null
              : Border.all(
                  color: _pressed
                      ? kPrimary.withValues(alpha: 0.3)
                      : const Color(0xFFE2E8F0),
                  width: 1.5,
                ),
          boxShadow: isDelete || _pressed
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Center(
          child: isDelete
              ? Icon(
                  Icons.backspace_outlined,
                  size: widget.size * 0.35,
                  color: _pressed ? kPrimary : kSubtleText,
                )
              : Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: widget.size * 0.38,
                    fontWeight: FontWeight.w600,
                    color: _pressed ? kPrimary : kNeutralText,
                    fontFamily: 'Montserrat',
                  ),
                ),
        ),
      ),
    );
  }
}
