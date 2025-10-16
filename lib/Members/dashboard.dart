import 'dart:convert';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/pages/claims.dart';
import 'package:capstone_app/pages/notification.dart'
    hide kPrimary, kNeutralText, kPrimaryDark, kSubtleText, kWarn, kDanger;
import 'package:capstone_app/pages/paymentmethod.dart';
import 'package:capstone_app/pages/contributionhistory.dart';
import 'package:capstone_app/pages/recentdeathnotices.dart' hide kDanger;
import 'package:capstone_app/profile/profile.dart' hide kPrimary, kWarn;
import 'package:capstone_app/screens/selectdayung.dart';
import 'package:capstone_app/Auth/login.dart'
    hide kPrimary, kNeutralText, kSubtleText, kPrimaryDark, kWarn, kDanger;
import 'package:auto_size_text/auto_size_text.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/Members/top_notification.dart';

// Shared palette aligned to Secretary
const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);

class MemberDashboardPage extends StatefulWidget {
  const MemberDashboardPage({super.key});
  @override
  State<MemberDashboardPage> createState() => _MemberDashboardPageState();
}

class _MemberDashboardPageState extends State<MemberDashboardPage> {
  final supabase = Supabase.instance.client;
  RealtimeChannel? _notifChannel;
  final List<RealtimeChannel> _announcementChannels = [];
  final ScrollController _scrollController = ScrollController();
  int _unreadNotifCount = 0;

  Map<String, dynamic>? _selectedDayungUnitObj;
  String _selectedDayungUnit = 'Dayung Unit'; // align with Secretary
  String? _unitBarangay; // align with Secretary
  String? _unitCity; // align with Secretary
  // ignore: unused_field
  int? _dayungUnitId;

  // ignore: unused_field
  User? _user;
  String _fullName = 'Member';
  // ignore: unused_field
  String? _profileUrl;

  bool _showNavBar = true;
  // ignore: unused_field
  bool _loadingUser = true;
  int _currentIndex = 0;

  // Dynamic stats
  int _activeMembersCount = 0;
  bool _loadingActiveMembers = true;

  List<Map<String, dynamic>> _recentCertificates = [];
  bool _loadingCertificates = true;

  List<Map<String, dynamic>> _pendingPaymentsByDeathNotice = [];

  double _pendingPaymentsAmount = 0;
  int _pendingPaymentCount = 0;
  bool _loadingPending = true;

  bool _loadingActivity = true;
  List<Map<String, dynamic>> _latestActivities = [];

  int? _asInt(dynamic v) => v == null ? null : int.tryParse(v.toString());

