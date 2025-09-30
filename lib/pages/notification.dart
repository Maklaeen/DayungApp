import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Palette
const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kWarn = Color(0xFFF57C00);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();

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

  static Widget _notificationCard({
    required String title,
    required String message,
    required String time,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required bool isWide,
    required bool isUnread, // <-- add this
  }) {
    return Semantics(
      label: '$title. $message. $time.',
      child: Stack(
        children: [
          Container(
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
          if (isUnread)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationPageState extends State<NotificationPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  Future<void> _fetchAll() async {
    setState(() => _loading = true);
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _items = [];
        _loading = false;
      });
      return;
    }

    // 1. Fetch notifications
    final notifData = await sb
        .from('notifications')
        .select('id, type, title, body, created_at, read_at')
        .eq('recipient_id', uid)
        .order('created_at', ascending: false);

    // 2. Fetch announcements for user's dayung memberships
    final apps = await sb
        .from('applications')
        .select('dayung_unit_id')
        .eq('user_id', uid)
        .eq('status', 'approved');
    final unitIds = List<Map<String, dynamic>>.from(apps)
        .map((a) => a['dayung_unit_id'])
        .where((id) => id != null)
        .toSet()
        .toList();

    List<Map<String, dynamic>> annData = [];
    Set readIds = {};
    if (unitIds.isNotEmpty) {
      annData = await sb
          .from('announcements')
          .select('id, title, body, created_at, dayung_unit_id')
          .inFilter('dayung_unit_id', unitIds)
          .order('created_at', ascending: false);

      // Fetch which announcements this user has read
      final reads = await sb
          .from('announcement_reads')
          .select('announcement_id')
          .eq('user_id', uid);
      readIds = Set.from((reads as List).map((r) => r['announcement_id']));

      annData = List<Map<String, dynamic>>.from(annData)
          .map(
            (a) => {
              ...a,
              'type': 'announcement_direct',
              'is_read': readIds.contains(a['id']),
            },
          )
          .toList();
    }

    // 3. Merge and sort
    final all = [...List<Map<String, dynamic>>.from(notifData), ...annData];
    all.sort(
      (a, b) => DateTime.parse(
        b['created_at'].toString(),
      ).compareTo(DateTime.parse(a['created_at'].toString())),
    );

    setState(() {
      _items = all;
      _loading = false;
    });
  }

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
            onPressed: () async {
              final sb = Supabase.instance.client;
              final uid = sb.auth.currentUser?.id;
              if (uid != null) {
                // Notifications -> set read_at
                await sb
                    .from('notifications')
                    .update({'read_at': DateTime.now().toIso8601String()})
                    .eq('recipient_id', uid)
                    .isFilter('read_at', null);

                // Announcements -> per-user reads via upsert
                final unreadAnn = _items.where(
                  (n) =>
                      n['type'] == 'announcement_direct' &&
                      !(n['is_read'] ?? false),
                );
                if (unreadAnn.isNotEmpty) {
                  await sb
                      .from('announcement_reads')
                      .upsert(
                        unreadAnn
                            .map(
                              (ann) => {
                                'announcement_id': ann['id'],
                                'user_id': uid,
                                'read_at': DateTime.now().toIso8601String(),
                              },
                            )
                            .toList(),
                        onConflict: 'announcement_id,user_id',
                      );
                }
                await _fetchAll();
              }
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
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
            ? NotificationPage._emptyState(isWide: isWide)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, i) {
                  final n = _items[i];
                  final isNotif =
                      n['type'] == 'membership_approved' ||
                      n['type'] == 'announcement';
                  final isAnnouncement = n['type'] == 'announcement_direct';
                  final isUnread = isNotif
                      ? n['read_at'] == null
                      : !(n['is_read'] ?? false);

                  return GestureDetector(
                    onTap: () async {
                      final sb = Supabase.instance.client;
                      final uid = sb.auth.currentUser?.id;
                      if (isNotif) {
                        await sb
                            .from('notifications')
                            .update({
                              'read_at': DateTime.now().toIso8601String(),
                            })
                            .eq('id', n['id']);
                      } else if (isAnnouncement && uid != null) {
                        await sb.from('announcement_reads').upsert([
                          {
                            'announcement_id': n['id'],
                            'user_id': uid,
                            'read_at': DateTime.now().toIso8601String(),
                          },
                        ], onConflict: 'announcement_id,user_id');
                      }
                      await _fetchAll();
                    },
                    child: NotificationPage._notificationCard(
                      title:
                          n['title'] ??
                          (isAnnouncement ? 'Announcement' : 'Notification'),
                      message: n['body'] ?? '',
                      time: _formatTime(n['created_at']),
                      icon: isAnnouncement
                          ? Icons.campaign
                          : Icons.notifications_active_rounded,
                      iconBg: isAnnouncement
                          ? kPrimary.withOpacity(0.10)
                          : kAccent.withOpacity(0.10),
                      iconColor: isAnnouncement ? kPrimary : kAccent,
                      isWide: isWide,
                      isUnread: isUnread,
                    ),
                  );
                },
              ),
      ),
    );
  }

  static String _formatTime(dynamic iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso.toString());
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
