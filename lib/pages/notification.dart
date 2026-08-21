import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/utils/theme_surface.dart';
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

enum _NotificationKind {
  announcement,
  pendingPayment,
  recentDeath,
  membership,
  application,
  other,
}

class NotificationPage extends StatefulWidget {
  final VoidCallback? onBack;
  final bool showBackButton;

  const NotificationPage({super.key, this.onBack, this.showBackButton = true});

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
          border: Border.all(
            color: kBorderColor.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: kPrimary.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
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
                color: kPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: isWide ? 64 : 56,
                color: kPrimary,
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
    required String category,
    required String time,
    required IconData icon,
    required Color accentColor,
    required Color surfaceColor,
    required Color iconBg,
    required Color iconColor,
    required bool isWide,
    required bool isUnread,
  }) {
    return Semantics(
      label: '$title. $message. $time.',
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16),
        decoration: BoxDecoration(
          color: isUnread ? surfaceColor : kCardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isUnread
                ? accentColor.withValues(alpha: 0.28)
                : kBorderColor.withValues(alpha: 0.45),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: isUnread ? 0.10 : 0.05),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: EdgeInsets.all(isWide ? 22 : 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: isWide ? 56 : 52,
              height: isWide ? 56 : 52,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: iconColor, size: isWide ? 30 : 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: iconBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          category,
                          style: TextStyle(
                            fontSize: isWide ? 13 : 12,
                            fontWeight: FontWeight.w700,
                            color: iconColor,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                      ),
                      if (isUnread)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Unread',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFDC2626),
                              fontFamily: 'Montserrat',
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AutoSizeText(
                    title,
                    style: TextStyle(
                      fontSize: isWide ? 19 : 17,
                      fontWeight: FontWeight.w800,
                      color: kText,
                      fontFamily: 'Montserrat',
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: isWide ? 16 : 15,
                      height: 1.5,
                      color: kText,
                      fontFamily: 'OpenSans',
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 16,
                        color: kSubText,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          time,
                          style: TextStyle(
                            fontSize: isWide ? 14 : 13,
                            color: kSubText,
                            fontFamily: 'OpenSans',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: kSubText,
                        size: 22,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationPageState extends State<NotificationPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _markingAllRead = false;
  int? _currentUnitId;

  int? _resolveScopedUnitId(BuildContext context) {
    final memberScopedId = context.read<DayungUnitProvider>().currentUnitId;
    final roleScopedId = context.read<DayungRoleProvider>().unitId;
    return memberScopedId ?? roleScopedId;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final unitId = _resolveScopedUnitId(context);
      _currentUnitId = unitId;
      _fetchAll(unitId: _currentUnitId);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final memberScopedId = context.watch<DayungUnitProvider>().currentUnitId;
    final roleScopedId = context.watch<DayungRoleProvider>().unitId;
    final newId = memberScopedId ?? roleScopedId;
    if (newId != _currentUnitId) {
      _currentUnitId = newId;
      if (mounted) {
        setState(() => _items = []);
      }
      _fetchAll(unitId: _currentUnitId);
    }
  }

  void _showNotificationModal({
    required String title,
    required String message,
    required String category,
    required String time,
    required IconData icon,
    required Color iconColor,
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
                            color: iconColor.withValues(alpha: 0.12),
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
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: iconColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              category,
                              style: TextStyle(
                                color: iconColor,
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

  Future<void> _markApplicationNotifSeen(int id) async {
    final sb = Supabase.instance.client;
    try {
      await sb
          .from('dayung_application_notifications')
          .update({'seen': true})
          .eq('id', id)
          .eq('seen', false);
    } catch (_) {}
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
      bool isPresidentForUnit = false;
      bool isSecretaryForUnit = false;
      bool isTreasurerForUnit = false;
      if (scopedUnitId != null) {
        final unit = await sb
            .from('dayung_units')
            .select('president_id, secretary_id, treasurer_id')
            .eq('id', scopedUnitId)
            .maybeSingle();
        isPresidentForUnit = (unit?['president_id'] ?? '').toString() == uid;
        isSecretaryForUnit = (unit?['secretary_id'] ?? '').toString() == uid;
        isTreasurerForUnit = (unit?['treasurer_id'] ?? '').toString() == uid;
      }

      // 1) Personal notifications for this user across the account.
      final notifData = List<Map<String, dynamic>>.from(
        await sb
            .from('notifications')
            .select(
              'id, type, title, body, created_at, read_at, dayung_unit_id, announcement_id',
            )
            .eq('recipient_id', uid)
            .order('created_at', ascending: false),
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

      List<Map<String, dynamic>> appNotifs = [];
      if (scopedUnitId != null) {
        dynamic query = sb
            .from('dayung_application_notifications')
            .select(
              'id, application_id, dayung_unit_id, created_at, seen, applications(name,status,user_id)',
            )
            .eq('dayung_unit_id', scopedUnitId);

        if (isSecretaryForUnit && !isPresidentForUnit) {
          query = query.eq('secretary_id', uid);
        }

        final raw = await query.order('created_at', ascending: false);
        appNotifs = List<Map<String, dynamic>>.from(raw)
            .map(
              (r) => {
                'id': r['id'],
                'type': 'application_new',
                'title': 'New Application',
                'body':
                    '${(r['applications']?['name'] ?? 'Applicant')} submitted an application that is ${(r['applications']?['status'] ?? 'pending')}.',
                'created_at': r['created_at'],
                'read_at': r['seen'] == true ? r['created_at'] : null,
                'is_read': r['seen'] == true,
                'dayung_unit_id': r['dayung_unit_id'],
                'app_notif_id': r['id'],
                'application_id': r['application_id'],
              },
            )
            .toList();
      }

      List<Map<String, dynamic>> treasurerUnitUpdates = [];
      if (scopedUnitId != null && isTreasurerForUnit) {
        final notices = await sb
            .from('death_notices')
            .select(
              'id, name, created_at, date_of_death, unpaid_count, total_payment_amount, total_paid_amount',
            )
            .eq('dayung_unit_id', scopedUnitId)
            .order('created_at', ascending: false)
            .limit(12);

        final deathNoticeRows = List<Map<String, dynamic>>.from(notices);
        final recentDeathItems = deathNoticeRows.map<Map<String, dynamic>>((r) {
          final noticeId = r['id'];
          final name = (r['name'] ?? 'Death Notice').toString();
          final createdAt = r['created_at'] ?? r['date_of_death'];
          return {
            'id': 'death_notice_$noticeId',
            'type': 'recent_death_notice',
            'title': 'Recent Death Notice',
            'body': '$name was added to your unit death notice queue.',
            'created_at': createdAt,
            'read_at': createdAt,
            'is_read': true,
            'dayung_unit_id': scopedUnitId,
          };
        });

        final pendingItems = deathNoticeRows
            .where((r) {
              final unpaidCount =
                  int.tryParse('${r['unpaid_count'] ?? ''}') ?? 0;
              final totalAmount =
                  double.tryParse('${r['total_payment_amount'] ?? ''}') ?? 0;
              final paidAmount =
                  double.tryParse('${r['total_paid_amount'] ?? ''}') ?? 0;
              return unpaidCount > 0 || paidAmount < totalAmount;
            })
            .map<Map<String, dynamic>>((r) {
              final noticeId = r['id'];
              final name = (r['name'] ?? 'Death Notice').toString();
              final unpaidCount =
                  int.tryParse('${r['unpaid_count'] ?? ''}') ?? 0;
              final totalAmount =
                  double.tryParse('${r['total_payment_amount'] ?? ''}') ?? 0;
              final paidAmount =
                  double.tryParse('${r['total_paid_amount'] ?? ''}') ?? 0;
              final remainingAmount = (totalAmount - paidAmount).clamp(
                0,
                double.infinity,
              );
              return {
                'id': 'pending_collection_$noticeId',
                'type': 'pending_payment_summary',
                'title': 'Pending Payment Collection',
                'body': unpaidCount > 0
                    ? '$unpaidCount member${unpaidCount == 1 ? '' : 's'} still need to pay for $name. Remaining: PHP ${remainingAmount.toStringAsFixed(2)}.'
                    : 'Collection for $name is still incomplete. Remaining: PHP ${remainingAmount.toStringAsFixed(2)}.',
                'created_at': r['created_at'] ?? r['date_of_death'],
                'read_at': r['created_at'] ?? r['date_of_death'],
                'is_read': true,
                'dayung_unit_id': scopedUnitId,
              };
            });

        treasurerUnitUpdates = [...recentDeathItems, ...pendingItems];
      }

      // 5) Merge and sort by created_at desc
      final merged =
          <Map<String, dynamic>>[
            ...notifData,
            ...mappedAnnouncements,
            ...appNotifs,
            ...treasurerUnitUpdates,
          ]..sort((a, b) {
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

  bool _isDirectAnnouncement(Map<String, dynamic> item) {
    return item['type'] == 'announcement_direct';
  }

  bool _isApplicationNotification(Map<String, dynamic> item) {
    return item['type'] == 'application_new';
  }

  _NotificationKind _itemKind(Map<String, dynamic> item) {
    final type = '${item['type'] ?? ''}'.toLowerCase();
    final title = '${item['title'] ?? ''}'.toLowerCase();
    final body = '${item['body'] ?? ''}'.toLowerCase();
    final hasAnnouncementLink =
        item['announcement_id'] != null || type == 'announcement_direct';

    if (type == 'application_new') return _NotificationKind.application;
    if (hasAnnouncementLink) return _NotificationKind.announcement;
    if (title.contains('payment reminder') ||
        title.contains('pending payment') ||
        title.contains('payment')) {
      return _NotificationKind.pendingPayment;
    }
    if (type == 'recent_activity' ||
        title.contains('recent death') ||
        title.contains('death') ||
        body.contains('passed away') ||
        body.contains('death notice')) {
      return _NotificationKind.recentDeath;
    }
    if (type == 'membership_approved') return _NotificationKind.membership;
    return _NotificationKind.other;
  }

  bool _isUnread(Map<String, dynamic> item) {
    if (_isApplicationNotification(item) || _isDirectAnnouncement(item)) {
      return item['is_read'] != true;
    }
    return item['read_at'] == null;
  }

  String _categoryLabel(Map<String, dynamic> item) {
    switch (_itemKind(item)) {
      case _NotificationKind.announcement:
        return 'Announcement';
      case _NotificationKind.pendingPayment:
        return 'Pending Payment';
      case _NotificationKind.recentDeath:
        return 'Recent Death';
      case _NotificationKind.membership:
        return 'Membership';
      case _NotificationKind.application:
        return 'Application';
      case _NotificationKind.other:
        return 'Notification';
    }
  }

  IconData _itemIcon(Map<String, dynamic> item) {
    switch (_itemKind(item)) {
      case _NotificationKind.announcement:
        return Icons.campaign_rounded;
      case _NotificationKind.pendingPayment:
        return Icons.payments_rounded;
      case _NotificationKind.recentDeath:
        return Icons.local_florist_rounded;
      case _NotificationKind.membership:
        return Icons.verified_rounded;
      case _NotificationKind.application:
        return Icons.assignment_rounded;
      case _NotificationKind.other:
        return Icons.notifications_active_rounded;
    }
  }

  Color _itemAccent(Map<String, dynamic> item) {
    switch (_itemKind(item)) {
      case _NotificationKind.announcement:
        return kPrimary;
      case _NotificationKind.pendingPayment:
        return const Color(0xFFB45309);
      case _NotificationKind.recentDeath:
        return const Color(0xFFBE123C);
      case _NotificationKind.membership:
        return kSuccess;
      case _NotificationKind.application:
        return kAccentDark;
      case _NotificationKind.other:
        return kAccent;
    }
  }

  Color _itemSurface(Map<String, dynamic> item) {
    switch (_itemKind(item)) {
      case _NotificationKind.announcement:
        return const Color(0xFFF5F9FF);
      case _NotificationKind.pendingPayment:
        return const Color(0xFFFFFBEB);
      case _NotificationKind.recentDeath:
        return const Color(0xFFFFF1F2);
      case _NotificationKind.membership:
        return const Color(0xFFF0FDF4);
      case _NotificationKind.application:
        return const Color(0xFFECFDF5);
      case _NotificationKind.other:
        return const Color(0xFFF8FAFC);
    }
  }

  String _itemTitle(Map<String, dynamic> item) {
    final title = '${item['title'] ?? ''}'.trim();
    if (title.isNotEmpty) return title;
    switch (_itemKind(item)) {
      case _NotificationKind.announcement:
        return 'Announcement';
      case _NotificationKind.pendingPayment:
        return 'Pending Payment';
      case _NotificationKind.recentDeath:
        return 'Recent Death';
      case _NotificationKind.membership:
        return 'Membership Update';
      case _NotificationKind.application:
        return 'New Application';
      case _NotificationKind.other:
        return 'Notification';
    }
  }

  String _itemMessage(Map<String, dynamic> item) {
    final message = '${item['body'] ?? ''}'.trim();
    if (message.isNotEmpty) return message;
    if (_isApplicationNotification(item)) {
      return 'A new application needs your attention.';
    }
    return 'Open this notification to see more details.';
  }

  int _countByKind(_NotificationKind kind) {
    return _items.where((item) => _itemKind(item) == kind).length;
  }

  Widget _buildTopCategoryChip({
    required String label,
    required int count,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
                fontFamily: 'Montserrat',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markVisibleNotificationsRead() async {
    if (_markingAllRead) return;

    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;

    setState(() => _markingAllRead = true);
    try {
      await sb
          .from('notifications')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('recipient_id', uid)
          .isFilter('read_at', null);

      final unreadDirect = _items.where(
        (item) => _isDirectAnnouncement(item) && _isUnread(item),
      );
      for (final item in unreadDirect) {
        final id = item['id'];
        if (id is int) {
          await _markAnnouncementRead(id);
        } else if (id is num) {
          await _markAnnouncementRead(id.toInt());
        }
      }

      final unreadApplications = _items.where(
        (item) => _isApplicationNotification(item) && _isUnread(item),
      );
      for (final item in unreadApplications) {
        final id = item['app_notif_id'];
        if (id is int) {
          await _markApplicationNotifSeen(id);
        } else if (id is num) {
          await _markApplicationNotifSeen(id.toInt());
        }
      }

      await _fetchAll(unitId: _currentUnitId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All visible notifications marked as read'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to mark all as read: $e')));
    } finally {
      if (mounted) {
        setState(() => _markingAllRead = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;
    final unreadCount = _items.where(_isUnread).length;
    final announcementCount = _countByKind(_NotificationKind.announcement);
    final pendingPaymentCount = _countByKind(_NotificationKind.pendingPayment);
    final recentDeathCount = _countByKind(_NotificationKind.recentDeath);

    return Scaffold(
      backgroundColor: dayungPageBackground(context),
      body: SafeArea(
        child: Column(
          children: [
            // Modern Curved Header
            Container(
              padding: EdgeInsets.fromLTRB(
                30,
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
                  if (widget.showBackButton)
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                      onPressed: widget.onBack ?? () => Navigator.pop(context),
                      tooltip: 'Back',
                    ),
                  if (widget.showBackButton) const SizedBox(width: 16),
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
                    onPressed: _markingAllRead
                        ? null
                        : _markVisibleNotificationsRead,
                    icon: _markingAllRead
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.done_all_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                    label: Text(
                      _markingAllRead ? 'Updating...' : 'Mark all read',
                      style: const TextStyle(
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
            Padding(
              padding: EdgeInsets.fromLTRB(
                isWide ? 24 : 16,
                16,
                isWide ? 24 : 16,
                0,
              ),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 20 : 16,
                  vertical: isWide ? 18 : 16,
                ),
                decoration: BoxDecoration(
                  color: dayungSurface(context),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: dayungBorder(context)),
                  boxShadow: [dayungElevatedShadow(context)],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        color: kPrimary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            unreadCount == 0
                                ? 'All caught up'
                                : '$unreadCount unread notification${unreadCount == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: isWide ? 18 : 16,
                              fontWeight: FontWeight.w800,
                              color: kText,
                              fontFamily: 'Montserrat',
                            ),
                          ),

                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildTopCategoryChip(
                                label: 'Pending Payment',
                                count: pendingPaymentCount,
                                color: const Color(0xFFB45309),
                                background: const Color(0xFFFFFBEB),
                              ),
                              _buildTopCategoryChip(
                                label: 'Announcement',
                                count: announcementCount,
                                color: kPrimary,
                                background: const Color(0xFFF5F9FF),
                              ),
                              _buildTopCategoryChip(
                                label: 'Recent Death',
                                count: recentDeathCount,
                                color: const Color(0xFFBE123C),
                                background: const Color(0xFFFFF1F2),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const DayungPageSkeleton(
                      layout: DayungSkeletonLayout.list,
                      itemCount: 6,
                      padding: EdgeInsets.fromLTRB(0, 20, 0, 24),
                    )
                  : _items.isEmpty
                  ? NotificationPage._emptyState(isWide: isWide)
                  : RefreshIndicator(
                      color: kPrimary,
                      onRefresh: () => _fetchAll(unitId: _currentUnitId),
                      child: ListView.separated(
                        padding: EdgeInsets.fromLTRB(0, 20, 0, 24),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, i) {
                          final n = _items[i];
                          final isDirect = _isDirectAnnouncement(n);
                          final isApplication = _isApplicationNotification(n);
                          final isUnread = _isUnread(n);
                          final iconColor = _itemAccent(n);
                          final category = _categoryLabel(n);

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(22),
                              onTap: () async {
                                if (isUnread && mounted) {
                                  setState(() {
                                    _items[i] = {
                                      ...n,
                                      if (isApplication || isDirect)
                                        'is_read': true
                                      else
                                        'read_at': DateTime.now()
                                            .toIso8601String(),
                                    };
                                  });
                                }

                                final messenger = ScaffoldMessenger.of(context);
                                bool ok = true;
                                try {
                                  if (isApplication && isUnread) {
                                    final id = n['app_notif_id'];
                                    if (id != null) {
                                      await _markApplicationNotifSeen(
                                        id is num
                                            ? id.toInt()
                                            : int.parse('$id'),
                                      );
                                    }
                                  } else if (isDirect && isUnread) {
                                    final id = n['id'];
                                    if (id is int) {
                                      ok = await _markAnnouncementRead(id);
                                    } else if (id is num) {
                                      ok = await _markAnnouncementRead(
                                        id.toInt(),
                                      );
                                    }
                                  } else if (isUnread) {
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

                                _showNotificationModal(
                                  title: _itemTitle(n),
                                  message: _itemMessage(n),
                                  category: category,
                                  time: _formatTime(n['created_at']),
                                  icon: _itemIcon(n),
                                  iconColor: iconColor,
                                );

                                // ignore: unawaited_futures
                                _fetchAll(unitId: _currentUnitId);

                                if (!ok && mounted) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not update the notification status.',
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: NotificationPage._notificationCard(
                                title: _itemTitle(n),
                                message: _itemMessage(n),
                                category: category,
                                time: _formatTime(n['created_at']),
                                icon: _itemIcon(n),
                                accentColor: iconColor,
                                surfaceColor: _itemSurface(n),
                                iconBg: iconColor.withValues(alpha: 0.12),
                                iconColor: iconColor,
                                isWide: isWide,
                                isUnread: isUnread,
                              ),
                            ),
                          );
                        },
                      ),
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
