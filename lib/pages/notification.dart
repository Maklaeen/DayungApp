import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';

class NotificationPage extends StatelessWidget {
  const NotificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    return Scaffold(
      backgroundColor: const Color(0xFFFEFFFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 28, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: AutoSizeText(
          'Dayung',
          style: TextStyle(
            fontSize: isWide ? 28 : 22,
            fontWeight: FontWeight.bold,
            color: Colors.black,
            fontFamily: 'Montserrat',
          ),
          maxLines: 1,
          minFontSize: 16,
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: AutoSizeText(
                'Notification',
                style: TextStyle(
                  fontSize: isWide ? 26 : 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Montserrat',
                ),
                maxLines: 1,
                minFontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                children: [
                  _notificationCard(
                    icon: Icons.campaign,
                    iconColor: Colors.blue,
                    title: 'Announcement from President',
                    message: 'Meeting on July 16, 2025\nat 3PM',
                    time: '2 oras na ang nilabay',
                    isWide: isWide,
                  ),
                  _deathNoticeCard(
                    name: 'Sophia Martinez has passed away',
                    date: 'February 17, 2025',
                    isWide: isWide,
                  ),
                  _deathNoticeCard(
                    name: 'Liam Anderson has passed away',
                    date: 'March 20, 2024',
                    isWide: isWide,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _notificationCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String time,
    required bool isWide,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AutoSizeText(
              title,
              style: TextStyle(
                fontSize: isWide ? 18 : 15,
                fontWeight: FontWeight.bold,
                fontFamily: 'Montserrat',
              ),
              maxLines: 1,
              minFontSize: 12,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: iconColor, size: isWide ? 28 : 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: isWide ? 18 : 14,
                      fontFamily: 'OpenSans',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              time,
              style: TextStyle(
                fontSize: isWide ? 16 : 13,
                color: Colors.black54,
                fontFamily: 'OpenSans',
              ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🕊️', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 8),
                Expanded(
                  child: AutoSizeText(
                    name,
                    style: TextStyle(
                      fontSize: isWide ? 18 : 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Montserrat',
                    ),
                    maxLines: 1,
                    minFontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              date,
              style: TextStyle(
                fontSize: isWide ? 16 : 13,
                color: Colors.black54,
                fontFamily: 'OpenSans',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
