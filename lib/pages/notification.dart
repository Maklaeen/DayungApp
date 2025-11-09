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
    required bool isUnread,
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
                  offset: Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: Offset(0, 2),
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
                    color: iconBg, // use the passed bg color
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: isWide ? 28 : 26),
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
      final unitId = context.read<DayungUnitProvider>().currentUnitId;
      if (unitId != null) {
        _currentUnitId = unitId;
        _fetchAll(unitId: _currentUnitId);
      } else {
        setState(() {
          _currentUnitId = null;
          _items = [];
          _loading = false;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newId = context.watch<DayungUnitProvider>().currentUnitId;
    if (newId != _currentUnitId) {
      _currentUnitId = newId;
      if (_currentUnitId != null) {
        if (mounted) setState(() => _items = []);
        _fetchAll(unitId: _currentUnitId);
      } else {
        setState(() {
          _items = [];
          _loading = false;
        });
      }
    }
  }

  void _showNotificationModal({
    required String title,
    required String message,
    required String time,
    required IconData icon,
    required Color iconColor,
    required bool isAnnouncement,
  }) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context, // use State's context
      useRootNavigator: true, // ensure a Navigator is available
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final mq = MediaQuery.maybeOf(ctx);
        final width =
            mq?.size.width ?? MediaQuery.of(context).size.width; // fallback
        final isWide = width > 700;
        return Container(
          padding: EdgeInsets.only(bottom: mq?.viewInsets.bottom ?? 0),
          decoration: const BoxDecoration(
            color: kCardBg,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 24,
                offset: Offset(0, -8),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isWide ? 40 : 24,
                28,
                isWide ? 40 : 24,
                24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: iconColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Icon(icon, color: iconColor, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: isWide ? 22 : 18,
                              fontWeight: FontWeight.w800,
                              color: kText,
                              fontFamily: 'Montserrat',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: kSubText,
                          ),
                          onPressed: () =>
                              Navigator.of(ctx, rootNavigator: true).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: isWide ? 16 : 15,
                        color: kText,
                        fontFamily: 'OpenSans',
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          size: 16,
                          color: kSubText,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: isWide ? 14 : 13,
                            color: kSubText,
                            fontFamily: 'OpenSans',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isAnnouncement)
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: kPrimary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Announcement',
                                style: TextStyle(
                                  color: kPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _fetchAll({int? unitId}) async {
    setState(() => _loading = true);
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    final scopedUnitId = unitId ?? _currentUnitId;

    if (uid == null) {
      setState(() {
        _items = [];
        _loading = false;
      });
      return;
    }

    try {
      // 1) Notifications for this user (optionally scoped to unit)
      var notifQuery = sb
          .from('notifications')
          .select(
            'id, type, title, body, created_at, read_at, dayung_unit_id, announcement_id',
          )
          .eq('recipient_id', uid);
      if (scopedUnitId != null) {
        notifQuery = notifQuery.eq('dayung_unit_id', scopedUnitId);
      }
      final notifData = List<Map<String, dynamic>>.from(
        await notifQuery.order('created_at', ascending: false),
      );

      // Capture announcement_ids already present in notifications to avoid duplicates
      final announcedInNotifs = notifData
          .map((n) => n['announcement_id'])
          .where((x) => x != null)
          .cast<int>()
          .toSet();

      // 2) Direct announcements for the current unit (if any)
      List<Map<String, dynamic>> annData = const [];
      if (scopedUnitId != null) {
        final ann = await sb
            .from('announcements')
            .select('id, dayung_unit_id, title, body, created_at')
            .eq('dayung_unit_id', scopedUnitId)
            .order('created_at', ascending: false);
        annData = List<Map<String, dynamic>>.from(ann);
      }

      // 3) Read states for announcements (per-user)
      final annIds = annData.map((a) => a['id'] as int).toList();
      Set<int> readAnn = {};
      if (annIds.isNotEmpty) {
        final reads = await sb
            .from('announcement_reads')
            .select('announcement_id')
            .eq('user_id', uid)
            .inFilter('announcement_id', annIds);
        readAnn = (reads as List)
            .map((e) => (e as Map)['announcement_id'] as int)
            .toSet();
      }

      // 4) Map direct announcements to unified item shape, excluding those already in notifications
      final mappedAnnouncements = annData
          .where((a) => !announcedInNotifs.contains(a['id']))
          .map<Map<String, dynamic>>((a) {
            return {
              'id': a['id'],
              'type': 'announcement_direct',
              'title': a['title'],
              'body': a['body'],
              'created_at': a['created_at'],
              'read_at': null, // announcements track read via is_read
              'is_read': readAnn.contains(a['id']),
              'dayung_unit_id': a['dayung_unit_id'],
            };
          })
          .toList();

      // 5) Merge and sort by created_at desc
      final merged =
          <Map<String, dynamic>>[...notifData, ...mappedAnnouncements]
            ..sort((a, b) {
              final ta = DateTime.tryParse('${a['created_at']}') ?? DateTime(0);
              final tb = DateTime.tryParse('${b['created_at']}') ?? DateTime(0);
              return tb.compareTo(ta);
            });

      if (!mounted) return;
      setState(() {
        _items = merged;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load notifications: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Modern Curved Header
            Container(
              padding: EdgeInsets.fromLTRB(
                8,
                isWide ? 36 : 28,
                isWide ? 24 : 16,
                isWide ? 32 : 24,
              ),
              decoration: const BoxDecoration(
                color: kPrimary,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF1E40AF),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Back',
                  ),
                  // const SizedBox(width: 4),
                  // const Icon(
                  //   Icons.notifications_rounded,
                  //   color: Colors.white,
                  //   size: 26,
                  // ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: isWide ? 24 : 17,
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
                        // notifications
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

                        // direct announcements (no corresponding notification)
                        final unreadDirect = _items.where(
                          (n) =>
                              n['type'] == 'announcement_direct' &&
                              (n['is_read'] != true),
                        );
                        for (final ann in unreadDirect) {
                          final id = ann['id'];
                          if (id is int) {
                            await _markAnnouncementRead(id);
                          } else if (id is num) {
                            await _markAnnouncementRead(id.toInt());
                          }
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
                      size: 20,
                    ),
                    label: const Text(
                      'Mark all read',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: kPrimary.withOpacity(0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              color: kPrimary,
                              strokeWidth: 3,
                            ),
                            SizedBox(height: 18),
                            Text(
                              'Loading notifications...',
                              style: TextStyle(
                                color: kSubText,
                                fontSize: 15,
                                fontFamily: 'OpenSans',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
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
                        final isAnnouncement =
                            n['type'] == 'announcement' ||
                            n['type'] == 'announcement_direct';
                        final isDirect = n['type'] == 'announcement_direct';
                        final isUnread = isDirect
                            ? (n['is_read'] != true)
                            : (n['read_at'] == null);

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () async {
                              // Optimistic UI: mark as read locally to avoid “hang” feel
                              if (isDirect && isUnread) {
                                setState(() {
                                  _items[i] = {...n, 'is_read': true};
                                });
                              }

                              bool ok = true;
                              try {
                                if (isDirect) {
                                  if (isUnread) {
                                    final id = n['id'];
                                    ok = await _markAnnouncementRead(
                                      id is num ? id.toInt() : int.parse('$id'),
                                    );
                                  }
                                } else {
                                  final sb = Supabase.instance.client;
                                  await sb
                                      .from('notifications')
                                      .update({
                                        'read_at': DateTime.now()
                                            .toIso8601String(),
                                      })
                                      .eq('id', n['id'])
                                      .isFilter('read_at', null);
                                }
                              } catch (_) {
                                ok = false;
                              }

                              // Show modal regardless of backend outcome
                              _showNotificationModal(
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
                                iconColor: isAnnouncement ? kPrimary : kAccent,
                                isAnnouncement: isAnnouncement,
                              );

                              // Refresh list in background (do not await)
                              // ignore: unawaited_futures
                              _fetchAll(unitId: _currentUnitId);

                              if (!ok && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not mark announcement as read.',
                                    ),
                                  ),
                                );
                              }
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
                          ),
                        );
                      },
                    ),
            ),
          ],
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

Future<bool> _markAnnouncementRead(int announcementId) async {
  final sb = Supabase.instance.client;
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return false;

  try {
    await sb
        .from('announcement_reads')
        .upsert(
          [
            {
              'announcement_id': announcementId,
              'user_id': uid,
              'read_at': DateTime.now().toIso8601String(),
            },
          ],
          onConflict: 'announcement_id,user_id',
          ignoreDuplicates: true,
        );
    return true;
  } on PostgrestException catch (e) {
    if (e.code == '23505') {
      // already exists, update timestamp best-effort
      try {
        await sb
            .from('announcement_reads')
            .update({'read_at': DateTime.now().toIso8601String()})
            .eq('announcement_id', announcementId)
            .eq('user_id', uid);
      } catch (_) {}
      return true;
    }
    // any other error -> treat as failure (e.g., RLS)
    return false;
  } catch (_) {
    return false;
  }
}
