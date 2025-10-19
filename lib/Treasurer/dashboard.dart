import 'dart:convert';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/Treasurer/collected.dart';
import 'package:capstone_app/Treasurer/manage_fund.dart';
import 'package:capstone_app/pages/claims.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/pages/recentdeathnotices.dart';
import 'package:capstone_app/profile/profile.dart';
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

class TreasurerDashboardPage extends StatefulWidget {
  const TreasurerDashboardPage({super.key});

  @override
  State<TreasurerDashboardPage> createState() => _TreasurerDashboardPageState();
}

class _TreasurerDashboardPageState extends State<TreasurerDashboardPage> {
  final sb = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();
  Future<List<Map<String, dynamic>>>? _deathNoticesFutureCached;
  Future<Map<int, Map<String, dynamic>>>? _paymentStatsFutureCached;
  List<int> _lastNoticeIds = const [];
  int? _lastStatsDayungId;

  String _dayungLabel = 'Dayung';
  int _tab = 0;
  bool _showNavBar = true;
  int? _dayungUnitId;
  int? _lastRoleUnitId;
  bool _loading = true;
  int _activeMembers = 0;
  double _pendingAmount = 0;
  int _pendingMembers = 0;
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
    await _ensureDayungId();
    await _fetchAll();
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

  Future<List<int>> _selectedDayungIds() async {
    await _ensureDayungId();
    if (_dayungUnitId != null) return [_dayungUnitId!];
    return const [];
  }

  Future<List<Map<String, dynamic>>> _deathNoticesFuture() async {
    final ids = await _selectedDayungIds();
    return _fetchDeathNotices(ids);
  }

  Future<List<Map<String, dynamic>>> _fetchDeathNotices(
    List<int> dayungIds,
  ) async {
    try {
      final ids = dayungIds.isNotEmpty
          ? dayungIds
          : (_dayungUnitId != null ? [_dayungUnitId!] : const <int>[]);
      if (ids.isEmpty) return [];

      // Only fetch notices where dayung_unit_id matches
      final dnDirect = await sb
          .from('death_notices')
          .select(
            'id,name,date_of_death,dayung_unit_id,user_id,beneficiary_id,deceased_type',
          )
          .inFilter('dayung_unit_id', ids)
          .order('date_of_death', ascending: false);

      final direct = List<Map<String, dynamic>>.from(dnDirect);

      // Ensure deceased_type populated for older rows
      for (final m in direct) {
        final dtype = (m['deceased_type'] ?? '').toString();
        if (dtype.isEmpty) {
          m['deceased_type'] = (m['beneficiary_id'] != null)
              ? 'beneficiary'
              : 'member';
        }
      }

      return direct;
    } catch (_) {
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

      // Refresh death notices only when explicitly refreshing
      _deathNoticesFutureCached = _deathNoticesFuture();
      // Reset stats cache; it will be re-initialized lazily when notices arrive
      _paymentStatsFutureCached = null;
      _lastNoticeIds = const [];
      _lastStatsDayungId = _dayungUnitId;

      await Future.wait([
        _fetchActiveMembers(selected),
        _fetchPendingPayments(selected),
        _fetchRecentDeaths(selected),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      _pendingMembers = 0;

      if (ids.isEmpty) return;

      // Prefer RPC if available, passing only the selected dayung id(s)
      try {
        final rpc = await sb.rpc(
          'treasurer_pending_payments',
          params: {'p_dayung_ids': ids},
        );
        if (rpc is Map && rpc['total_amount'] != null) {
          _pendingAmount = double.tryParse(rpc['total_amount'].toString()) ?? 0;
          _pendingMembers = int.tryParse(rpc['member_count'].toString()) ?? 0;
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
      _pendingMembers = memberSet.length;
    } catch (_) {
      _pendingAmount = 0;
      _pendingMembers = 0;
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
          .from('death_notices')
          .select('name,date_of_death')
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

  Future<void> _triggerPaymentCollection(
    int deathNoticeId,
    int dayungUnitId,
  ) async {
    // Fetch notice meta (always contains the member/parent user_id snapshot)
    Map<String, dynamic>? dn;
    try {
      final res = await sb
          .from('death_notices')
          .select('id,deceased_type,user_id,beneficiary_id')
          .eq('id', deathNoticeId)
          .single();
      dn = Map<String, dynamic>.from(res);
    } catch (_) {}

    // Exclude this user from billing (self for member, parent for beneficiary)
    final String? excludedUserId = (dn?['user_id'] ?? '').toString().isNotEmpty
        ? (dn!['user_id']).toString()
        : null;

    // Cleanup: remove any existing payment row for the excluded user (if any)
    if (excludedUserId != null && excludedUserId.isNotEmpty) {
      try {
        await sb
            .from('payments')
            .delete()
            .eq('death_notice_id', deathNoticeId)
            .eq('dayung_unit_id', dayungUnitId)
            .eq('user_id', excludedUserId);
      } catch (_) {}
    }

    // Get active members for the dayung
    final appsRes = await sb
        .from('applications')
        .select('user_id')
        .eq('dayung_unit_id', dayungUnitId)
        .eq('status', 'approved');
    final members = List<Map<String, dynamic>>.from(appsRes);

    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active members to charge.')),
      );
      return;
    }

    // Already generated payments for this notice/dayung
    final existingRes = await sb
        .from('payments')
        .select('user_id')
        .eq('death_notice_id', deathNoticeId)
        .eq('dayung_unit_id', dayungUnitId);
    final existingIds = {
      for (final r in List<Map<String, dynamic>>.from(existingRes))
        (r['user_id'] ?? '').toString(),
    };

    // Prepare new rows (skip duplicates and excluded user)
    final rows = <Map<String, dynamic>>[];
    for (final u in members) {
      final uid = (u['user_id'] ?? '').toString(); // CHANGED from u['id']
      if (uid.isEmpty) continue;
      if (excludedUserId != null && uid == excludedUserId) continue;
      if (existingIds.contains(uid)) continue;
      rows.add({
        'user_id': uid,
        'amount': 1, // adjust as needed
        'status': 'pending',
        'death_notice_id': deathNoticeId,
        'dayung_unit_id': dayungUnitId,
      });
    }

    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No new payments to create.')),
      );
      await _fetchAll();
      return;
    }

    try {
      await sb.from('payments').insert(rows);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created ${rows.length} payment(s).')),
      );
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Some payments already existed. New ones added.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create payments: ${e.message}')),
        );
      }
    }

