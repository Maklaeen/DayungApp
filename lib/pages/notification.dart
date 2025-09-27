import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';

// Palette
const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kWarn = Color(0xFFF57C00);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);

class NotificationPage extends StatelessWidget {
  const NotificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 28, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        title: AutoSizeText(
          'Notifications',
          style: TextStyle(
            fontSize: isWide ? 28 : 24,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            fontFamily: 'Montserrat',
            letterSpacing: 0.3,
          ),
          maxLines: 1,
          minFontSize: 18,
        ),
        centerTitle: false,
        actions: [
          TextButton.icon(
            onPressed: () {
              // TODO: mark all as read logic
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All notifications marked as read'),
                ),
              );
            },
            icon: const Icon(Icons.done_all, color: Colors.white),
            label: const Text(
              'Mark all read',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _sectionHeader('Announcements', isWide: isWide),
            _notificationCard(
              title: 'Announcement from President',
              message: 'Meeting on July 16, 2025 at 3PM',
              time: '2 hours ago',
              icon: Icons.campaign,
              iconBg: kPrimary.withOpacity(0.10),
              iconColor: kPrimary,
              isWide: isWide,
            ),
            const SizedBox(height: 14),
            _sectionHeader('Recent Deaths', isWide: isWide),
            _deathNoticeCard(
              name: 'Sophia Martinez has passed away',
              date: 'February 17, 2025',
              isWide: isWide,
            ),
            const SizedBox(height: 12),
            _deathNoticeCard(
              name: 'Liam Anderson has passed away',
              date: 'March 20, 2024',
              isWide: isWide,
            ),
            const SizedBox(height: 16),
            // Empty-state example (show when no notifications)
            // _emptyState(isWide: isWide),
          ],
        ),
      ),
    );
  }

  static Widget _sectionHeader(String text, {required bool isWide}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: isWide ? 20 : 18,
          fontWeight: FontWeight.w800,
          color: kNeutralText,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  static Widget _notificationCard({
    required String title,
    required String message,
    required String time,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required bool isWide,
  }) {
    return Semantics(
      label: '$title. $message. $time.',
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE6E8EF)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: isWide ? 48 : 44,
              height: isWide ? 48 : 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: isWide ? 26 : 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoSizeText(
                    title,
                    style: TextStyle(
                      fontSize: isWide ? 20 : 18,
                      fontWeight: FontWeight.w800,
                      color: kNeutralText,
                      fontFamily: 'Montserrat',
                    ),
                    maxLines: 2,
                    minFontSize: 14,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: isWide ? 18 : 16,
                      height: 1.35,
                      color: kNeutralText,
                      fontFamily: 'OpenSans',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 16,
                        color: kSubtleText,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: isWide ? 15 : 14,
                          color: kSubtleText,
                          fontFamily: 'OpenSans',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'More options',
              onPressed: () {
                // TODO: Add actions (e.g., view details, delete)
              },
              icon: const Icon(Icons.more_vert, color: kSubtleText),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _deathNoticeCard({
    required String name,
    required String date,
    required bool isWide,
  }) {
    return Semantics(
      label: '$name. Date: $date.',
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE6E8EF)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: isWide ? 48 : 44,
              height: isWide ? 48 : 44,
              decoration: BoxDecoration(
                color: kDanger.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('🕊️', style: TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoSizeText(
                    name,
                    style: TextStyle(
                      fontSize: isWide ? 20 : 18,
                      fontWeight: FontWeight.w800,
                      color: kNeutralText,
                      fontFamily: 'Montserrat',
                    ),
                    maxLines: 2,
                    minFontSize: 14,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    date,
                    style: TextStyle(
                      fontSize: isWide ? 16 : 15,
                      color: kSubtleText,
                      fontFamily: 'OpenSans',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _emptyState({required bool isWide}) {
    return Container(
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6E8EF)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.notifications_none,
            size: isWide ? 64 : 56,
            color: kPrimary,
          ),
          const SizedBox(height: 12),
          Text(
            'You’re all caught up',
            style: TextStyle(
              fontSize: isWide ? 20 : 18,
              fontWeight: FontWeight.w700,
              color: kNeutralText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'No new notifications at the moment.',
            style: TextStyle(fontSize: isWide ? 16 : 15, color: kSubtleText),
          ),
        ],
      ),
    );
  }
}
