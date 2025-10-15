import 'package:flutter/material.dart';
import 'dart:math' as math;

class AppTopHeader extends StatelessWidget {
  final String title;
  final String? subtitle; // e.g., 'Barangay, City'
  final String? profileUrl;
  final VoidCallback onNotificationTap;
  final VoidCallback onProfileTap;
  final int? notificationBadge;
  final EdgeInsets padding;
  final double avatarRadius;
  final List<Widget>? trailingActions; // optional extra actions before notif
  final double? textScale;

  const AppTopHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.profileUrl,
    required this.onNotificationTap,
    required this.onProfileTap,
    this.notificationBadge,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 4),
    this.avatarRadius = 28,
    this.trailingActions,
    this.textScale,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Use provided textScale or lock to 1.0 by default to keep header consistent across pages
    final scale = textScale ?? 1.0; // or: math.min(1.0, media.textScaleFactor)

    return MediaQuery(
      // Override only textScaleFactor so the header looks the same in all pages
      data: media.copyWith(textScaleFactor: scale),
      child: Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Montserrat',
                        color: Color(0xFF1F2937),
                        height: 1.1,
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 14,
                              color: Color(0xFF4B5563),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'OpenSans',
                                  color: Color(0xFF4B5563),
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (trailingActions != null) ...[
              ...trailingActions!,
              const SizedBox(width: 4),
            ],
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  tooltip: 'Notifications',
                  icon: const Icon(
                    Icons.notifications_outlined,
                    color: Color(0xFFF57C00),
                    size: 30,
                  ),
                  onPressed: onNotificationTap,
                ),
                if (notificationBadge != null && notificationBadge! > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFFC62828),
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      child: Center(
                        child: Text(
                          '${notificationBadge! > 99 ? '99+' : notificationBadge}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            GestureDetector(
              onTap: onProfileTap,
              child: CircleAvatar(
                radius: avatarRadius,
                backgroundColor: const Color(0xFF0D47A1),
                backgroundImage: (profileUrl != null && profileUrl!.isNotEmpty)
                    ? NetworkImage(profileUrl!)
                    : null,
                child: (profileUrl == null || profileUrl!.isEmpty)
                    ? const Icon(Icons.person, color: Colors.white, size: 30)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