    await _fetchAll();
  }

  Future<Map<int, Map<String, dynamic>>> _paymentStatsByNotice(
    List<int> noticeIds,
    int dayungUnitId,
  ) async {
    if (noticeIds.isEmpty) return {};
    final rows = await sb
        .from('payments')
        .select('death_notice_id,status,amount')
        .inFilter('death_notice_id', noticeIds)
        .eq('dayung_unit_id', dayungUnitId);

    final stats = <int, Map<String, dynamic>>{};
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final id = r['death_notice_id'] as int?;
      if (id == null) continue;
      final s = (r['status'] ?? '').toString().toLowerCase();
      final amt = (r['amount'] is num) ? (r['amount'] as num).toDouble() : 0.0;
      final m = stats.putIfAbsent(
        id,
        () => {
          'paidCount': 0,
          'unpaidCount': 0,
          'paidAmount': 0.0,
          'pendingAmount': 0.0,
          'totalCount': 0,
        },
      );
      m['totalCount'] = (m['totalCount'] as int) + 1;
      if (s == 'paid') {
        m['paidCount'] = (m['paidCount'] as int) + 1;
        m['paidAmount'] = (m['paidAmount'] as double) + amt;
      } else {
        m['unpaidCount'] = (m['unpaidCount'] as int) + 1;
        m['pendingAmount'] = (m['pendingAmount'] as double) + amt;
      }
    }
    return stats;
  }

  List<Widget> get _pages => [
    _homePage(),
    const Placeholder(), // Contributions
    ClaimsPage(onNavBarVisible: (v) => setState(() => _showNavBar = v)),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wide = width > 820;
    final provUnit = context.watch<DayungRoleProvider>().unitId;
    if (provUnit != _lastRoleUnitId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeOnProviderUnitChanged(provUnit);
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E40AF), Color(0xFF3B82F6), Color(0xFFF8FAFC)],
            stops: [0.0, 0.3, 0.3],
          ),
        ),
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E40AF).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1E40AF).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _dayungLabel,
                      overflow: TextOverflow.ellipsis,
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
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationPage()),
                ),
                badge: '1',
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
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfilePage()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.person,
                      size: 34,
                      color: Color(0xFF1E40AF),
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

  Widget _buildContentArea(bool wide) {
    return Expanded(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNavItem(Icons.home_rounded, "Home", 0),
                  _buildNavItem(Icons.public, "Contributions", 1),
                  _buildNavItem(Icons.description, "Claims", 2),
                ],
              ),
            ),
          ),
        ),
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
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
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
                    color: const Color(0xFFEF4444).withOpacity(0.3),
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
              ? const Color(0xFF1E40AF).withOpacity(0.1)
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

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _dayungLabel,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: kPrimaryDark,
                letterSpacing: .4,
              ),
            ),
          ),
          _iconBtn(
            icon: Icons.notifications_active_rounded,
            color: kWarn,
            tooltip: 'Notifications',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationPage()),
            ),
            badge: '1',
          ),
          const SizedBox(width: 6),
          _iconBtn(
            icon: Icons.settings_rounded,
            color: kPrimary,
            tooltip: 'Profile & Settings',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _greeting() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Maayung buntag,\nTreasurer!',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.05,
                color: kNeutralText,
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
            child: const CircleAvatar(
              radius: 28,
              backgroundColor: kPrimary,
              child: Icon(Icons.person, size: 34, color: Colors.white),
            ),
          ),
        ],
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
            _buildCollectedSection(),
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
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
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center, // Center horizontally
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
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
              color: color.withOpacity(0.8),
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
                color: color.withOpacity(0.6),
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
      decoration: BoxDecoration(
        color: const Color(0xFFFDF2F8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEC4899).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEC4899).withOpacity(0.1),
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
        _buildModernActionCard(
          icon: Icons.account_balance_wallet_rounded,
          title: 'Manage Fund',
          subtitle: 'View and manage fund details',
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
                builder: (_) => ManageFundPage(dayungUnitId: _dayungUnitId!),
              ),
            ).then((_) => _fetchAll());
          },
        ),
        const SizedBox(height: 8),
        _buildModernActionCard(
          icon: Icons.verified_user_rounded,
          title: 'Paid Members',
          subtitle: 'View members who have paid',
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
        const SizedBox(height: 8),
        _buildModernActionCard(
          icon: Icons.pending_actions_rounded,
          title: 'Unpaid Members',
          subtitle: 'View members who haven\'t paid',
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
      ],
    );
  }

  Widget _buildModernActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: color.withOpacity(0.6),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
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
            color: const Color(0xFF10B981).withOpacity(0.3),
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
                  color: Colors.black.withOpacity(0.1),
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
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
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
                  color: Colors.grey.withOpacity(0.08),
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

        final noticeIds = filtered
            .map<int>((e) => int.tryParse('${e['id']}') ?? 0)
            .toList();
        final dayungId =
            _dayungUnitId ??
            (filtered.isNotEmpty ? (filtered.first['dayung_unit_id'] ?? 0) : 0);

        _ensureStatsFuture(noticeIds, dayungId);

        return FutureBuilder<Map<int, Map<String, dynamic>>>(
          future: _paymentStatsByNotice(noticeIds, dayungId),
          builder: (context, statSnap) {
            final stats = statSnap.data ?? const <int, Map<String, dynamic>>{};

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
            color: const Color(0xFF1E40AF).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E40AF).withOpacity(0.3)),
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
    Map<int, Map<String, dynamic>> stats,
    int dayungId,
  ) {
    final sid = int.tryParse('${notice['id']}') ?? 0;
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
        };

    final paid = (st['paidCount'] ?? 0) as int;
    final unpaid = (st['unpaidCount'] ?? 0) as int;
    final totalCount = (st['totalCount'] ?? (paid + unpaid)) as int;
    final paidAmt = (st['paidAmount'] ?? 0.0) as double;
    final pendingAmt = (st['pendingAmount'] ?? 0.0) as double;

    final completed = unpaid == 0 && totalCount > 0;
    final progress = totalCount == 0
        ? 0.0
        : (paid / totalCount).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
                  (notice['name'] ?? 'Death Notice').toString(),
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
                      ? const Color(0xFF10B981).withOpacity(0.1)
                      : const Color(0xFFF59E0B).withOpacity(0.1),
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
                'Paid',
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
                '₱${paidAmt.toStringAsFixed(0)} / ₱${(paidAmt + pendingAmt).toStringAsFixed(0)}',
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
                  onPressed: () => _showPaymentStatusSheet(sid, dId),
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
                  onPressed: completed
                      ? null
                      : () => _triggerPaymentCollection(sid, dId),
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

  Widget _buildCountChip(IconData icon, String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$label $count',
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
        .from('death_notices')
        .select('id, name, date_of_death')
        .inFilter('dayung_unit_id', ids)
        .order('date_of_death', ascending: false);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                _modalBackButton(ctx, label: "Close"),
                Text(
                  paid
                      ? 'Paid Members per Deceased'
                      : 'Unpaid Members per Deceased',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kPrimaryDark,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: notices.isEmpty
                      ? const Center(child: Text('No death notices found'))
                      : ListView.separated(
                          itemCount: notices.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final n = notices[i];
                            final deceasedName = (n['name'] ?? 'Deceased')
                                .toString();
                            final date = (n['date_of_death'] ?? '').toString();
                            return ListTile(
                              leading: const Icon(
                                Icons.person_off,
                                color: kDanger,
                              ),
                              title: Text(deceasedName),
                              subtitle: Text(date),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.pop(ctx);
                                _showMembersPerDeathNotice(
                                  deathNoticeId: n['id'],
                                  deceasedName: deceasedName,
                                  paid: paid,
                                );
                              },
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
          .select('user_id,status')
          .eq('death_notice_id', deathNoticeId)
          .eq('dayung_unit_id', ids.first)
          .eq('status', paid ? 'paid' : 'pending');

      final userIds = <String>{
        for (final r in List<Map<String, dynamic>>.from(rows))
          (r['user_id'] ?? '').toString(),
      }..removeWhere((e) => e.isEmpty);

      List<Map<String, dynamic>> users = [];
      if (userIds.isNotEmpty) {
        final res = await sb
            .from('users')
            .select('id, full_name')
            .inFilter('id', userIds.toList())
            .order('full_name', ascending: true);
        users = List<Map<String, dynamic>>.from(res);
      }

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                  _modalBackButton(
                    ctx,
                    onBack: () {
                      _showMembersModal(paid: paid);
                    },
                  ),
                  Text(
                    '${paid ? "Paid" : "Unpaid"} Members for',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: kPrimaryDark,
                    ),
                  ),
                  Text(
                    deceasedName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: kDanger,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: users.isEmpty
                        ? const Center(child: Text('No members found'))
                        : ListView.separated(
                            itemCount: users.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final u = users[i];
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: paid
                                      ? Colors.green.withOpacity(.12)
                                      : Colors.red.withOpacity(.12),
                                  child: Icon(
                                    paid
                                        ? Icons.verified_rounded
                                        : Icons.pending_actions_rounded,
                                    color: paid
                                        ? Colors.green[700]
                                        : Colors.red[700],
                                  ),
                                ),
                                title: Text(
                                  (u['full_name'] ?? 'Member').toString(),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  (u['id'] ?? '').toString(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: kSubtleText,
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load members: $e')));
    }
  }

  Widget _modalBackButton(
    BuildContext context, {
    String label = "Back",
    VoidCallback? onBack,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pop();
              if (onBack != null) onBack();
            },
            tooltip: label,
          ),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: kPrimaryDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tripleCards() {
    final cards = <Widget>[
      _statCard(
        color: const Color(0xFFD8EEFF),
        icon: Icons.groups,
        iconColor: Colors.blue[700],
        title: "Total Members",
        bigText: _loading ? '—' : _activeMembers.toString(),
      ),
      _recentDeathsCard(),
      _statCard(
        color: const Color(0xFFFEFBDC),
        icon: Icons.account_balance_wallet,
        iconColor: Colors.orange[700],
        title: "Pending\nPayments",
        bigText: _loading ? '—' : '₱ ${_pendingAmount.toStringAsFixed(0)}',
        smallSubtitle: _loading
            ? ''
            : (_pendingMembers > 0 ? 'From $_pendingMembers' : 'All settled'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 360) {
          return Column(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i != cards.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }
        return Row(
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

  Widget _recentDeathsCard() {
    final names = _recentDeaths;
    final display = names.take(2).toList();
    final extra = names.length - display.length;

    return _statShell(
      color: const Color(0xFFFFDAF6),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.center, // <-- Center horizontally
        children: [
          Icon(FontAwesomeIcons.dove, size: 30, color: Colors.purple[400]),
          const SizedBox(height: 8),
          const Text(
            "Recent Death Notices",
            textAlign: TextAlign.center, // <-- Center text
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              fontFamily: 'Montserrat',
              color: kNeutralText,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: names.isEmpty
                ? const Center(
                    child: Text(
                      "None",
                      textAlign: TextAlign.center, // <-- Center text
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        fontFamily: 'Montserrat',
                        color: kNeutralText,
                      ),
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final n in display)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center, // <-- Center row
                            children: [
                              const Icon(
                                FontAwesomeIcons.dove,
                                size: 14,
                                color: Colors.black87,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  n,
                                  textAlign:
                                      TextAlign.center, // <-- Center text
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    fontFamily: 'Montserrat',
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (extra > 0)
                        Text(
                          'View All',
                          textAlign: TextAlign.center, // <-- Center text
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'OpenSans',
                            color: Colors.blue[700],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required Color color,
    required IconData icon,
    required Color? iconColor,
    required String title,
    required String bigText,
    String smallSubtitle = '',
  }) {
    return _statShell(
      color: color,
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.center, // <-- Center horizontally
        children: [
          Icon(icon, size: 32, color: iconColor),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center, // <-- Center text
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              fontFamily: 'Montserrat',
              color: kNeutralText,
              height: 1.15,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      bigText,
                      textAlign: TextAlign.center, // <-- Center text
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 32,
                        fontFamily: 'Montserrat',
                        color: kNeutralText,
                      ),
                    ),
                  ),
                  if (smallSubtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      smallSubtitle,
                      textAlign: TextAlign.center, // <-- Center text
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'OpenSans',
                        color: kSubtleText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statShell({required Color color, required Widget child}) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300, width: 2),
      ),
      child: child,
    );
  }

  Widget _primaryAction(String label, IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 26, color: kPrimary),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'Montserrat',
              color: kPrimaryDark,
            ),
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size.fromHeight(60),
          side: const BorderSide(color: kPrimary, width: 1.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _collectedPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F8D9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kAccent.withOpacity(.35)),
      ),
      child: Column(
        children: [
          const Text(
            'Collected from the Collectors',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'Montserrat',
              color: kNeutralText,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 160,
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CollectedFromCollectorsPage(
                      dayungUnitId: _dayungUnitId!,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'View',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
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

      // Fallback: if some collector names are missing from the embed, fetch them by ID
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

      // Sort client-side by payer full_name
      items.sort((a, b) {
        final an = (((a['user'] as Map?)?['full_name']) ?? '')
            .toString()
            .toLowerCase();
        final bn = (((b['user'] as Map?)?['full_name']) ?? '')
            .toString()
            .toLowerCase();
        if (an.isEmpty && bn.isEmpty) return 0;
        if (an.isEmpty) return 1;
        if (bn.isEmpty) return -1;
        return an.compareTo(bn);
      });

      int paid = 0, unpaid = 0;
      double paidAmt = 0, totalAmt = 0;
      for (final r in items) {
        final s = (r['status'] ?? '').toString().toLowerCase();
        final amt = (r['amount'] is num)
            ? (r['amount'] as num).toDouble()
            : double.tryParse('${r['amount']}') ?? 0.0;
        totalAmt += amt;
        if (s == 'paid') {
          paid++;
          paidAmt += amt;
        } else {
          unpaid++;
        }
      }

      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ...existing code...
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 460),
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Colors.grey.shade300),
                        itemBuilder: (_, i) {
                          final r = items[i];
                          final s = (r['status'] ?? '')
                              .toString()
                              .toLowerCase();
                          final amt = (r['amount'] is num)
                              ? (r['amount'] as num).toDouble()
                              : double.tryParse('${r['amount']}') ?? 0.0;

                          final payerName =
                              (((r['user'] as Map?)?['full_name']) ?? '')
                                  .toString();
                          final title = payerName.isNotEmpty
                              ? payerName
                              : 'Payment #${r['id']}';

                          final paidAtStr = _fmtDateTime(r['paid_at']);
                          // Prefer embed; fallback to lookup by collected_by
                          String collectorName =
                              (((r['collector'] as Map?)?['full_name']) ?? '')
                                  .toString();
                          if (collectorName.isEmpty &&
                              (r['collected_by'] ?? '').toString().isNotEmpty) {
                            collectorName =
                                collectorLookup[(r['collected_by'])
                                    .toString()] ??
                                '';
                          }
                          final subtitleText = s == 'paid'
                              ? 'Collected'
                                    '${paidAtStr.isNotEmpty ? ' on: $paidAtStr' : ''}'
                                    '${collectorName.isNotEmpty ? '\nCollected by: $collectorName' : ''}'
                              : 'Pending';

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: s == 'paid'
                                  ? Colors.green.withOpacity(.15)
                                  : Colors.orange.withOpacity(.15),
                              child: Icon(
                                s == 'paid'
                                    ? Icons.check
                                    : Icons.hourglass_empty,
                                color: s == 'paid'
                                    ? Colors.green[800]
                                    : Colors.orange[800],
                              ),
                            ),
                            title: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: kNeutralText,
                              ),
                            ),
                            subtitle: Text(
                              subtitleText,
                              style: const TextStyle(color: kSubtleText),
                            ),
                            trailing: Text(
                              '₱${amt.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: kNeutralText,
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
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load payments: $e')));
    }
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

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(.95),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final selected = _tab == index;
    return TextButton(
      onPressed: () => setState(() => _tab = index),
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

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? tooltip,
    String? badge,
  }) {
    return Semantics(
      label: tooltip,
      button: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
          ),
          if (badge != null)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: kDanger,
                  borderRadius: BorderRadius.circular(10),
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
      ),
    );
  }
}
