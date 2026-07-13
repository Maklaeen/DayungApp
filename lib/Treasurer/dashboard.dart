import 'dart:convert';
import 'package:capstone_app/Auth/logout.dart';
import 'package:capstone_app/Beneficiary/beneficiary.dart';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/Treasurer/collected.dart';
import 'package:capstone_app/Treasurer/manage_fund.dart';
import 'package:capstone_app/Treasurer/treasclaims.dart';
import 'package:capstone_app/Treasurer/treascontributions.dart';
import 'package:capstone_app/Treasurer/treasurer_payment_page.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/Collector/gcash_qr_page.dart';
import 'package:capstone_app/pages/recentdeathnotices.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:capstone_app/settings/profsettings.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/foundation.dart';

// Palette
const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kWarn = Color(0xFFF57C00);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);
const kSubText = Color(0xFF4B5563);
const kText = Color(0xFF1F2937);

class TreasurerDashboardPage extends StatefulWidget {
  const TreasurerDashboardPage({super.key});

  @override
  State<TreasurerDashboardPage> createState() => _TreasurerDashboardPageState();
}

class _TreasurerDashboardPageState extends State<TreasurerDashboardPage> {
    Future<List<Map<String, dynamic>>> _fetchApprovedClaims(List<int> dayungIds) async {
      try {
        final rows = await sb
            .from('claims')
            .select()
            .inFilter('dayung_unit_id', dayungIds)
            .eq('status', 'Approved');
        return List<Map<String, dynamic>>.from(rows);
      } catch (_) {
        return [];
      }
    }
  final sb = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();

  String _fullName = 'Treasurer';

  Future<List<Map<String, dynamic>>>? _deathNoticesFutureCached;
  Future<Map<String, Map<String, dynamic>>>? _paymentStatsFutureCached;
  List<int> _lastNoticeIds = const [];
  int? _lastStatsDayungId;

  String _dayungLabel = 'Dayung';
  int _tab = 0;
  bool _showNavBar = true;
  int? _dayungUnitId;
  int? _lastRoleUnitId;
  bool _loading = true;
  int _activeMembers = 0;
  int _unreadNotifCount = 0;
  double _pendingAmount = 0;
  DateTime? _lastRefreshTime;
  List<String> _recentDeaths = [];
  String _noticeFilter = 'members';

  @override
  void initState() {
    super.initState();
    // Prime the notices future immediately so the first build doesn't recreate it
    _deathNoticesFutureCached = _deathNoticesFuture();
    _init();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provUnit = context.read<DayungRoleProvider>().unitId;
      _maybeOnProviderUnitChanged(provUnit);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeOnProviderUnitChanged(int? newUnitId) {
    if (newUnitId == null || newUnitId == _lastRoleUnitId) return;
    _lastRoleUnitId = newUnitId;
    setState(() => _dayungUnitId = newUnitId);
    _deathNoticesFutureCached = _deathNoticesFuture(); // reset caches
    _paymentStatsFutureCached = null;
    _loadDayungFromPrefs(); // refresh label
    _fetchAll();
  }

  Future<void> _init() async {
    await _loadUserData();
    await _ensureDayungId();
    await _fetchAll();
  }

  Future<void> _loadUserData() async {
    final currentUser = sb.auth.currentUser;
    if (currentUser == null) return;
    try {
      final res = await sb
          .from('users')
          .select('full_name, profile_url')
          .eq('id', currentUser.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _fullName = ((res?['full_name'] ?? 'Treasurer') as String).trim();
      });
    } catch (_) {}
  }

  void _ensureStatsFuture(List<int> noticeIds, int dayungUnitId) {
    if (_paymentStatsFutureCached != null &&
        listEquals(_lastNoticeIds, noticeIds) &&
        _lastStatsDayungId == dayungUnitId) {
      return;
    }
    _lastNoticeIds = List<int>.from(noticeIds);
    _lastStatsDayungId = dayungUnitId;
    _paymentStatsFutureCached = _paymentStatsByNotice(noticeIds, dayungUnitId);
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? fallback;
  }

  double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? fallback;
  }

  Future<List<int>> _selectedDayungIds() async {
    await _ensureDayungId();
    if (_dayungUnitId != null) return [_dayungUnitId!];
    return const [];
  }
  

  Future<List<Map<String, dynamic>>> _deathNoticesFuture() async {
    final ids = await _selectedDayungIds();
    return _fetchDeathNotices(ids);
  }

  

