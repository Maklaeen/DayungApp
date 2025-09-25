import 'package:flutter/material.dart';
import 'package:capstone_app/ui/theme/branding.dart';

class MemberHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? profileUrl;
  final VoidCallback onNotificationTap;
  final VoidCallback onProfileTap;
  final EdgeInsets padding;
  final bool responsive;
  final double avatarRadius;

  const MemberHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.profileUrl,
    required this.onNotificationTap,
    required this.onProfileTap,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 4),
    this.responsive = true,
    this.avatarRadius = 28,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final size = (responsive && w > 700) ? 34.0 : 30.0;

    return Padding(
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
                    style: kHeaderTitleStyle(size),
                  ),
                  if (subtitle != null && subtitle!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kHeaderSubStyle,
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined,
                color: kWarn, size: 30),
            onPressed: onNotificationTap,
          ),
            GestureDetector(
            onTap: onProfileTap,
            child: CircleAvatar(
              radius: avatarRadius,
              backgroundColor: kPrimary,
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
    );
  }
}