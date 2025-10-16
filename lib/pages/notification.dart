import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Additional colors for notification-specific styling
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimaryLight = Color(0xFF3B82F6);
const kAccentDark = Color(0xFF059669);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);
const double kEdge = 16;

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();

  static Widget _emptyState({required bool isWide}) {
    return Center(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16),
        padding: EdgeInsets.all(isWide ? 32 : 24),
        decoration: BoxDecoration(
          color: kCardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kBorderColor.withOpacity(0.3), width: 1),
          boxShadow: [
            BoxShadow(
              color: kPrimary.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: isWide ? 64 : 56,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'You’re all caught up',
              style: TextStyle(
                fontSize: isWide ? 22 : 20,
                fontWeight: FontWeight.w800,
                color: kText,
                fontFamily: 'Montserrat',
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No new notifications at the moment.',
              style: TextStyle(
                fontSize: isWide ? 16 : 15,
                color: kSubText,
                fontFamily: 'OpenSans',
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
    required bool isUnread, // <-- add this
  }) {
    return Semantics(
      label: '$title. $message. $time.',
      child: Stack(
        children: [
          Container(
            margin: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16),
            decoration: BoxDecoration(
              color: kCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: kBorderColor.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: kPrimary.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: EdgeInsets.all(isWide ? 20 : 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: isWide ? 52 : 48,
                  height: isWide ? 52 : 48,
                  decoration: BoxDecoration(
                    color: kPrimary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: isWide ? 28 : 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AutoSizeText(
                        title,
                        style: TextStyle(
                          fontSize: isWide ? 18 : 16,
                          fontWeight: FontWeight.w800,
                          color: kText,
                          fontFamily: 'Montserrat',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: TextStyle(
                          fontSize: isWide ? 15 : 14,
                          height: 1.4,
                          color: kText,
                          fontFamily: 'OpenSans',
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 14,
                            color: kSubText,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: isWide ? 13 : 12,
                              color: kSubText,
                              fontFamily: 'OpenSans',
                              fontWeight: FontWeight.w500,
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
                  icon: Icon(Icons.more_vert_rounded, color: kSubText),
                ),
              ],
            ),
          ),
          if (isUnread)
            Positioned(
              top: 12,
              right: isWide ? 40 : 32,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kPrimary.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
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
  int? _currentUnitId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _currentUnitId = context.read<DayungUnitProvider>().currentUnitId;
      _fetchAll(unitId: _currentUnitId);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newId = context.watch<DayungUnitProvider>().currentUnitId;
    if (newId != _currentUnitId) {
      _currentUnitId = newId;
      if (mounted) setState(() => _items = []); // clear stale
      _fetchAll(unitId: _currentUnitId);
    }
  }

  Future<void> _fetchAll({int? unitId}) async {
    setState(() => _loading = true);
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    final scopedUnitId = unitId ?? _currentUnitId; // NEW

    if (uid == null) {
      setState(() {
        _items = [];
        _loading = false;
      });
      return;
    }

    try {
      // Notifications addressed to the user, scoped to current unit
      var notifQuery = sb
          .from('notifications')
          .select('id, type, title, body, created_at, read_at, dayung_unit_id')
          .eq('recipient_id', uid);

      if (scopedUnitId != null) {
        notifQuery = notifQuery.eq('dayung_unit_id', scopedUnitId);
      }

      final notifData = List<Map<String, dynamic>>.from(
        await notifQuery.order('created_at', ascending: false),
      );

      // Announcements only for current unit
      List<Map<String, dynamic>> annData = [];
      if (scopedUnitId != null) {
        final results = await Future.wait([
          sb
              .from('announcements')
              .select('id, title, body, created_at, dayung_unit_id')
              .eq('dayung_unit_id', scopedUnitId)
              .order('created_at', ascending: false),
          sb
              .from('announcement_reads')
              .select('announcement_id')
              .eq('user_id', uid),
        ]);

        final anns = List<Map<String, dynamic>>.from(results[0] as List);
        final reads = Set.from(
          (results[1] as List)
              .map((r) => r['announcement_id'])
              .where((v) => v != null),
        );

        annData = anns
            .map(
              (a) => {
                ...a,
                'type': 'announcement_direct',
                'is_read': reads.contains(a['id']),
              },
            )
            .toList();
      }

      // Extra safety: drop any row not matching scoped unit
      final filteredNotif = scopedUnitId == null
          ? notifData
          : notifData
                .where((n) => n['dayung_unit_id'] == scopedUnitId)
                .toList();

      final all = [...filteredNotif, ...annData]
        ..sort(
          (a, b) => DateTime.parse(
            b['created_at'].toString(),
          ).compareTo(DateTime.parse(a['created_at'].toString())),
        );

      if (!mounted) return;
      setState(() {
        _items = all;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load notifications')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    return Scaffold(
      backgroundColor: kBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom App Bar
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 24 : 16,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: kPrimary,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimary.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_rounded,
                        size: 24,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Back',
                    ),
                    Expanded(
                      child: AutoSizeText(
                        'Notifications',
                        style: TextStyle(
                          fontSize: isWide ? 28 : 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontFamily: 'Montserrat',
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final sb = Supabase.instance.client;
                        final uid = sb.auth.currentUser?.id;
                        if (uid != null) {
                          // Only mark current unit's notifications as read
                          var upd = sb
                              .from('notifications')
                              .update({
                                'read_at': DateTime.now().toIso8601String(),
                              })
                              .eq('recipient_id', uid)
                              .isFilter('read_at', null);
                          if (_currentUnitId != null) {
                            upd = upd.eq(
                              'dayung_unit_id',
                              _currentUnitId as Object,
                            );
                          }
                          await upd;

                          // Announcements: only current unit’s
                          final unreadAnn = _items.where(
                            (n) =>
                                n['type'] == 'announcement_direct' &&
                                !(n['is_read'] ?? false) &&
                                (_currentUnitId == null ||
                                    n['dayung_unit_id'] == _currentUnitId),
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
                                          'read_at': DateTime.now()
                                              .toIso8601String(),
                                        },
                                      )
                                      .toList(),
                                  onConflict: 'announcement_id,user_id',
                                );
                          }
                          await _fetchAll(unitId: _currentUnitId);
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Marked current unit as read'),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.done_all_rounded,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Mark all read',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'OpenSans',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: kPrimary,
                          strokeWidth: 3,
                        ),
                      )
                    : _items.isEmpty
                    ? NotificationPage._emptyState(isWide: isWide)
                    : ListView.separated(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (context, i) {
                          final n = _items[i];
                          final isNotif =
                              n['type'] == 'membership_approved' ||
                              n['type'] == 'announcement';
                          final isAnnouncement =
                              n['type'] == 'announcement_direct';
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
                                      'read_at': DateTime.now()
                                          .toIso8601String(),
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
                              await _fetchAll(
                                unitId: _currentUnitId,
                              ); // keep scoped
                            },
                            child: NotificationPage._notificationCard(
                              title:
                                  n['title'] ??
                                  (isAnnouncement
                                      ? 'Announcement'
                                      : 'Notification'),
                              message: n['body'] ?? '',
                              time: _formatTime(n['created_at']),
                              icon: isAnnouncement
                                  ? Icons.campaign_rounded
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
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(dynamic iso) {
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