Future<List<Map<String, dynamic>>> _fetchDeathNotices(List<int> dayungIds) async {
  try {
    final ids = dayungIds.isNotEmpty
        ? dayungIds
        : (_dayungUnitId != null ? [_dayungUnitId!] : const <int>[]);
    if (ids.isEmpty) return [];

    final dnDirect = await sb
        .from('claims')
        .select(
          'id, PassedAway, date_of_death, dayung_unit_id, user_id, beneficiary_id, deceased_type, paid_count, unpaid_count, total_paid_amount, total_payment_amount, status, title, description, death_certificate_url, amount'
        )
        .inFilter('dayung_unit_id', ids)
        .eq('status', 'Approved')
        .order('date_of_death', ascending: false);

    final direct = List<Map<String, dynamic>>.from(dnDirect);

    // Collect user_ids to fetch names for members
    final userIds = direct
        .where((m) => (m['deceased_type'] ?? '') != 'beneficiary')
        .map((m) => m['user_id'])
        .where((id) => id != null)
        .toSet();

    Map<String, String> userNames = {};
    if (userIds.isNotEmpty) {
      final users = await sb
          .from('users')
          .select('id, full_name')
          .inFilter('id', userIds.toList());
      for (final u in List<Map<String, dynamic>>.from(users)) {
        userNames[u['id']] = u['full_name'] ?? '';
      }
    }

    for (final m in direct) {
      final dtype = (m['deceased_type'] ?? '').toString();
      if (dtype.isEmpty) {
        m['deceased_type'] = (m['beneficiary_id'] != null) ? 'beneficiary' : 'member';
      }
      if (m['deceased_type'] == 'beneficiary') {
        m['name'] = m['PassedAway'] ?? 'Beneficiary';
      } else {
        m['name'] = userNames[m['user_id']] ?? 'Member';
      }
    }

    return direct;
  } catch (e) {
    print('DEBUG: error in _fetchDeathNotices: $e');
    return [];
  }
}
  Future<void> _loadDayungFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    String label = prefs.getString('selectedDayungUnit') ?? 'Dayung';
    String? jsonFull = prefs.getString('selectedDayungUnitData');
    Map<String, dynamic>? parsed;

    try {
      if (jsonFull != null) {
        parsed = jsonDecode(jsonFull);
      }
    } catch (_) {}
    if (parsed == null &&
        label.trim().startsWith('{') &&
        label.contains('"name"')) {
      try {
        parsed = jsonDecode(label);
      } catch (_) {}
    }
    if (parsed != null) {
      if ((parsed['name'] ?? '').toString().isNotEmpty) {
        label = parsed['name'];
      }
      final id = parsed['id'];
      if (id != null) _dayungUnitId = int.tryParse(id.toString());
    }
    setState(() => _dayungLabel = label);
  }

  Future<void> _fetchAll() async {
    // Prevent refreshing more than once every 2 seconds
    final now = DateTime.now();
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!).inSeconds < 2) {
      return;
    }
    _lastRefreshTime = now;
    setState(() => _loading = true);
    try {
      final selected = await _selectedDayungIds(); // only current dayung

  
      _deathNoticesFutureCached = _deathNoticesFuture();
      // Reset stats cache; it will be re-initialized lazily when notices arrive
      _paymentStatsFutureCached = null;
      _lastNoticeIds = const [];
      _lastStatsDayungId = _dayungUnitId;

      await Future.wait([
        _fetchActiveMembers(selected),
        _fetchPendingPayments(selected),
        _fetchRecentDeaths(selected),
        _fetchUnreadNotifCount(selected),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchUnreadNotifCount(List<int> ids) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _unreadNotifCount = 0);
      return;
    }

    try {
      final notifRows = await sb
          .from('notifications')
          .select('id')
          .eq('recipient_id', uid)
          .isFilter('read_at', null);
      int unread = (notifRows as List).length;

      if (ids.isNotEmpty) {
        final annRows = await sb
            .from('announcements')
            .select('id')
            .inFilter('dayung_unit_id', ids);
        final annIds = (annRows as List)
            .map((row) => (row as Map)['id'])
            .whereType<int>()
            .toList();

        if (annIds.isNotEmpty) {
          final reads = await sb
              .from('announcement_reads')
              .select('announcement_id')
              .eq('user_id', uid)
              .inFilter('announcement_id', annIds);
          final readIds = Set<int>.from(
            (reads as List).map(
              (row) => (row as Map)['announcement_id'] as int,
            ),
          );
          unread += annIds.where((id) => !readIds.contains(id)).length;
        }
      }

      if (mounted) {
        setState(() => _unreadNotifCount = unread);
      }
    } catch (_) {
      if (mounted) setState(() => _unreadNotifCount = 0);
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationPage()),
    );
    await _fetchUnreadNotifCount(await _selectedDayungIds());
  }

  Future<void> _fetchActiveMembers(List<int> ids) async {
    try {
      if (ids.isEmpty) {
        _activeMembers = 0;
        return;
      }
      final apps = await sb
          .from('applications')
          .select('user_id')
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'approved');
      final usersSet = <String>{};
      for (final r in List<Map<String, dynamic>>.from(apps)) {
        final id = (r['user_id'] ?? '').toString();
        if (id.isNotEmpty) usersSet.add(id);
      }
      if (usersSet.isEmpty) {
        _activeMembers = 0;
        return;
      }
      final users = await sb
          .from('users')
          .select('id,is_deceased')
          .inFilter('id', usersSet.toList());
      final alive = List<Map<String, dynamic>>.from(
        users,
      ).where((u) => (u['is_deceased'] ?? false) == false).length;
      _activeMembers = alive;
    } catch (_) {
      _activeMembers = 0;
    }
  }

  Future<void> _fetchPendingPayments(List<int> ids) async {
    try {
      _pendingAmount = 0;

      if (ids.isEmpty) return;

      // Prefer RPC if available, passing only the selected dayung id(s)
      try {
        final rpc = await sb.rpc(
          'treasurer_pending_payments',
          params: {'p_dayung_ids': ids},
        );
        if (rpc is Map && rpc['total_amount'] != null) {
          _pendingAmount = double.tryParse(rpc['total_amount'].toString()) ?? 0;
          return;
        }
      } catch (_) {}

      // Fallback: query only pending payments belonging to selected dayung(s)
      final rows = await sb
          .from('payments')
          .select('amount,user_id')
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'pending');

      double total = 0;
      final memberSet = <String>{};
      for (final m in List<Map<String, dynamic>>.from(rows)) {
        total += (m['amount'] is num) ? (m['amount'] as num).toDouble() : 0.0;
        final uid = (m['user_id'] ?? '').toString();
        if (uid.isNotEmpty) memberSet.add(uid);
      }
      _pendingAmount = total;
    } catch (_) {
      _pendingAmount = 0;
    }
  }

  Future<void> _ensureDayungId() async {
    if (_dayungUnitId != null) return;
    await _loadDayungFromPrefs();
    if (_dayungUnitId != null) return;

    try {
      final uid = sb.auth.currentUser?.id;
      if (uid != null) {
        final res = await sb
            .from('dayung_units')
            .select('id')
            .eq('treasurer_id', uid)
            .limit(1);
        final list = List<Map<String, dynamic>>.from(res);
        if (list.isNotEmpty) {
          setState(
            () => _dayungUnitId = int.tryParse(list.first['id'].toString()),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchRecentDeaths(List<int> ids) async {
    try {
      if (ids.isEmpty) {
        _recentDeaths = [];
        return;
      }
      final dn = await sb
          .from('claims')
          .select('PassedAway,date_of_death')
          .inFilter('dayung_unit_id', ids)
          .order('date_of_death', ascending: false)
          .limit(2);
      _recentDeaths = List<Map<String, dynamic>>.from(
        dn,
      ).map((e) => (e['name'] ?? 'Member') as String).toList();
    } catch (_) {
      _recentDeaths = [];
    }
  }

  Future<void> _triggerPaymentCollection(int deathNoticeId) async {
    if (deathNoticeId <= 0 || _dayungUnitId == null) return;

    try {
      final notice = await sb
          .from('claims')
          .select('PassedAway')
          .eq('id', deathNoticeId)
          .maybeSingle();

      final deceasedName = (notice?['PassedAway'] ?? 'member').toString();
      final deadline = DateTime.now().add(const Duration(days: 3));
      final deadlineStr =
          '${deadline.year}-${deadline.month.toString().padLeft(2, '0')}-${deadline.day.toString().padLeft(2, '0')}';

      await sb
          .from('payments')
          .update({
            'message':
                'Due na ang inyong bayad para kay $deceasedName. Palihog magbayad wala pay $deadlineStr. Daghang salamat!',
          })
          .eq('death_notice_id', deathNoticeId)
          .eq('dayung_unit_id', _dayungUnitId!)
          .neq('status', 'paid');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Collection reminder updated.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to trigger collection: $e')),
      );
    }

    await _fetchAll();
  }

  Future<Map<String, Map<String, dynamic>>> _paymentStatsByNotice(
    List<int> deathNoticeIds,
    int dayungUnitId,
  ) async {
    if (deathNoticeIds.isEmpty) return {};
    final rows = await sb
        .from('payments')
        .select('death_notice_id,status,amount,user_id')
        .inFilter('death_notice_id', deathNoticeIds)
        .eq('dayung_unit_id', dayungUnitId);

    final stats = <String, Map<String, dynamic>>{};
    final paidUsersPerNotice = <String, Set<String>>{};
    final unpaidUsersPerNotice = <String, Set<String>>{};

    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final id = r['death_notice_id']?.toString();
      if (id == null) continue;
      final s = (r['status'] ?? '').toString().toLowerCase();
      final uid = (r['user_id'] ?? '').toString();
      final amt = _asDouble(r['amount']);
      final m = stats.putIfAbsent(
        id,
        () => {
          'paidCount': 0,
          'unpaidCount': 0,
          'paidAmount': 0.0,
          'pendingAmount': 0.0,
          'totalCount': 0,
          'paidUserIds': <String>{},
        },
      );
      paidUsersPerNotice.putIfAbsent(id, () => <String>{});
      unpaidUsersPerNotice.putIfAbsent(id, () => <String>{});
      m['totalCount'] = (m['totalCount'] as int) + 1;
      if (s == 'paid') {
        if (!paidUsersPerNotice[id]!.contains(uid)) {
          paidUsersPerNotice[id]!.add(uid);
          m['paidCount'] = (m['paidCount'] as int) + 1;
          (m['paidUserIds'] as Set<String>).add(uid);
        }
        m['paidAmount'] = (m['paidAmount'] as double) + amt;
      } else {
        if (!unpaidUsersPerNotice[id]!.contains(uid)) {
          unpaidUsersPerNotice[id]!.add(uid);
          m['unpaidCount'] = (m['unpaidCount'] as int) + 1;
        }
        m['pendingAmount'] = (m['pendingAmount'] as double) + amt;
      }
    }
    // Convert Set to List for debug print compatibility
    for (final m in stats.values) {
      m['paidUserIds'] = (m['paidUserIds'] as Set<String>).toList();
    }
    return stats;
  }

  List<Widget> get _pages => [
    _homePage(),
    _dayungUnitId == null
        ? const Center()
        : TreasurerContributionsPage(dayungUnitId: _dayungUnitId!),
    _dayungUnitId == null
        ? const SizedBox.shrink()
        : TreasurerClaimsPage(dayungUnitId: _dayungUnitId!),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provUnit = context.watch<DayungUnitProvider>().currentUnitId;
    if (provUnit != _lastRoleUnitId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeOnProviderUnitChanged(provUnit);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wide = width > 820;
    // final provUnit = context.watch<DayungRoleProvider>().unitId;
    // if (provUnit != _lastRoleUnitId) {
    //   WidgetsBinding.instance.addPostFrameCallback((_) {
    //     _maybeOnProviderUnitChanged(provUnit);
    //   });
    // }

    return Scaffold(
      backgroundColor: dayungPageBackground(context),
      drawer: _buildSideDrawer(context),
      body: Container(
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
      ),
    );
  }

  /* ------------------------------- UI parts ------------------------------- */

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
                    color: const Color(0xFF1E40AF).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1E40AF).withValues(alpha: 0.3),
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
                      _dayungLabel,
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
              _buildModernIconButton(
                icon: Icons.notifications_active_rounded,
                onTap: _openNotifications,
                badge: _unreadNotifCount > 0 ? '$_unreadNotifCount' : null,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Maayung buntag,\nTreasurer!',
                  style: TextStyle(
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
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: IndexedStack(index: _tab, children: _pages),
          ),
        ),
      ),
    );
  }

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

  Widget _buildSideDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: kBg,
      child: Column(
        children: [
          // Modern Drawer Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kPrimaryDark, kPrimary],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: kAccent.withValues(alpha: 0.15),
                  child: Icon(Icons.person, size: 36, color: kAccent),
                ),
                const SizedBox(height: 16),
                Text(
                  _fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 4),
                // Text(
                //   _selectedDayungUnit,
                //   style: TextStyle(
                //     color: Colors.white.withOpacity(0.85),
                //     fontSize: 15,
                //     fontFamily: 'OpenSans',
                //   ),
                // ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Modern Drawer Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _ModernDrawerTile(
                  icon: Icons.account_circle,
                  label: 'Profile',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfilePage()),
                    );
                  },
                ),
                _ModernDrawerTile(
                  icon: Icons.people_rounded,
                  label: 'Beneficiaries',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BeneficiaryPage(),
                      ),
                    );
                  },
                ),
                _ModernDrawerTile(
                  icon: Icons.notifications,
                  label: 'Notifications',
                  onTap: () async {
                    Navigator.pop(context);
                    await _openNotifications();
                  },
                ),
                _ModernDrawerTile(
                  icon: Icons.settings,
                  label: 'Settings',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProfSettingsPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 32, thickness: 1, color: kSubText),
                _ModernDrawerTile(
                  icon: Icons.logout,
                  label: 'Logout',
                  onTap: () async {
                    Navigator.pop(context);
                    await showLogoutDialog(context);
                  },
                ),
              ],
            ),
          ),
          // App version or footer
          Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 8),
            child: Text(
              'v1.0.0',
              style: TextStyle(
                color: kSubText.withValues(alpha: 0.7),
                fontSize: 13,
                fontFamily: 'OpenSans',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernIconButton({
    required IconData icon,
    required VoidCallback onTap,
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
              child: Icon(icon, color: Colors.white, size: 20),
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

  Widget _buildNavItem(IconData icon, String label, int index) {
    final selected = _tab == index;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
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

  Widget _homePage() {
    return RefreshIndicator(
      onRefresh: _fetchAll,
      edgeOffset: 68,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildModernStatsCards(),
            const SizedBox(height: 24),
            _buildQuickActions(),
            const SizedBox(height: 24),
            _buildRecentActivity(),
            const SizedBox(height: 24),
            _buildDeathNoticesSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildModernStatsCards() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: dayungSectionCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Overview',
            style: TextStyle(
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
                child: SizedBox(
                  height: 180,
                  child: _buildModernStatCard(
                    icon: Icons.groups_rounded,
                    title: 'Active Members',
                    value: _loading ? '—' : _activeMembers.toString(),
                    color: const Color(0xFF3B82F6),
                    bgColor: const Color(0xFFEFF6FF),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 180,
                  child: GestureDetector(
                    onTap: () {
                      if (_dayungUnitId == null) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              RecentDeathNotices(dayungUnitId: _dayungUnitId),
                        ),
                      );
                    },
                    child: _buildRecentDeathsCard(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 180,
                  child: _buildModernStatCard(
                    icon: Icons.account_balance_wallet_rounded,
                    title: 'Pending Amount',
                    value: _loading
                        ? '—'
                        : '₱${_pendingAmount.toStringAsFixed(0)}',
                    color: const Color(0xFFF59E0B),
                    bgColor: const Color(0xFFFEF3C7),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernStatCard({
    required IconData icon,
    required String title,
    required String value,
    String subtitle = '',
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
        crossAxisAlignment: CrossAxisAlignment.center, // Center horizontally
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
            textAlign: TextAlign.center, // Center text
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center, // Center text
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center, // Center text
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: color.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentDeathsCard() {
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
              FontAwesomeIcons.dove,
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
            children: _recentDeaths
                .take(2)
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

  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: dayungSectionCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
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
                child: SizedBox(
                  height: 140,
                  child: _modernActionCardGrid(
                    icon: Icons.account_balance_wallet_rounded,
                    title: 'Manage Fund',
                    subtitle: 'View & manage',
                    color: const Color(0xFF3B82F6),
                    onTap: () {
                      if (_dayungUnitId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Select a Dayung first')),
                        );
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ManageFundPage(dayungUnitId: _dayungUnitId!),
                        ),
                      ).then((_) => _fetchAll());
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 140,
                  child: _modernActionCardGrid(
                    icon: Icons.payments_rounded,
                    title: 'My Payment Page',
                    subtitle: 'Pay contributions',
                    color: const Color(0xFF2563EB),
                    onTap: () {
                      if (_dayungUnitId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Select a Dayung first')),
                        );
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              TreasurerPaymentPage(dayungUnitId: _dayungUnitId!),
                        ),
                      ).then((_) => _fetchAll());
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 140,
                  child: _modernActionCardGrid(
                    icon: Icons.verified_user_rounded,
                    title: 'Paid Members',
                    subtitle: 'View paid list',
                    color: const Color(0xFF10B981),
                    onTap: () async {
                      if (_dayungUnitId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Select a Dayung first')),
                        );
                        return;
                      }
                      await _showMembersModal(paid: true);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 140,
                  child: _modernActionCardGrid(
                    icon: Icons.pending_actions_rounded,
                    title: 'Unpaid Members',
                    subtitle: 'View unpaid list',
                    color: const Color(0xFFEF4444),
                    onTap: () async {
                      if (_dayungUnitId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Select a Dayung first')),
                        );
                        return;
                      }
                      await _showMembersModal(paid: false);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 140,
                  child: _modernActionCardGrid(
                    icon: Icons.qr_code_2_rounded,
                    title: 'GCash QR',
                    subtitle: 'Show payment QR',
                    color: const Color(0xFFF59E0B),
                    onTap: () {
                      if (_dayungUnitId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Select a Dayung first')),
                        );
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              GcashQrPage(dayungUnitId: _dayungUnitId!),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: SizedBox()),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Quick Access',
            style: TextStyle(
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
                child: SizedBox(
                  height: 110,
                  child: _modernActionCardGrid(
                    icon: Icons.account_balance_rounded,
                    title: 'Collections',
                    subtitle: 'From collectors',
                    color: const Color(0xFF10B981),
                    onTap: () {
                      if (_dayungUnitId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Select a Dayung first')),
                        );
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CollectedFromCollectorsPage(
                            dayungUnitId: _dayungUnitId!,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: SizedBox()),
              const SizedBox(width: 12),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modernActionCardGrid({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: color.withValues(alpha: 0.1),
        highlightColor: color.withValues(alpha: 0.05),
        child: Ink(
          decoration: BoxDecoration(
            color: dayungSurface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: dayungBorder(context)),
            boxShadow: [dayungElevatedShadow(context)],
          ),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: 'OpenSans',
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: dayungAccentSurface(
                        context,
                        const Color(0xFFEC4899),
                        lightAlpha: 0.08,
                        darkAlpha: 0.14,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.family_restroom_rounded,
                      color: Color(0xFFEC4899),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Death Notice Queue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: dayungTextColor(context),
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      if (_dayungUnitId == null) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              RecentDeathNotices(dayungUnitId: _dayungUnitId),
                        ),
                      );
                    },
                    child: const Text(
                      'View All',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF3B82F6),
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
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
                child: Text(
                  _loading
                      ? 'Refreshing treasurer dashboard...'
                      : 'Pending amount for collection: ₱${_pendingAmount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: dayungTextColor(context),
                    fontFamily: 'OpenSans',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (_recentDeaths.isEmpty)
                const Text(
                  'No recent activity yet.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                    fontFamily: 'OpenSans',
                  ),
                )
              else
                ..._recentDeaths
                    .take(3)
                    .map(
                      (name) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF3B82F6),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF111827),
                                  fontFamily: 'OpenSans',
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

  Widget _buildCollectedSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF059669)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.account_balance_rounded,
            color: Colors.white,
            size: 32,
          ),
          const SizedBox(height: 12),
          const Text(
            'Collected from Collectors',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (_dayungUnitId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Select a Dayung first')),
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CollectedFromCollectorsPage(
                        dayungUnitId: _dayungUnitId!,
                      ),
                    ),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Text(
                    'View Collections',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

Widget _buildDeathNoticesSection() {
  return FutureBuilder<List<Map<String, dynamic>>>(
    future: _deathNoticesFutureCached,
    builder: (context, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: CircularProgressIndicator(),
          ),
        );
      }
      if (snap.hasError) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: const Text(
            'Failed to load death notices.',
            style: TextStyle(color: Color(0xFFDC2626)),
          ),
        );
      }

      final notices = snap.data ?? const <Map<String, dynamic>>[];
      if (notices.isEmpty) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            'No death notices yet.',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }

      // Filter by Members | Beneficiaries tab
      final filtered = notices.where((n) {
        final t = (n['deceased_type'] ?? '').toString().toLowerCase();
        if (_noticeFilter == 'members') return t == 'member';
        return t == 'beneficiary';
      }).toList();

      if (filtered.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _deathNoticesHeader(count: 0),
            const SizedBox(height: 12),
            _buildNoticeTypeTabs(),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _noticeFilter == 'members'
                    ? 'No member death notices yet.'
                    : 'No beneficiary death notices yet.',
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      }

      // Build payment stats based on payments table
      final noticeIds =
          filtered.map<int>((e) => int.tryParse('${e['id']}') ?? 0).toList();
      final dayungId = _dayungUnitId ??
          (filtered.isNotEmpty ? (filtered.first['dayung_unit_id'] ?? 0) : 0);

      _ensureStatsFuture(noticeIds, dayungId);

      return FutureBuilder<Map<String, Map<String, dynamic>>>(
        future: _paymentStatsFutureCached,
        builder: (context, statSnap) {
          final stats =
              statSnap.data ?? const <String, Map<String, dynamic>>{};

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _deathNoticesHeader(count: filtered.length),
              const SizedBox(height: 12),
              _buildNoticeTypeTabs(),
              const SizedBox(height: 16),
              ...filtered.map(
                (n) => _buildModernNoticeCard(n, stats, dayungId),
              ),
            ],
          );
        },
      );
    },
  );
}

  Widget _deathNoticesHeader({required int count}) {
    return Row(
      children: [
        const Text(
          'Death Notices',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E40AF),
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E40AF).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF1E40AF).withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: Color(0xFF1E40AF),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoticeTypeTabs() {
    final isMembers = _noticeFilter == 'members';
    return Center(
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _segTab(
              label: 'Members',
              selected: isMembers,
              onTap: () => setState(() => _noticeFilter = 'members'),
            ),
            _segTab(
              label: 'Beneficiaries',
              selected: !isMembers,
              onTap: () => setState(() => _noticeFilter = 'beneficiaries'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segTab({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: selected ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E40AF) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : const Color(0xFF1E40AF),
          ),
        ),
      ),
    );
  }

  Widget _buildModernNoticeCard(
    Map<String, dynamic> notice,
    Map<String, Map<String, dynamic>> stats,
    int dayungId,
  ) {
    final sid = (notice['id'] ?? '').toString();
    final dId =
        int.tryParse((notice['dayung_unit_id'] ?? dayungId).toString()) ?? 0;
    final st =
        stats[sid] ??
        const {
          'paidCount': 0,
          'unpaidCount': 0,
          'paidAmount': 0.0,
          'pendingAmount': 0.0,
          'totalCount': 0,
          'paidUserIds': [],
        };

    final paid =
      int.tryParse('${notice['paid_count'] ?? st['paidCount'] ?? 0}') ?? 0;
    
    final unpaid =
      int.tryParse('${notice['unpaid_count'] ?? st['unpaidCount'] ?? 0}') ??
      0;
    final totalCount = paid + unpaid;

    final paidAmt = _asDouble(st['paidAmount']);
    final pendingAmt = _asDouble(st['pendingAmount']);

    final completed = unpaid == 0 && totalCount > 0;
    final progress = totalCount == 0
        ? 0.0
        : (paid / totalCount).clamp(0.0, 1.0);
    final totalPaidAmount = _asDouble(notice['total_paid_amount']);
    final totalPaymentAmount = _asDouble(
      notice['total_payment_amount'],
      fallback: paidAmt + pendingAmt,
    );

    //debugPrint('Notice ID: $sid | Paid: $paid | Unpaid: $unpaid | Total: $totalCount | PaidAmt: $paidAmt | PendingAmt: $pendingAmt | PaidUserIds: $paidUserIds');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (notice['PassedAway'] ?? 'Death Notice').toString(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2937),
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: completed
                      ? const Color(0xFF10B981).withValues(alpha: 0.1)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: completed
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B),
                  ),
                ),
                child: Text(
                  completed ? 'Completed' : 'Collecting',
                  style: TextStyle(
                    color: completed
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.event_rounded,
                size: 16,
                color: Color(0xFF6B7280),
              ),
              const SizedBox(width: 8),
              Text(
                (notice['date_of_death'] ?? '').toString().isEmpty
                    ? '—'
                    : notice['date_of_death'].toString(),
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildCountChip(
                Icons.verified_rounded,
                'Paid:',
                paid,
                const Color(0xFF10B981),
              
              ),
              const SizedBox(width: 8),
              _buildCountChip(
                Icons.pending_actions_rounded,
                'Unpaid',
                unpaid,
                const Color(0xFFEF4444),
              ),
              const Spacer(),
              Text(
                '₱${totalPaidAmount.toStringAsFixed(0)} / ₱${totalPaymentAmount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2937),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: AlwaysStoppedAnimation(
                completed ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${(progress * 100).round()}% Complete',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
              const Spacer(),
              Text(
                '$paid of $totalCount members',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _showPaymentStatusSheet(_asInt(notice['id']), dId),
                  icon: const Icon(Icons.info_outline_rounded, size: 18),
                  label: const Text('View Status'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(color: Color(0xFF3B82F6)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  // ...inside _buildModernNoticeCard...
                  onPressed: completed
                      ? null
                      : () => _triggerPaymentCollection(_asInt(notice['id'])),

                  icon: const Icon(Icons.campaign_rounded, size: 18),
                  label: const Text('Collect'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCountChip(
    IconData icon,
    String label,
    int count,
    Color color, {
    double? amount,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            amount != null
                ? '$label $count (₱${amount.toStringAsFixed(0)})'
                : '$label $count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMembersModal({required bool paid}) async {
    final ids = await _selectedDayungIds();
    if (ids.isEmpty) return;

    // 1. Fetch all death notices for this dayung
    final notices = await sb
        .from('claims')
        .select('id, PassedAway, date_of_death')
        .inFilter('dayung_unit_id', ids)
        .order('date_of_death', ascending: false);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: dayungSurface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 56,
                    height: 6,
                    decoration: BoxDecoration(
                      color: dayungBorder(ctx),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  paid
                      ? 'Paid Members per Deceased'
                      : 'Unpaid Members per Deceased',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: dayungTextColor(ctx),
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  paid
                      ? 'Choose a deceased member to see who already paid.'
                      : 'Choose a deceased member to see who still needs to pay.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: dayungSubtextColor(ctx),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: dayungSoftSurface(ctx),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: dayungBorder(ctx)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color:
                              (paid
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFF59E0B))
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          paid
                              ? Icons.check_circle_rounded
                              : Icons.pending_actions_rounded,
                          color: paid
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${notices.length} deceased record${notices.length == 1 ? '' : 's'} available',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: dayungTextColor(ctx),
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: notices.isEmpty
                      ? Center(
                          child: Text(
                            'No death notices found',
                            style: TextStyle(color: dayungSubtextColor(ctx)),
                          ),
                        )
                      : ListView.separated(
                          itemCount: notices.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final n = notices[i];
                            final deceasedName = (n['PassedAway'] ?? 'Deceased')
                                .toString();
                            final date = (n['date_of_death'] ?? '').toString();
                            return Material(
                              color: dayungSurface(ctx),
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _showMembersPerDeathNotice(
                                    deathNoticeId: n['id'],
                                    deceasedName: deceasedName,
                                    paid: paid,
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: dayungAccentSurface(
                                            ctx,
                                            kDanger,
                                            lightAlpha: 0.10,
                                            darkAlpha: 0.16,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.person_off_rounded,
                                          color: kDanger,
                                          size: 28,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              deceasedName,
                                              style: TextStyle(
                                                fontSize: 19,
                                                fontWeight: FontWeight.w800,
                                                color: dayungTextColor(ctx),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              date.isEmpty
                                                  ? 'No date of death recorded'
                                                  : 'Date of death: $date',
                                              style: TextStyle(
                                                fontSize: 15,
                                                color: dayungSubtextColor(ctx),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: dayungAccentSurface(
                                            ctx,
                                            kPrimaryDark,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.chevron_right_rounded,
                                          color: kPrimaryDark,
                                        ),
                                      ),
                                    ],
                                  ),
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
      },
    );
  }

  Future<void> _showMembersPerDeathNotice({
    required int deathNoticeId,
    required String deceasedName,
    required bool paid,
  }) async {
    final ids = await _selectedDayungIds();
    if (ids.isEmpty) return;

    try {
      final rows = await sb
          .from('payments')
          .select(
            'id, amount, status, paid_at, collected_by, '
            'user:users!payments_user_id_fkey(full_name), '
            'collector:users!payments_collected_by_fkey(full_name)',
          )
          .eq('death_notice_id', deathNoticeId)
          .eq('dayung_unit_id', ids.first);

      final items =
          List<Map<String, dynamic>>.from(rows)
              .where(
                (r) => paid
                    ? (r['status'] ?? '').toString().toLowerCase() == 'paid'
                    : (r['status'] ?? '').toString().toLowerCase() != 'paid',
              )
              .toList()
            ..sort((a, b) {
              final an = (((a['user'] as Map?)?['full_name']) ?? '')
                  .toString()
                  .toLowerCase();
              final bn = (((b['user'] as Map?)?['full_name']) ?? '')
                  .toString()
                  .toLowerCase();
              return an.compareTo(bn);
            });

      // Build collector lookup map
      final missingCollectorIds = <String>{
        for (final r in items)
          if ((r['collected_by'] ?? '').toString().isNotEmpty &&
              ((((r['collector'] as Map?)?['full_name']) ?? '')
                  .toString()
                  .isEmpty))
            (r['collected_by']).toString(),
      }.toList();

      final collectorLookup = <String, String>{};
      if (missingCollectorIds.isNotEmpty) {
        try {
          final u = await sb
              .from('users')
              .select('id, full_name')
              .inFilter('id', missingCollectorIds);
          for (final m in List<Map<String, dynamic>>.from(u)) {
            collectorLookup[(m['id'] ?? '').toString()] =
                (m['full_name'] ?? 'Collector').toString();
          }
        } catch (_) {}
      }

      if (!mounted) return;
      final totalAmount = items.fold<double>(
        0.0,
        (sum, row) => sum + _asDouble(row['amount']),
      );

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (context) {
          final paidItems = items
              .where(
                (r) => (r['status'] ?? '').toString().toLowerCase() == 'paid',
              )
              .toList();
          final pendingItems = items
              .where(
                (r) => (r['status'] ?? '').toString().toLowerCase() != 'paid',
              )
              .toList();

          Widget section(
            String title,
            List<Map<String, dynamic>> rows,
            bool isPaid,
          ) {
            if (rows.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: kPrimaryDark,
                    ),
                  ),
                ),
                ...rows.map((r) {
                  final directCollectorName =
                      (((r['collector'] as Map?)?['full_name']) ?? '')
                          .toString();
                  final collectorName = directCollectorName.isNotEmpty
                      ? directCollectorName
                      : (collectorLookup[(r['collected_by'] ?? '')
                                .toString()] ??
                            '');
                  return _buildStatusTile({
                    ...r,
                    'resolved_collector_name': collectorName,
                  }, isPaid);
                }),
              ],
            );
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Payment Status',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: kPrimaryDark,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 460),
                      child: ListView(
                        children: [
                          section('Paid Members', paidItems, true),
                          section('Pending Members', pendingItems, false),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load members: $e')));
    }
  }

  Future<void> _showPaymentStatusSheet(int noticeId, int dayungUnitId) async {
    final sb = Supabase.instance.client;
    try {
      final rows = await sb
          .from('payments')
          .select(
            'id, amount, status, paid_at, collected_by, '
            'user:users!payments_user_id_fkey(full_name), '
            'collector:users!payments_collected_by_fkey(full_name)',
          )
          .eq('death_notice_id', noticeId)
          .eq('dayung_unit_id', dayungUnitId);

      final items = List<Map<String, dynamic>>.from(rows);

      final missingCollectorIds = <String>{
        for (final r in items)
          if ((r['collected_by'] ?? '').toString().isNotEmpty &&
              ((((r['collector'] as Map?)?['full_name']) ?? '')
                  .toString()
                  .isEmpty))
            (r['collected_by']).toString(),
      }.toList();

      final collectorLookup = <String, String>{};
      if (missingCollectorIds.isNotEmpty) {
        try {
          final u = await sb
              .from('users')
              .select('id, full_name')
              .inFilter('id', missingCollectorIds);
          for (final m in List<Map<String, dynamic>>.from(u)) {
            collectorLookup[(m['id'] ?? '').toString()] =
                (m['full_name'] ?? 'Collector').toString();
          }
        } catch (_) {}
      }

      items.sort((a, b) {
        final an = (((a['user'] as Map?)?['full_name']) ?? '')
            .toString()
            .toLowerCase();
        final bn = (((b['user'] as Map?)?['full_name']) ?? '')
            .toString()
            .toLowerCase();
        return an.compareTo(bn);
      });

      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) {
          final paidItems = items
              .where(
                (r) => (r['status'] ?? '').toString().toLowerCase() == 'paid',
              )
              .toList();
          final pendingItems = items
              .where(
                (r) => (r['status'] ?? '').toString().toLowerCase() != 'paid',
              )
              .toList();

          Widget section(
            String title,
            List<Map<String, dynamic>> rows,
            bool isPaid,
          ) {
            if (rows.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: kPrimaryDark,
                    ),
                  ),
                ),
                ...rows.map((r) {
                  final directCollectorName =
                      (((r['collector'] as Map?)?['full_name']) ?? '')
                          .toString();
                  final collectorName = directCollectorName.isNotEmpty
                      ? directCollectorName
                      : (collectorLookup[(r['collected_by'] ?? '')
                                .toString()] ??
                            '');
                  return _buildStatusTile({
                    ...r,
                    'resolved_collector_name': collectorName,
                  }, isPaid);
                }),
              ],
            );
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Payment Status',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: kPrimaryDark,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 460),
                      child: ListView(
                        children: [
                          section('Paid Members', paidItems, true),
                          section('Pending Members', pendingItems, false),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load payment status: $e')),
      );
    }
  }

  Widget _buildStatusTile(Map<String, dynamic> r, bool paid) {
    final payerName = (((r['user'] as Map?)?['full_name']) ?? '').toString();
    final title = payerName.isNotEmpty ? payerName : 'Payment #${r['id']}';
    final amt = _asDouble(r['amount']);
    final paidAtStr = _fmtDateTime(r['paid_at']);
    final resolvedCollectorName = (r['resolved_collector_name'] ?? '')
        .toString();
    final fallbackCollectorName =
        (((r['collector'] as Map?)?['full_name']) ?? '').toString();
    final collectorName = resolvedCollectorName.isNotEmpty
        ? resolvedCollectorName
        : fallbackCollectorName;
    final effectiveCollectorName = collectorName.isNotEmpty
        ? collectorName
        : 'Collector not recorded';
    final subtitleText = paid
        ? 'Collected${paidAtStr.isNotEmpty ? ' on: $paidAtStr' : ''}\nCollected by: $effectiveCollectorName'
        : 'Pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: paid
                ? Colors.green.withValues(alpha: .15)
                : Colors.orange.withValues(alpha: .15),
            child: Icon(
              paid ? Icons.check_rounded : Icons.hourglass_bottom_rounded,
              color: paid ? Colors.green[800] : Colors.orange[800],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: kNeutralText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitleText,
                  style: const TextStyle(
                    color: kSubtleText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₱${amt.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: kNeutralText,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: paid
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  paid ? 'Paid' : 'Pending',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: paid ? Colors.green[800] : Colors.orange[800],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _memberSummaryCard({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 24),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: kNeutralText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: kSubtleText,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDateTime(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    DateTime? dt = DateTime.tryParse(s);
    if (dt == null) return '';
    dt = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _ModernDrawerTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ModernDrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_ModernDrawerTile> createState() => _ModernDrawerTileState();
}

class _ModernDrawerTileState extends State<_ModernDrawerTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = kPrimary.withValues(alpha: 0.08);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: _hovering ? hoverColor : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: ListTile(
          leading: Icon(widget.icon, color: kPrimary),
          title: Text(
            widget.label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: kText,
              fontFamily: 'Montserrat',
            ),
          ),
          onTap: widget.onTap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 2,
          ),
        ),
      ),
    );
  }
}
