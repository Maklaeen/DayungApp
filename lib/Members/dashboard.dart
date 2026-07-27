import 'dart:convert';
import 'package:capstone_app/Auth/logout.dart';
import 'package:capstone_app/Beneficiary/beneficiary.dart';
import 'package:capstone_app/Members/gcash_payment_page.dart';
import 'package:capstone_app/Members/memclaims.dart';
import 'package:capstone_app/Members/memcontributions.dart';
import 'package:capstone_app/Members/receipts.dart';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/pages/recentdeathnotices.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:capstone_app/Auth/login.dart';
import 'package:capstone_app/settings/profsettings.dart';
import 'package:capstone_app/utils/theme_surface.dart';
// import 'package:capstone_app/profile/dayung_profile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Color palette
const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);
const kPrimary = Color(0xFF0D47A1);
const kPrimaryDark = Color(0xFF083366);
const kWarn = Color(0xFFF57C00);
const kDanger = Color(0xFFC62828);
const kNeutralText = Color(0xFF1F2937);
const kSubtleText = Color(0xFF4B5563);

class MemberDashboardPage extends StatefulWidget {
  const MemberDashboardPage({super.key});
  @override
  State<MemberDashboardPage> createState() => _MemberDashboardPageState();
}

class _MemberDashboardPageState extends State<MemberDashboardPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final List<RealtimeChannel> _announcementChannels = [];
  int? _dayungUnitId;
  final ScrollController _scrollController = ScrollController();
  RealtimeChannel? _notifChannel;

  void _afterFrame(VoidCallback fn) {
    WidgetsBinding.instance.addPostFrameCallback((_) => fn());
  }

  Map<String, dynamic>? _selectedDayungUnitObj;

  String _fullName = 'Member';
  String _selectedDayungUnit = 'Dayung Unit';
  String? birthCertificateUrl;
  String? marriageCertificateUrl;

  bool _loadingActiveMembers = true;
  bool _handlingOverlay = false;
  bool _loadingPending = true;

  List<Map<String, dynamic>> _recentCertificates = [];
  final List<Map<String, dynamic>> _pendingPaymentsByDeathNotice = [];

  List<String> _pendingPaymentMessages = [];

  double _pendingPaymentsAmount = 0;

  int _unreadNotifCount = 0;
  int _activeMembersCount = 0;
  int? _asInt(dynamic v) => v == null ? null : int.tryParse(v.toString());
  int? _lastRoleUnitId;
  int _currentIndex = 0;
  bool _showNavBar = true;

  @override
  void initState() {
    super.initState();
    _reloadDayungFromPrefs();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients || !mounted) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final current = _scrollController.position.pixels;
      if (current >= maxScroll && _showNavBar) {
        setState(() => _showNavBar = false);
      } else if (current < maxScroll && !_showNavBar) {
        setState(() => _showNavBar = true);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provUnit = context.read<DayungUnitProvider>().currentUnitId;
      _maybeOnProviderUnitChanged(provUnit);
      _fetchUnreadNotifCount();
      _subscribeNotificationsRealtime();
      _subscribeAnnouncementsRealtime();
    });
    _load();
    _initLoad();
  }

  void _maybeOnProviderUnitChanged(int? newUnitId) async {
    if (newUnitId == null || newUnitId == _lastRoleUnitId) return;
    _lastRoleUnitId = newUnitId;
    setState(() => _dayungUnitId = newUnitId);
    await _refreshAll();
    await _fetchUnreadNotifCount();
    _subscribeNotificationsRealtime();
    await _subscribeAnnouncementsRealtime();
    await _load();
  }

  // Future<void> _load() async {
  //   await Future.wait([
  //     _fetchActiveMembers(),
  //     _fetchRecentDeaths(),
  //     _fetchPendingPayments(),
  //     _fetchRecentActivity(),
  //   ]);
  // }

  Future<List<int>> _managedDayungIds() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return <int>[];

    final rows = await supabase
        .from('dayung_units')
        .select('id')
        .eq('president_id', uid)
        .order('id');

    return List<Map<String, dynamic>>.from(
      rows,
    ).map((e) => e['id'] as int).toList();
  }

  Future<void> _load() async {
    try {
      final ids = await _managedDayungIds();
      if (ids.isEmpty) {
        return;
      }
      await Future.wait([
        _fetchActiveMembers(),
        _fetchRecentDeaths(),
        _fetchPendingPayments(),
      ]);
    } catch (e) {
      debugPrint('Failed to load member dashboard data: $e');
    }
  }

  Future<void> _initLoad() async {
    await _loadUserData();
    await Future.wait([
      _fetchActiveMembers(),
      _fetchRecentDeaths(),
      _fetchPendingPayments(),
    ]);
  }

  // Future<void> _bootstrapOnce() async {
  //   await _loadUserData();
  //   await _reloadDayungFromPrefs();
  //   if (!mounted) return;
  //   await _fetchUnreadNotifCount();
  //   await _fetchAllStats();
  //   _subscribeNotificationsRealtime();

  Future<void> _fetchUnreadNotifCount() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    final unitId = _dayungUnitId;
    if (uid == null) {
      if (!mounted) return;
      setState(() => _unreadNotifCount = 0);
      return;
    }

    try {
      final notifRows = await sb
          .from('notifications')
          .select('id')
          .eq('recipient_id', uid)
          .isFilter('read_at', null);
      final notifCount = (notifRows as List).length;

      int annCount = 0;
      if (unitId != null) {
        final annRows = await sb
            .from('announcements')
            .select('id')
            .eq('dayung_unit_id', unitId);
        final annIds = (annRows as List).map((r) => (r as Map)['id']).toList();

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
      }

      if (!mounted) return;
      setState(() => _unreadNotifCount = notifCount + annCount);
    } catch (_) {
      if (!mounted) return;
      setState(() => _unreadNotifCount = 0);
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationPage()),
    );
    await _fetchUnreadNotifCount();
  }

  void _showAnnouncementDialog(Map<String, dynamic> notif) {
    if (!mounted || _handlingOverlay) return;
    _handlingOverlay = true;
    _afterFrame(() {
      if (!mounted) return;
      showDialog<void>(
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
                            .update({
                              'read_at': DateTime.now().toIso8601String(),
                            })
                            .eq('id', notif['id']);
                      } catch (_) {}
                      if (!mounted) return;
                      Navigator.of(context).pop();
                      _handlingOverlay = false;
                      await _fetchUnreadNotifCount(); // light update only
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
    });
  }

  Future<void> _refreshAll() async {
    await _loadUserData();
    await _reloadDayungFromPrefs();
    await _fetchAllStats();
    await _fetchUnreadNotifCount();
  }

  Future<void> _reloadDayungFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final unitJson = prefs.getString('selectedDayungUnit');
      if (unitJson == null) {
        debugPrint('No selectedDayungUnit in prefs.');
        return;
      }
      final map = Map<String, dynamic>.from(jsonDecode(unitJson));
      final rawId = map['id'];
      final id = rawId is int ? rawId : int.tryParse('$rawId');
      if (id != null) {
        debugPrint('Loaded Dayung unit from prefs: id=$id');
        setState(() {
          _selectedDayungUnitObj = map;
          _selectedDayungUnit = (map['name'] ?? 'Dayung Unit').toString();
          _dayungUnitId = id;
        });
      }
    } catch (e) {
      debugPrint('Failed to reload Dayung from prefs: $e');
    }
  }

  // Future<void> _loadOrAskDayung() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   final unitJson = prefs.getString('selectedDayungUnit');
  //   if (unitJson != null) {
  //     try {
  //       final unit = jsonDecode(unitJson);
  //       final id = _asInt((unit as Map)['id']);
  //       if (id != null && await _isApprovedForUnit(id)) {
  //         if (!mounted) return;
  //         setState(() {
  //           _selectedDayungUnit = (unit['name'] ?? 'Dayung Unit').toString();
  //           _selectedDayungUnitObj = Map<String, dynamic>.from(unit);
  //           _unitBarangay = (unit['barangay'] ?? '').toString().trim().isEmpty
  //               ? null
  //               : unit['barangay'].toString();
  //           _unitCity = (unit['city'] ?? '').toString().trim().isEmpty
  //               ? null
  //               : unit['city'].toString();
  //           _dayungUnitId = id;
  //         });
  //         return;
  //       } else {
  //         await prefs.setString('selectedDayungUnit', jsonEncode(unit));
  //         if (!mounted) return;
  //         setState(() {
  //           _selectedDayungUnitObj = Map<String, dynamic>.from(unit);
  //           _selectedDayungUnit = (unit['name'] ?? 'Dayung Unit').toString();
  //           _dayungUnitId = _asInt(unit['id']);
  //           _unitBarangay = (unit['barangay'] ?? '').toString().trim().isEmpty
  //               ? null
  //               : unit['barangay'].toString();
  //           _unitCity = (unit['city'] ?? '').toString().trim().isEmpty
  //               ? null
  //               : unit['city'].toString();
  //         });
  //         return;
  //       }
  //     } catch (_) {
  //       await prefs.remove('selectedDayungUnit');
  //     }
  //   }
  //   try {
  //     final uid = supabase.auth.currentUser?.id;
  //     if (uid != null) {
  //       final apps = await supabase
  //           .from('applications')
  //           .select('dayung_unit_id, approved_at')
  //           .eq('user_id', uid)
  //           .eq('status', 'approved')
  //           .order('approved_at', ascending: false)
  //           .limit(1);

  //       final list = (apps as List);
  //       if (list.isNotEmpty) {
  //         final dId = _asInt((list.first as Map)['dayung_unit_id']);
  //         if (dId != null) {
  //           final unit = await supabase
  //               .from('dayung_units')
  //               .select('id, name, barangay, city')
  //               .eq('id', dId)
  //               .maybeSingle();
  //           if (unit != null) {
  //             await prefs.setString('selectedDayungUnit', jsonEncode(unit));
  //             if (!mounted) return;
  //             setState(() {
  //               _selectedDayungUnitObj = Map<String, dynamic>.from(unit);
  //               _selectedDayungUnit = (unit['name'] ?? 'Dayung Unit')
  //                   .toString();
  //               _unitBarangay =
  //                   (unit['barangay'] ?? '').toString().trim().isEmpty
  //                   ? null
  //                   : unit['barangay'].toString();
  //               _unitCity = (unit['city'] ?? '').toString().trim().isEmpty
  //                   ? null
  //                   : unit['city'].toString();
  //               _dayungUnitId = dId;
  //             });
  //             return;
  //           }
  //         }
  //       }
  //     }
  //   } catch (_) {}
  //   if (!mounted) return;
  //   await _navigateAndPickUnit();
  // }

  Future<void> _fetchAllStats() async {
    await Future.wait([
      _fetchActiveMembers(),
      _fetchRecentDeaths(),
      _fetchPendingPayments(),
    ]);
  }

  void _subscribeNotificationsRealtime() {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;

    _notifChannel?.unsubscribe();
    _notifChannel = sb.channel('member_dashboard_notifications_$uid');

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
          callback: (payload) {
            final notif = payload.newRecord;
            if (notif['type'] == 'membership_approved' ||
                notif['type'] == 'announcement') {
              _showAnnouncementDialog(Map<String, dynamic>.from(notif));
            }
            _fetchUnreadNotifCount();
          },
        )
        .subscribe();
  }

  Future<void> _subscribeAnnouncementsRealtime() async {
    for (final ch in _announcementChannels) {
      ch.unsubscribe();
    }
    _announcementChannels.clear();

    final unitId = _dayungUnitId;
    if (unitId == null) return;

    final ch = supabase.channel('member_dashboard_announcements_$unitId');
    ch
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'announcements',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'dayung_unit_id',
            value: unitId,
          ),
          callback: (_) {
            _fetchUnreadNotifCount();
          },
        )
        .subscribe();
    _announcementChannels.add(ch);
  }

  Future<void> _loadUserData() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      _afterFrame(() {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const Login()),
          );
        }
      });
      return;
    }
    try {
      final response = await supabase
          .from('users')
          .select('full_name, sex, profile_url')
          .eq('id', currentUser.id)
          .maybeSingle();

      if (!mounted) return;
      final full = (response?['full_name'] as String?)?.trim();
      final sex = response?['sex'];
      setState(() {
        _fullName = '${_getTitle(sex)} ${full ?? 'Member'}'.trim();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
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

  Future<void> _fetchActiveMembers() async {
    if (!mounted) return;
    setState(() => _loadingActiveMembers = true);
    try {
      final id = _dayungUnitId;
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
      if (mounted) {
        setState(() => _loadingActiveMembers = false);
      }
    }
  }

  Future<void> _fetchRecentDeaths() async {
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
    }
  }

  Future<void> _fetchPendingPayments() async {
    if (!mounted) return;
    setState(() => _loadingPending = true);
    try {
      final uid = supabase.auth.currentUser?.id;
      final unitId = _asInt(_selectedDayungUnitObj?['id']);
      if (uid == null || unitId == null) {
        _pendingPaymentsAmount = 0;
        _pendingPaymentMessages = [];
        return;
      }

      // Use the correct field name: userdeceased
      final unpaidRows = await supabase
          .from('payments')
          .select('amount, userdeceased, message')
          .eq('user_id', uid)
          .eq('dayung_unit_id', unitId)
          .eq('status', 'unpaid');

      final paidRows = await supabase
          .from('payments')
          .select('amount, userdeceased')
          .eq('user_id', uid)
          .eq('dayung_unit_id', unitId)
          .eq('status', 'paid');

      final Map<dynamic, double> unpaidMap = {};
      for (final row in unpaidRows) {
        final id = row['userdeceased'];
        final amt = (row['amount'] is num)
            ? (row['amount'] as num).toDouble()
            : double.tryParse('${row['amount']}') ?? 0.0;
        unpaidMap[id] = (unpaidMap[id] ?? 0) + amt;
      }

      for (final row in paidRows) {
        final id = row['userdeceased'];
        final amt = (row['amount'] is num)
            ? (row['amount'] as num).toDouble()
            : double.tryParse('${row['amount']}') ?? 0.0;
        unpaidMap[id] = (unpaidMap[id] ?? 0) - amt;
      }

      double totalDue = unpaidMap.values
          .where((v) => v > 0)
          .fold(0.0, (a, b) => a + b);

      _pendingPaymentsAmount = totalDue;
      _pendingPaymentMessages = [
        for (final row in unpaidRows)
          if ((row['message'] ?? '').toString().trim().isNotEmpty)
            row['message'].toString(),
      ];
    } catch (e) {
      _pendingPaymentsAmount = 0;
      _pendingPaymentMessages = [];
    } finally {
      if (mounted) {
        setState(() => _loadingPending = false);
      }
    }
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

  Widget _buildContentArea(bool wide) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: dayungSurface(context),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [dayungTopShadow(context)],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          child: RefreshIndicator(
            onRefresh: _load,
            edgeOffset: 68,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: IndexedStack(
                key: ValueKey(_currentIndex),
                index: _currentIndex,
                children: _pages,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? tooltip,
    String? badge,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Icon(icon, color: color, size: 20),
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  fontFamily: 'OpenSans',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHomePage(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      edgeOffset: 68,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _overviewSection(),
            const SizedBox(height: 24),
            _buildNextPaymentCard(
              false,
            ), // Keep your Next Payment Due card here
            const SizedBox(height: 24),
            _modernActionCards(),
            const SizedBox(height: 24),
            _modernRecentActivity(),
            const SizedBox(height: 24),
            _modernQuickActions(),
            const SizedBox(height: 100), // Space for bottom nav
          ],
        ),
      ),
    );
  }

  Widget _buildModernHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        children: [
          Row(
            children: [
              Builder(
                builder: (context) => Container(
                  padding: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: kPrimary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.menu_rounded, color: Colors.white),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedDayungUnit,
                      maxLines: 1,
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              _iconBtn(
                icon: Icons.notifications_active_rounded,
                color: kWarn,
                tooltip: 'Notifications',
                onTap: _openNotifications,
                badge: _unreadNotifCount > 0 ? '$_unreadNotifCount' : null,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Good Morning!\n$_fullName',
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              // GestureDetector(
              //   onTap: () {
              //     Navigator.push(
              //       context,
              //       MaterialPageRoute(builder: (_) => const ProfilePage()),
              //     );
              //   },
              //   child: Container(
              //     padding: const EdgeInsets.all(4),
              //     decoration: BoxDecoration(
              //       color: Colors.white.withOpacity(0.2),
              //       borderRadius: BorderRadius.circular(32),
              //       boxShadow: [
              //         BoxShadow(
              //           color: Colors.black.withOpacity(0.1),
              //           blurRadius: 8,
              //           offset: const Offset(0, 2),
              //         ),
              //       ],
              //     ),
              //     child: const CircleAvatar(
              //       radius: 28,
              //       backgroundColor: Colors.white,
              //       child: Icon(
              //         Icons.person,
              //         size: 34,
              //         color: Color(0xFF1E40AF),
              //       ),
              //     ),
              //   ),
              // ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _overviewSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: dayungSectionCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overview',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E40AF),
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 180,
                    child: _modernStatCard(
                      icon: Icons.groups_rounded,
                      title: 'Active Members',
                      value: _loadingActiveMembers
                          ? '—'
                          : _activeMembersCount.toString(),
                      color: const Color(0xFF3B82F6),
                      bgColor: const Color(0xFFEFF6FF),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 180,
                  child: InkWell(
                    onTap: () {
                      final id = _asInt(_selectedDayungUnitObj?['id']);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RecentDeathNotices(dayungUnitId: id),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: _recentDeathsCard(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() => _currentIndex = 1);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 180,
                    child: _modernStatCard(
                      icon: Icons.account_balance_wallet_rounded,
                      title: 'Pending Amount',
                      value: _loadingPending
                          ? '—'
                          : '₱${_pendingPaymentsAmount.toStringAsFixed(0)}',
                      color: const Color(0xFFF59E0B),
                      bgColor: const Color(0xFFFEF3C7),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Stat card
  Widget _modernStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: dayungAccentCardDecoration(
        context,
        accent: color,
        lightAlpha: 0.10,
        darkAlpha: 0.16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // Recent deaths card
  Widget _recentDeathsCard() {
    final names = _recentCertificates
        .map((e) => (e['deceased_name'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toList();
    final display = names.take(2).toList();
    // final extra = names.length - display.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: dayungAccentCardDecoration(
        context,
        accent: const Color(0xFFEC4899),
        lightAlpha: 0.08,
        darkAlpha: 0.14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEC4899).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.family_restroom_rounded,
              color: Color(0xFFEC4899),
              size: 20,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Recent Deaths',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFFEC4899),
            ),
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: display
                .map(
                  (name) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF9F1239),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  // Quick Actions
  Widget _modernActionCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E40AF),
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 8),
        _modernActionCard(
          icon: Icons.receipt_long_rounded,
          title: 'View Receipts',
          subtitle: 'See your payment receipts',
          color: const Color(0xFF10B981),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReceiptsPage()),
            );
          },
        ),
        const SizedBox(height: 8),
        _modernActionCard(
          icon: Icons.qr_code_rounded,
          title: 'Pay via GCash',
          subtitle: 'Quick GCash payment',
          color: const Color(0xFF3B82F6),
          onTap: () {
            final user = Supabase.instance.client.auth.currentUser;
            if (user != null) {
              // Print user info to debug console
              debugPrint(
                'Pay via GCash clicked by user: ${user.id} (${user.email})',
              );
            } else {
              debugPrint('Pay via GCash clicked by unknown user');
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GCashPaymentPage(
                  dayungUnitId: _asInt(_selectedDayungUnitObj?['id']),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _modernActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isCompact = MediaQuery.of(context).size.width < 360;
    final titleFontSize = isCompact ? 14.0 : 16.0;
    final subtitleFontSize = isCompact ? 11.0 : 12.0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: dayungSurface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dayungBorder(context)),
        boxShadow: [dayungElevatedShadow(context)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w700,
                          color: dayungTextColor(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: subtitleFontSize,
                          color: dayungSubtextColor(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: color.withValues(alpha: 0.6),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Recent Activity
  Widget _modernRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Activity',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: dayungSectionCardDecoration(context, radius: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: dayungAccentSurface(context, kPrimaryDark),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: kPrimaryDark.withValues(
                      alpha: dayungIsDark(context) ? 0.34 : 0.18,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.notifications_active_rounded,
                      color: kPrimaryDark,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _pendingPaymentMessages.isEmpty
                            ? 'No payment reminders right now.'
                            : '${_pendingPaymentMessages.length} reminder(s) need your attention.',
                        style: const TextStyle(
                          color: kText,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          fontFamily: 'OpenSans',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_pendingPaymentMessages.isEmpty)
                const Text(
                  'No recent activity',
                  style: TextStyle(
                    color: kSubText,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    fontFamily: 'OpenSans',
                  ),
                )
              else
                ..._pendingPaymentMessages
                    .take(3)
                    .map(
                      (msg) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(top: 6),
                              decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                msg,
                                style: const TextStyle(
                                  color: kText,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  fontFamily: 'OpenSans',
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _modernQuickActions() {
    final id = _asInt(_selectedDayungUnitObj?['id']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Access',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(height: 16),
        _modernActionCard(
          icon: Icons.receipt_long_rounded,
          title: 'Receipts',
          subtitle: 'Open your payment history and official receipts',
          color: const Color(0xFF10B981),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReceiptsPage()),
            );
          },
        ),
        const SizedBox(height: 8),
        _modernActionCard(
          icon: Icons.qr_code_rounded,
          title: 'GCash Payment',
          subtitle: 'Continue payment using the unit QR page',
          color: const Color(0xFF3B82F6),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GCashPaymentPage(dayungUnitId: id),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        _modernActionCard(
          icon: Icons.family_restroom_rounded,
          title: 'Recent Death Notices',
          subtitle: 'Check the latest notices that affect contributions',
          color: const Color(0xFFF59E0B),
          onTap: () {
            if (id == null) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RecentDeathNotices(dayungUnitId: id),
              ),
            );
          },
        ),
      ],
    );
  }
  //               icon: Icons.info_outline_rounded,
  //               title: "Contribution Tips",
  //               color: const Color(0xFF3B82F6),
  //               onTap: () {
  //                 // Implement tips action
  //               },
  //             ),
  //           ),
  //           const SizedBox(width: 12),
  //           Expanded(
  //             child: _modernQuickActionCard(
  //               icon: Icons.analytics_rounded,
  //               title: "View Reports",
  //               color: const Color(0xFFF59E0B),
  //               onTap: () {
  //                 // Implement reports action
  //               },
  //             ),
  //           ),
  //         ],
  //       ),
  //     ],
  //   );
  // }

  List<Widget> get _pages => [
    _buildHomePage(context),
    _dayungUnitId == null
        ? const Center(child: Text('Select a Dayung unit first'))
        : MembersContributionHistory(dayungUnitId: _dayungUnitId!),
    _dayungUnitId == null
        ? const Center(child: Text('Select a Dayung unit first'))
        : MembersClaimsPage(dayungUnitId: _dayungUnitId!),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provUnit = context.watch<DayungUnitProvider>().currentUnitId;
    if (provUnit != _lastRoleUnitId) {
      _lastRoleUnitId = provUnit;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _maybeOnProviderUnitChanged(provUnit);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // final provUnit = context.watch<DayungUnitProvider>().currentUnitId;
    // if (provUnit != _lastRoleUnitId) {
    //   WidgetsBinding.instance.addPostFrameCallback((_) {
    //     _maybeOnProviderUnitChanged(provUnit);
    //   });
    // }

    final width = MediaQuery.of(context).size.width;
    final bool wide = width > 820;

    return Container(
      decoration: BoxDecoration(gradient: dayungDashboardGradient(context)),
      child: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [_buildModernHeader(), _buildContentArea(wide)],
            ),
          ),
          _buildFloatingNavBar(wide),
        ],
      ),
    );
  }

  // Add this method for the floating nav bar, matching Treasurer style
  Widget _buildFloatingNavBar(bool wide) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 20,
      child: Center(
        child: IgnorePointer(
          ignoring: !_showNavBar,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: _showNavBar ? 1 : 0,
            child: Container(
              height: 80,
              margin: EdgeInsets.symmetric(horizontal: wide ? 200 : 20),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: dayungSurface(context),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: dayungBorder(context)),
                boxShadow: [dayungElevatedShadow(context)],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNavItem(Icons.dashboard_rounded, "Home", 0),
                  _buildNavItem(Icons.trending_up_rounded, "Contributions", 1),
                  _buildNavItem(Icons.assignment_rounded, "Claims", 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final selected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF1E40AF).withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected
                  ? const Color(0xFF1E40AF)
                  : const Color(0xFF6B7280),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? const Color(0xFF1E40AF)
                    : const Color(0xFF6B7280),
                height: 1.0,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
        color: dayungAccentSurface(
          context,
          kPrimary,
          lightAlpha: 0.08,
          darkAlpha: 0.14,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: kPrimary.withValues(
            alpha: dayungIsDark(context) ? 0.36 : 0.25,
          ),
          width: 1.6,
        ),
        boxShadow: [dayungElevatedShadow(context)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Next Payment Due:',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: dayungTextColor(context),
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
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: dayungTextColor(context),
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
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: dayungTextColor(context),
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
                                style: TextStyle(
                                  fontSize: 13,
                                  color: dayungSubtextColor(context),
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
              color: dayungSubtextColor(context),
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
                      final id = _asInt(_selectedDayungUnitObj?['id']);
                      if (id == null) {
                        // Show an error, fallback, or prevent navigation
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GCashPaymentPage(dayungUnitId: id),
                        ),
                      );
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
}

class AmountDueWidget extends StatefulWidget {
  final String userId;
  final int unitId; // <-- Change to int
  const AmountDueWidget({
    required this.userId,
    required this.unitId,
    super.key,
  });

  @override
  State<AmountDueWidget> createState() => _AmountDueWidgetState();
}

class _AmountDueWidgetState extends State<AmountDueWidget> {
  double? amountDue;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchAmountDue();
  }

  Future<void> fetchAmountDue() async {
    final response = await Supabase.instance.client
        .from('payments')
        .select('amount')
        .eq('user_id', widget.userId)
        .eq('dayung_unit_id', widget.unitId)
        .eq('status', 'unpaid') // or 'pending', adjust as needed
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    setState(() {
      amountDue = response?['amount']?.toDouble();
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const CircularProgressIndicator();
    return Text('Amount Due: ₱${amountDue ?? 0}');
  }
}