  @override
  void initState() {
    super.initState();
    _subscribeNotificationsRealtime();
    _loadOrAskDayung();
    _fetchUnreadNotifCount();
    _loadUserData();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final current = _scrollController.position.pixels;
      if (current >= maxScroll && _showNavBar) {
        setState(() => _showNavBar = false);
      } else if (current < maxScroll && !_showNavBar) {
        setState(() => _showNavBar = true);
      }
    });
  }

  Future<void> _fetchUnreadNotifCount() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    final unitId = _asInt(_selectedDayungUnitObj?['id']);

    if (uid == null || unitId == null) {
      if (mounted) setState(() => _unreadNotifCount = 0);
      return;
    }

    try {
      // Unread notifications for current unit only
      final notifRows = await sb
          .from('notifications')
          .select('id')
          .eq('recipient_id', uid)
          .eq('dayung_unit_id', unitId)
          .isFilter('read_at', null);

      final notifCount = (notifRows as List).length;

      // Unread announcements for current unit only
      final annRows = await sb
          .from('announcements')
          .select('id')
          .eq('dayung_unit_id', unitId);

      final annIds = (annRows as List)
          .map((r) => (r as Map)['id'])
          .where((v) => v != null)
          .toList();

      int annCount = 0;
      if (annIds.isNotEmpty) {
        final reads = await sb
            .from('announcement_reads')
            .select('announcement_id')
            .eq('user_id', uid)
            .inFilter('announcement_id', annIds);

        final readIds = Set.from(
          (reads as List).map((r) => (r as Map)['announcement_id']),
        );

        annCount = annIds.where((id) => !readIds.contains(id)).length;
      }

      if (mounted) setState(() => _unreadNotifCount = notifCount + annCount);
    } catch (_) {
      if (mounted) setState(() => _unreadNotifCount = 0);
    }
  }

  Future<bool> _isApprovedForUnit(int unitId) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      final rows = await supabase
          .from('applications')
          .select('id')
          .eq('user_id', uid)
          .eq('dayung_unit_id', unitId)
          .eq('status', 'approved')
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkUnreadNotifications() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    final data = await sb
        .from('notifications')
        .select('id, title, body, type, created_at')
        .eq('recipient_id', uid)
        .isFilter('read_at', null)
        .order('created_at', ascending: false)
        .limit(1);
    final list = List<Map<String, dynamic>>.from(data);
    if (list.isNotEmpty) {
      final notif = list.first;
      if (notif['type'] == 'membership_approved' ||
          notif['type'] == 'announcement') {
        _showAnnouncementDialog(notif);
      }
    }
  }

  void _showAnnouncementDialog(Map<String, dynamic> notif) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return Dialog(
          backgroundColor: const Color(0xFF8CA6C7), // blueish background
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Announcement',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w800,
                    fontSize: 28,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                const Icon(
                  Icons.notifications_active_rounded,
                  color: Colors.amber,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  notif['body']?.toString() ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () async {
                    final sb = Supabase.instance.client;
                    try {
                      await sb
                          .from('notifications')
                          .update({'read_at': DateTime.now().toIso8601String()})
                          .eq('id', notif['id']);
                    } catch (_) {}
                    if (!mounted) return;
                    Navigator.of(context).pop();
                    await _loadOrAskDayung();
                    await _fetchUnreadNotifCount();
                  },
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: Color(0xFFDDE3EA),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _refreshAll() async {
    await _loadUserData();
    await _reloadDayungFromPrefs();
    await _fetchAllStats();
    await _fetchUnreadNotifCount();
  }

  Future<void> _reloadDayungFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final unitJson = prefs.getString('selectedDayungUnit');

    if (unitJson == null) {
      setState(() {
        _selectedDayungUnit = 'Dayung Unit';
        _selectedDayungUnitObj = null;
        _unitBarangay = null;
        _unitCity = null;
        _dayungUnitId = null;
        _unreadNotifCount = 0;
      });
      return;
    }

    try {
      final decoded = jsonDecode(unitJson);
      if (decoded is! Map) throw 'bad_json';
      final unit = Map<String, dynamic>.from(decoded);
      final id = _asInt(unit['id']);

      if (id != null && await _isApprovedForUnit(id)) {
        setState(() {
          _selectedDayungUnit = (unit['name'] ?? 'Dayung Unit').toString();
          _selectedDayungUnitObj = unit;
          _unitBarangay = (unit['barangay'] ?? '').toString().trim().isEmpty
              ? null
              : unit['barangay'].toString();
          _unitCity = (unit['city'] ?? '').toString().trim().isEmpty
              ? null
              : unit['city'].toString();
          _dayungUnitId = id;
        });
        await context.read<DayungRoleProvider>().refreshRoles(id);
        await _fetchUnreadNotifCount();
      } else {
        await prefs.remove('selectedDayungUnit');
        setState(() {
          _selectedDayungUnit = 'Dayung Unit';
          _selectedDayungUnitObj = null;
          _unitBarangay = null;
          _unitCity = null;
          _dayungUnitId = null;
          _unreadNotifCount = 0;
        });
      }
    } catch (_) {
      await prefs.remove('selectedDayungUnit');
      setState(() {
        _selectedDayungUnit = 'Dayung Unit';
        _selectedDayungUnitObj = null;
        _unitBarangay = null;
        _unitCity = null;
        _dayungUnitId = null;
        _unreadNotifCount = 0;
      });
    }
  }

  Future<void> _loadOrAskDayung() async {
    final prefs = await SharedPreferences.getInstance();
    final unitJson = prefs.getString('selectedDayungUnit');
    if (unitJson != null) {
      try {
        final unit = jsonDecode(unitJson);
        final id = _asInt((unit as Map)['id']);
        if (id != null && await _isApprovedForUnit(id)) {
          setState(() {
            _selectedDayungUnit = (unit['name'] ?? 'Dayung Unit').toString();
            _selectedDayungUnitObj = Map<String, dynamic>.from(unit);
            _unitBarangay = (unit['barangay'] ?? '').toString().trim().isEmpty
                ? null
                : unit['barangay'].toString();
            _unitCity = (unit['city'] ?? '').toString().trim().isEmpty
                ? null
                : unit['city'].toString();
            _dayungUnitId = id;
          });
          await context.read<DayungRoleProvider>().refreshRoles(id);
          await _fetchUnreadNotifCount();
          await _fetchAllStats();
          await _subscribeAnnouncementsRealtime();
          return;
        } else {
          await prefs.setString('selectedDayungUnit', jsonEncode(unit));
          setState(() {
            _selectedDayungUnitObj = Map<String, dynamic>.from(unit);
            _selectedDayungUnit = (unit['name'] ?? 'Dayung Unit').toString();
            final idx = _asInt(unit['id']);
            _dayungUnitId = idx;
            _unitBarangay = (unit['barangay'] ?? '').toString().trim().isEmpty
                ? null
                : unit['barangay'].toString();
            _unitCity = (unit['city'] ?? '').toString().trim().isEmpty
                ? null
                : unit['city'].toString();
          });
          await context.read<DayungRoleProvider>().refreshRoles(
            _asInt(unit['id']),
          );
          await _fetchUnreadNotifCount();
          await _fetchAllStats();
          return;
        }
      } catch (_) {
        await prefs.remove('selectedDayungUnit');
      }
    }
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid != null) {
        final apps = await supabase
            .from('applications')
            .select('dayung_unit_id, approved_at')
            .eq('user_id', uid)
            .eq('status', 'approved')
            .order('approved_at', ascending: false)
            .limit(1);

        final list = (apps as List);
        if (list.isNotEmpty) {
          final dId = _asInt((list.first as Map)['dayung_unit_id']);
          if (dId != null) {
            final unit = await supabase
                .from('dayung_units')
                .select('id, name, barangay, city')
                .eq('id', dId)
                .maybeSingle();
            if (unit != null) {
              await prefs.setString('selectedDayungUnit', jsonEncode(unit));
              setState(() {
                _selectedDayungUnitObj = Map<String, dynamic>.from(unit);

                _selectedDayungUnit = (unit['name'] ?? 'Dayung Unit')
                    .toString();
                _unitBarangay =
                    (unit['barangay'] ?? '').toString().trim().isEmpty
                    ? null
                    : unit['barangay'].toString();
                _unitCity = (unit['city'] ?? '').toString().trim().isEmpty
                    ? null
                    : unit['city'].toString();
                _dayungUnitId = dId;
              });
              await _fetchUnreadNotifCount();
              await _fetchAllStats();
              return;
            }
          }
        }
      }
    } catch (_) {}

    await _navigateAndPickUnit();
  }

  Future<void> _fetchAllStats() async {
    await Future.wait([
      _fetchActiveMembers(),
      _fetchRecentDeaths(),
      _fetchPendingPayments(),
      _fetchRecentActivity(),
    ]);
  }

  void _subscribeNotificationsRealtime() {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;

    _notifChannel?.unsubscribe();
    _notifChannel = sb.channel('member_notifications_$uid');

    _notifChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: uid,
          ),
          callback: (payload) async {
            final row = payload.newRecord;
            final type = (row['type'] ?? '').toString();
            if (type == 'membership_approved' || type == 'announcement') {
              // Show top banner
              TopNotificationBanner.show(
                context,
                title: row['title']?.toString() ?? 'Notification',
                message: row['body']?.toString() ?? '',
                icon: type == 'announcement'
                    ? Icons.campaign
                    : Icons.notifications_active_rounded,
                onTap: () async {
                  // Mark this notification as read when tapped
                  try {
                    await sb
                        .from('notifications')
                        .update({'read_at': DateTime.now().toIso8601String()})
                        .eq('id', row['id']);
                  } catch (_) {}
                  await _fetchUnreadNotifCount();
                },
              );
              await _fetchUnreadNotifCount();
            }
          },
        )
        .subscribe();

    _checkUnreadNotifications();
  }

  Future<void> _subscribeAnnouncementsRealtime() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;

    // Clear existing channels
    for (final ch in _announcementChannels) {
      ch.unsubscribe();
    }
    _announcementChannels.clear();

    // Fetch all approved dayung units of this user
    final apps = await sb
        .from('applications')
        .select('dayung_unit_id')
        .eq('user_id', uid)
        .eq('status', 'approved');

    final unitIds = <int>{
      for (final r in (apps as List))
        if ((r as Map)['dayung_unit_id'] != null)
          int.parse(r['dayung_unit_id'].toString()),
    }.toList();

    // Subscribe to inserts on announcements per unit
    for (final id in unitIds) {
      final ch = sb.channel('announcements_unit_$id');
      ch
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'announcements',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'dayung_unit_id',
              value: id,
            ),
            callback: (payload) async {
              final row = payload.newRecord;
              // Pop top banner
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) {
                  return Dialog(
                    backgroundColor: const Color(0xFF8CA6C7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Announcement',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontWeight: FontWeight.w800,
                              fontSize: 28,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Icon(
                            Icons.campaign,
                            color: Colors.amber,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            (row['body'] ?? '').toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Montserrat',
                              fontWeight: FontWeight.w800,
                              fontSize: 24,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextButton(
                            onPressed: () async {
                              try {
                                await sb.from('announcement_reads').upsert([
                                  {
                                    'announcement_id': row['id'],
                                    'user_id': uid,
                                    'read_at': DateTime.now().toIso8601String(),
                                  },
                                ], onConflict: 'announcement_id,user_id');
                              } catch (_) {}
                              if (!mounted) return;
                              Navigator.of(context).pop();
                              await _fetchUnreadNotifCount();
                            },
                            child: const Text(
                              'Continue',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                                color: Color(0xFFDDE3EA),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
              await _fetchUnreadNotifCount();
            },
          )
          .subscribe();
      _announcementChannels.add(ch);
    }
  }

  Future<void> _fetchRecentActivity() async {
    setState(() => _loadingActivity = true);
    try {
      final supabase = Supabase.instance.client;
      final uid = supabase.auth.currentUser?.id;
      final dayungId = _asInt(_selectedDayungUnitObj?['id']);

      // Debug prints
      debugPrint('DEBUG: User ID: $uid, Dayung ID: $dayungId');

      if (uid == null || dayungId == null) {
        setState(() {
          _latestActivities = [];
          _loadingActivity = false;
        });
        return;
      }

      // 1. Get most recent paid contribution
      final contribResult = await supabase
          .from('payments')
          .select('amount, created_at, death_notice_id')
          .eq('user_id', uid)
          .eq('status', 'paid')
          .order('created_at', ascending: false)
          .limit(1);

      // Debug
      debugPrint('DEBUG: Contributions result: $contribResult');
      final recentContributions = contribResult as List? ?? [];

      // 2. Get most recent claim update
      final claimResult = await supabase
          .from('claims')
          .select('status, title, date_submitted')
          .eq('user_id', uid)
          .order('date_submitted', ascending: false)
          .limit(1);

      // Debug
      debugPrint('DEBUG: Claims result: $claimResult');
      final recentClaims = claimResult as List? ?? [];

      List<Map<String, dynamic>> activities = [];

      // Always add today's date
      activities.add({
        'icon': Icons.calendar_today,
        'color': kPrimary,
        'text': _formatTodayDate(),
        'date': DateTime.now().toIso8601String(),
        'type': 'date',
      });

      // ignore: unnecessary_type_check
      if (recentContributions.isNotEmpty && recentContributions is List) {
        final contrib = recentContributions[0];
        final amount = (contrib['amount'] is num)
            ? (contrib['amount'] as num).toDouble()
            : double.tryParse('${contrib['amount']}') ?? 0.0;

        activities.add({
          'icon': Icons.attach_money,
          'color': kAccent,
          'text': 'Paid ₱${amount.toStringAsFixed(0)} contribution',
          'date': contrib['created_at'],
          'type': 'payment',
        });
      }

      // ignore: unnecessary_type_check
      if (recentClaims.isNotEmpty && recentClaims is List) {
        final claim = recentClaims[0];
        final status = (claim['status'] ?? '').toString();

        String statusText = 'Claim ';
        IconData icon = Icons.circle;
        Color color = kAccent;

        switch (status.toLowerCase()) {
          case 'approved':
            statusText += 'approved';
            icon = Icons.check_circle;
            color = kAccent;
            break;
          case 'rejected':
            statusText += 'rejected';
            icon = Icons.cancel_outlined;
            color = Colors.red;
            break;
          case 'pending':
            statusText += 'pending';
            icon = Icons.pending_actions;
            color = Colors.orange;
            break;
          default:
            statusText += status;
        }

        activities.add({
          'icon': icon,
          'color': color,
          'text': statusText,
          'date': claim['date_submitted'],
          'type': 'claim',
        });
      }

      // Sort by date (most recent first)
      activities.sort((a, b) {
        final aDate =
            DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime.now();
        final bDate =
            DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime.now();
        return bDate.compareTo(aDate);
      });

      // Limit to 3 most recent activities
      activities = activities.take(3).toList();

      setState(() {
        _latestActivities = activities;
        _loadingActivity = false;
      });
    } catch (e) {
      setState(() {
        _latestActivities = [];
        _loadingActivity = false;
      });
    }
  }

  // Helper to format today's date
  String _formatTodayDate() {
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  Future<void> _refreshDashboard() async {
    await _loadUserData();
    await _reloadDayungFromPrefs();
    await _fetchAllStats();
  }

  Future<void> _loadUserData() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      _redirectToLogin();
      return;
    }
    try {
      final response = await supabase
          .from('users')
          .select('full_name, sex, profile_url')
          .eq('id', currentUser.id)
          .maybeSingle();

      final full = (response?['full_name'] as String?)?.trim();
      final sex = response?['sex'];
      setState(() {
        _user = currentUser;
        _fullName = '${_getTitle(sex)} ${full ?? 'Member'}'.trim();
        _profileUrl = (response?['profile_url'] as String?)?.trim();
        _loadingUser = false;
      });
    } catch (_) {
      setState(() {
        _loadingUser = false;
        _fullName = 'Member';
      });
    }
  }

  String _getTitle(dynamic sex) {
    final s = (sex ?? '').toString().toLowerCase().trim();
    if (s == 'male') return 'Mr.';
    if (s == 'female') return 'Mrs.';
    return '';
  }

  Future<void> _navigateAndPickUnit() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SelectDayungPage()),
    );
    if (result != null && result is Map) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selectedDayungUnit', jsonEncode(result));
      setState(() {
        _selectedDayungUnit = (result['name'] ?? 'Dayung Unit').toString();
        _selectedDayungUnitObj = Map<String, dynamic>.from(result);
        _unitBarangay = (result['barangay'] ?? '').toString().trim().isEmpty
            ? null
            : result['barangay'].toString();
        _unitCity = (result['city'] ?? '').toString().trim().isEmpty
            ? null
            : result['city'].toString();
        _dayungUnitId = _asInt(result['id']);
      });
      await context.read<DayungRoleProvider>().refreshRoles(
        _asInt(result['id']),
      );
      context.read<DayungUnitProvider>().setDayungUnit(result['name']);
      await _fetchUnreadNotifCount();
      await _fetchAllStats();
      await _subscribeAnnouncementsRealtime();
      return;
    }
  }

  Future<void> _fetchActiveMembers() async {
    setState(() => _loadingActiveMembers = true);
    try {
      final id = _asInt(_selectedDayungUnitObj?['id']);
      if (id == null) {
        _activeMembersCount = 0;
      } else {
        final result = await supabase.rpc(
          'get_active_members_count',
          params: {'p_dayung_unit_id': id},
        );
        _activeMembersCount = (result is int)
            ? result
            : int.tryParse('$result') ?? 0;
      }
    } catch (_) {
      _activeMembersCount = 0;
    } finally {
      if (mounted) setState(() => _loadingActiveMembers = false);
    }
  }

  Future<void> _fetchRecentDeaths() async {
    setState(() => _loadingCertificates = true);
    try {
      final unitId = _asInt(_selectedDayungUnitObj?['id']);
      if (unitId == null) {
        _recentCertificates = [];
      } else {
        final data = await supabase
            .from('death_notices')
            .select('id, name, date_of_death, dayung_unit_id')
            .eq('dayung_unit_id', unitId)
            .order('date_of_death', ascending: false)
            .limit(5);

        // Normalize to existing UI keys
        _recentCertificates = (data as List)
            .map(
              (e) => {
                'deceased_name': (e as Map)['name'],
                'date_of_death': e['date_of_death'],
                'dayung_unit_id': e['dayung_unit_id'],
              },
            )
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {
      _recentCertificates = [];
    } finally {
      if (mounted) setState(() => _loadingCertificates = false);
    }
  }

  Future<void> _fetchPendingPayments() async {
    setState(() => _loadingPending = true);
    try {
      final uid = supabase.auth.currentUser?.id;
      final dayungId = _asInt(_selectedDayungUnitObj?['id']);
      if (uid == null || dayungId == null) {
        _pendingPaymentsAmount = 0;
        _pendingPaymentCount = 0;
        _pendingPaymentsByDeathNotice = [];
      } else {
        final rows = await supabase
            .from('payments')
            .select('amount, status, user_id, death_notice_id')
            .eq('user_id', uid)
            .eq('dayung_unit_id', dayungId)
            .eq('status', 'pending');

        double total = 0;
        int cnt = 0;
        final noticeTotals = <int, double>{};
        final noticeCounts = <int, int>{};

        for (final r in rows as List) {
          final m = r as Map<String, dynamic>;
          final noticeId = m['death_notice_id'] as int?;
          final amt = (m['amount'] is num)
              ? (m['amount'] as num).toDouble()
              : 0.0;
          if (noticeId != null) {
            noticeTotals[noticeId] = (noticeTotals[noticeId] ?? 0) + amt;
            noticeCounts[noticeId] = (noticeCounts[noticeId] ?? 0) + 1;
          }
          total += amt;
          cnt++;
        }

        List<Map<String, dynamic>> notices = [];
        if (noticeTotals.isNotEmpty) {
          final ids = noticeTotals.keys.toList();
          final noticeRows = await supabase
              .from('death_notices')
              .select('id, name, date_of_death')
              .inFilter('id', ids);
          final noticeMap = {
            for (final n in (noticeRows as List))
              (n as Map)['id'] as int: Map<String, dynamic>.from(n),
          };
          for (final id in ids) {
            notices.add({
              'id': id,
              'name': noticeMap[id]?['name'] ?? 'Death Notice #$id',
              'date_of_death': noticeMap[id]?['date_of_death'],
              'amount': noticeTotals[id],
              'count': noticeCounts[id],
            });
          }
        }

        _pendingPaymentsAmount = total;
        _pendingPaymentCount = cnt;
        _pendingPaymentsByDeathNotice = notices;
      }
    } catch (_) {
      _pendingPaymentsAmount = 0;
      _pendingPaymentCount = 0;
      _pendingPaymentsByDeathNotice = [];
    } finally {
      if (mounted) setState(() => _loadingPending = false);
    }
  }

  void _redirectToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const Login()),
    );
  }

  @override
  void dispose() {
    _notifChannel?.unsubscribe();
    for (final ch in _announcementChannels) {
      ch.unsubscribe();
    }
    _announcementChannels.clear();
    _scrollController.dispose();
    super.dispose();
  }

  List<Widget> get _pages => [
    _buildHomePage(context),
    ContributionHistory(),
    ClaimsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wide = width > 700;
    return Scaffold(
      backgroundColor: kBg,
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        edgeOffset: 68,
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _topHeader(wide),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFE1E4E8),
                  ),
                  if (_currentIndex == 0) _greetingSection(),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: IndexedStack(
                        key: ValueKey(_currentIndex),
                        index: _currentIndex,
                        children: _pages,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _bottomNav(wide),
          ],
        ),
      ),
    );
  }

  Widget _bottomNav(bool wide) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 16,
      child: Center(
        child: IgnorePointer(
          ignoring: !_showNavBar,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: _showNavBar ? 1 : 0,
            child: Container(
              height: 86,
              margin: EdgeInsets.symmetric(horizontal: wide ? 170 : 20),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(44),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.08),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _navItem(Icons.home_rounded, "Home", 0),
                  _navItem(Icons.public, "Contributions", 1),
                  _navItem(Icons.description, "Claims", 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final selected = _currentIndex == index;
    return TextButton(
      onPressed: () => setState(() => _currentIndex = index),
      style: TextButton.styleFrom(
        foregroundColor: selected ? kPrimary : kNeutralText,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 30, color: selected ? kPrimary : kNeutralText),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontFamily: 'OpenSans',
              letterSpacing: .3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomePage(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool wide = width > 820;
    final dayungName = _selectedDayungUnitObj?['name'] ?? 'Dayung';
    final barangay = _selectedDayungUnitObj?['barangay'];
    final city = _selectedDayungUnitObj?['city'];
    final subtitle = (barangay != null)
        ? '$barangay${city != null ? ', $city' : ''}'
        : null;

    return RefreshIndicator(
      onRefresh: _refreshDashboard,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildCards(wide),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildNextPaymentCard(wide),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildRecentActivity(wide),
            ),
          ],
        ),
      ),
    );
  }

  Widget _greetingSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Maayung buntag, $_fullName!',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                fontFamily: 'Montserrat',
                color: kNeutralText,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCards(bool isWide) {
    final activeValue = _loadingActiveMembers
        ? '…'
        : _activeMembersCount.toString();

    String recentDeathsValue;
    if (_loadingCertificates) {
      recentDeathsValue = 'Loading…';
    } else if (_recentCertificates.isEmpty) {
      recentDeathsValue = 'None';
    } else {
      final names = _recentCertificates
          .map((e) => (e['deceased_name'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
      if (names.length <= 2) {
        recentDeathsValue = names.join('\n');
      } else {
        recentDeathsValue =
            '${names.take(2).join('\n')}\n+${names.length - 2} more';
      }
    }

    final pendingValue = _loadingPending
        ? '…'
        : '₱ ${_pendingPaymentsAmount.toStringAsFixed(0)}';
    final pendingSubtitle = _loadingPending
        ? ''
        : (_pendingPaymentCount > 0
              ? '$_pendingPaymentCount pending'
              : 'No pending');

    final cards = [
      _dashboardCard(
        color: const Color(0xFFD8EEFF),
        icon: Icons.groups,
        iconColor: Colors.blue[700],
        title: "Total Active\nMembers",
        value: activeValue,
      ),
      _dashboardCard(
        color: const Color(0xFFFFDAF6),
        icon: FontAwesomeIcons.dove,
        iconColor: Colors.purple[400],
        title: "Recent Deaths",
        value: recentDeathsValue,
        isDeathNotice: true,
        context: context,
        onTap: () {
          final id = _asInt(_selectedDayungUnitObj?['id']);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RecentDeathNotices(dayungUnitId: id),
            ),
          );
        },
      ),
      _dashboardCard(
        color: const Color(0xFFFEFBDC),
        icon: Icons.account_balance_wallet,
        iconColor: Colors.orange[700],
        title: "Pending\nPayments",
        value: pendingValue,
        subtitle: pendingSubtitle,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            children: cards
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: c,
                  ),
                )
                .toList(),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
            const SizedBox(width: 12),
            Expanded(child: cards[2]),
          ],
        );
      },
    );
  }

  Widget _dashboardCard({
    required Color color,
    required IconData icon,
    required Color? iconColor,
    required String title,
    required String value,
    String subtitle = "",
    double iconSize = 30,
    bool isDeathNotice = false,
    BuildContext? context,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 220,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: kPrimary.withOpacity(.12), // NEW ripple color
        highlightColor: kPrimary.withOpacity(.05),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade300, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: iconSize, color: iconColor),
              const SizedBox(height: 8),
              AutoSizeText(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: kNeutralText,
                  fontFamily: 'Montserrat',
                  height: 1.15,
                ),
                maxLines: 2,
                minFontSize: 11,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: isDeathNotice
                    ? _recentDeathsValueWidget(value, context)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AutoSizeText(
                            value,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 30,
                              color: kNeutralText,
                              fontFamily: 'Montserrat',
                            ),
                            maxLines: 2,
                            minFontSize: 12,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          if (subtitle.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: AutoSizeText(
                                subtitle,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: kSubtleText.withOpacity(.9),
                                  fontFamily: 'OpenSans',
                                ),
                                maxLines: 2,
                                minFontSize: 10,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentDeathsValueWidget(String raw, BuildContext? ctx) {
    if (raw == 'Loading…') {
      return const Center(
        child: SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: kPrimary, // unified color
          ),
        ),
      );
    }
    if (raw == 'None') {
      return const Center(
        child: Text(
          "None",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: 'Montserrat',
            color: kNeutralText,
          ),
        ),
      );
    }
    final lines = raw.split('\n');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ...lines
            .where((l) => !l.startsWith('+'))
            .map(
              (name) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(
                      FontAwesomeIcons.dove,
                      size: 14,
                      color: kNeutralText,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: kNeutralText,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        if (lines.any((l) => l.startsWith('+')))
          Text(
            lines.firstWhere((l) => l.startsWith('+')),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
              color: kSubtleText,
            ),
          ),
        TextButton(
          onPressed: () {
            final id = _asInt(_selectedDayungUnitObj?['id']);
            if (ctx != null) {
              Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) => RecentDeathNotices(dayungUnitId: id),
                ),
              );
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: kPrimary,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            "View All",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              fontFamily: 'Montserrat',
            ),
          ),
        ),
      ],
    );
  }

  Widget _topHeader(bool wide) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedDayungUnit, // same as Secretary header
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Montserrat',
                    color: kNeutralText,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                if (_unitBarangay != null || _unitCity != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: kSubtleText,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          [
                            if (_unitBarangay != null) _unitBarangay!,
                            if (_unitCity != null) _unitCity!,
                          ].join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'OpenSans',
                            color: kSubtleText,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          // Replace settings with Profile icon
          _iconBtn(
            tooltip: 'Profile',
            icon: Icons.person,
            color: kPrimary,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
              await _loadUserData(); // refresh name/avatar after returning
            },
          ),
          _iconBtn(
            tooltip: 'Notifications',
            icon: Icons.notifications,
            color: kWarn,
            badge: _unreadNotifCount > 0 ? '$_unreadNotifCount' : null,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationPage()),
              );
              await _fetchUnreadNotifCount();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNextPaymentCard(bool isWide) {
    final loading = _loadingPending;
    final amount = loading
        ? '…'
        : '₱ ${_pendingPaymentsAmount.toStringAsFixed(0)}';
    final dueDate = 'Due soon';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isWide ? 32 : 24),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: kPrimary.withOpacity(.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kPrimary.withOpacity(.25), width: 1.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Next Payment Due:',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: kPrimaryDark,
              fontFamily: 'Montserrat',
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: kPrimaryDark,
                  fontFamily: 'Montserrat',
                  letterSpacing: .5,
                ),
              ),
              const SizedBox(width: 10),
              if (!_loadingPending && _pendingPaymentsByDeathNotice.isNotEmpty)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: _pendingPaymentsByDeathNotice.map((p) {
                      final amt = (p['amount'] is num)
                          ? (p['amount'] as num).toDouble()
                          : 0.0;
                      final name = (p['name'] ?? '').toString();
                      final dod = p['date_of_death'];
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Text(
                                '₱${amt.toStringAsFixed(0)} for $name',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: kPrimaryDark,
                                  fontFamily: 'Montserrat',
                                ),
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                              ),
                            ),
                            if (dod != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                '($dod)',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: kSubtleText,
                                  fontFamily: 'OpenSans',
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            dueDate,
            style: TextStyle(
              color: kSubtleText.withOpacity(.9),
              fontSize: 14.5,
              fontFamily: 'OpenSans',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: loading
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PaymentMethodPage(
                            dayungUnitId: _asInt(_selectedDayungUnitObj?['id']),
                          ),
                        ),
                      ).then((_) {
                        _refreshDashboard();
                      });
                    },
              icon: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.payments_rounded),
              label: Text(
                loading ? 'Loading…' : 'Pay Now',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFamily: 'Montserrat',
                  letterSpacing: .3,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivity(bool isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Activity',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: kPrimaryDark,
            fontFamily: 'Montserrat',
            letterSpacing: .2,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 40 : 20,
            vertical: isWide ? 24 : 16,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300, width: 1.3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _loadingActivity
              ? const Center(child: CircularProgressIndicator())
              : _latestActivities.isEmpty ||
                    _latestActivities.length <=
                        1 // Updated condition
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'No recent activity',
                      style: TextStyle(
                        fontSize: 16,
                        color: kSubtleText,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (int i = 0; i < _latestActivities.length; i++) ...[
                      _ActivityRow(
                        icon: _latestActivities[i]['icon'],
                        color: _latestActivities[i]['color'],
                        text: _latestActivities[i]['text'],
                      ),
                      if (i < _latestActivities.length - 1)
                        const SizedBox(height: 12),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _ActivityRow({
    required this.icon,
    required this.color,
    required this.text,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
            ),
          ),
        ),
      ],
    );
  }
}

Widget _iconBtn({
  required IconData icon,
  required Color color,
  required VoidCallback onTap,
  String? tooltip,
  String? badge,
}) {
  return Semantics(
    button: true,
    label: tooltip,
    child: Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 28, color: color),
            ),
            if (badge != null)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: kDanger,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(.25),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
