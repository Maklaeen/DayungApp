import 'package:flutter/material.dart';

const Color kSecretaryHeaderStart = Color(0xFF1E3A8A);
const Color kSecretaryHeaderEnd = Color(0xFF2563EB);
const Color kSecretaryHeaderText = Colors.white;

class SecretaryPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final EdgeInsetsGeometry? padding;
  final bool usePaymentStyle;

  const SecretaryPageHeader({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.padding,
    this.usePaymentStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;

    if (usePaymentStyle) {
      return Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.fromLTRB(20, 28, 20, 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kSecretaryHeaderStart, kSecretaryHeaderEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(28),
            bottomRight: Radius.circular(28),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(
                Icons.chevron_left_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                  if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding:
          padding ??
          EdgeInsets.fromLTRB(20, isWide ? 48 : 32, 20, isWide ? 32 : 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kSecretaryHeaderStart, kSecretaryHeaderEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332563EB),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.chevron_left_rounded,
              color: kSecretaryHeaderText,
              size: 28,
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, color: kSecretaryHeaderText, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isWide ? 24 : 20,
                    fontWeight: FontWeight.w800,
                    color: kSecretaryHeaderText,
                    fontFamily: 'Montserrat',
                    letterSpacing: 0.2,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isWide ? 14 : 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SecretarySheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onClose;

  const SecretarySheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [kSecretaryHeaderStart, kSecretaryHeaderEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white38,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              IconButton(
                onPressed: onClose ?? () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
