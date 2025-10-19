import 'dart:convert';
import 'package:capstone_app/Collector/collect_cash.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/pages/claims.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/pages/recentdeathnotices.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Additional colors for collector-specific styling
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimaryLight = Color(0xFF3B82F6);
const kAccentDark = Color(0xFF059669);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);
const double kEdge = 16;

class CollectorDashboardPage extends StatefulWidget {
  const CollectorDashboardPage({super.key});

  @override
  State<CollectorDashboardPage> createState() => _CollectorDashboardPageState();
}

class _CollectorDashboardPageState extends State<CollectorDashboardPage> {
  final sb = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();

  String _dayungLabel = 'Dayung';
  int? _dayungUnitId;
  int? _lastRoleUnitId;
  bool _loading = true;
  int _activeMembers = 0;
  double _pendingAmount = 0;
  int _pendingMembers = 0;
  List<String> _recentDeaths = [];

  int _tab = 0;
  bool _showNavBar = true;

  @override
  void initState() {
    super.initState();
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

  void _maybeOnProviderUnitChanged(int? newUnitId) {
    if (newUnitId == null || newUnitId == _lastRoleUnitId) return;
    _lastRoleUnitId = newUnitId;
    setState(() => _dayungUnitId = newUnitId);
    // also refresh label from prefs (SelectDayung writes it)
    _loadDayungFromPrefs();
    _fetchAll();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadDayungFromPrefs();
    await _ensureDayungId();
    await _fetchAll();
  }

  Future<void> _ensureDayungId() async {
    if (_dayungUnitId != null) return;
    try {
      final uid = sb.auth.currentUser?.id;
      if (uid == null) return;
      final res = await sb
          .from('users')
          .select('dayung_unit_id')
          .eq('id', uid)
          .maybeSingle();
      final id = res?['dayung_unit_id'];
      if (id != null) {
        setState(() => _dayungUnitId = int.tryParse(id.toString()));
      }
    } catch (_) {
      /* ignore */
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
    setState(() => _loading = true);
    try {
      final managed = await _managedDayungIds();
      await Future.wait([
        _fetchActiveMembers(managed),
        _fetchPendingPayments(managed),
        _fetchRecentDeaths(managed),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<int>> _managedDayungIds() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return <int>[];

    try {
      final rows = await sb
          .from('dayung_collectors')
          .select('dayung_unit_id')
          .eq('user_id', uid);
      final ids = <int>{
        for (final r in List<Map<String, dynamic>>.from(rows))
          if (r['dayung_unit_id'] != null)
            int.tryParse(r['dayung_unit_id'].toString()) ?? -1,
      }..remove(-1);

      if (ids.isNotEmpty) return ids.toList();
    } catch (_) {}

    // Fallback to selected pref (if any)
    if (_dayungUnitId != null) return [_dayungUnitId!];
    return <int>[];
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

      // RPC if available
      try {
        final rpc = await sb.rpc(
          'collector_pending_payments',
          params: {'p_dayung_ids': ids},
        );
        if (rpc is Map && rpc['total_amount'] != null) {
          _pendingAmount = double.tryParse(rpc['total_amount'].toString()) ?? 0;
          _pendingMembers = int.tryParse(rpc['member_count'].toString()) ?? 0;
          return;
        }
      } catch (_) {}

      if (ids.isEmpty) return;
      final rows = await sb
          .from('payments')
          .select('amount, user_id, status, dayung_unit_id');
      final managed = ids.toSet();
      final memberSet = <String>{};
      double total = 0;
      for (final r in rows as List) {
        final m = r as Map<String, dynamic>;
        if ((m['status'] ?? '').toString().toLowerCase() == 'pending') {
          final dId = m['dayung_unit_id'];
          if (dId is int && managed.contains(dId)) {
            total += (m['amount'] is num) ? (m['amount'] as num).toDouble() : 0;
            if (m['user_id'] != null) memberSet.add(m['user_id'].toString());
          }
        }
      }
      _pendingAmount = total;
      _pendingMembers = memberSet.length;
    } catch (_) {
      _pendingAmount = 0;
      _pendingMembers = 0;
    }
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

  List<Widget> get _pages => [
    _homePage(),
    const Placeholder(), // Contributions
    ClaimsPage(onNavBarVisible: (v) => setState(() => _showNavBar = v)),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool wide = width > 820;
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
              child: Column(children: [_topBar(), _buildContentArea(wide)]),
            ),
            _bottomNav(wide),
          ],
        ),
      ),
    );
  }

  /* ------------------------------- UI parts ------------------------------- */

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        children: [
          // Top bar
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
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
                icon: Icons.notifications_rounded,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationPage()),
                ),
                badge: '1',
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Greeting section
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Maayung buntag,\nCollector!',
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
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
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

  // --- Modern Content Area ---
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

  // --- Modern Floating NavBar ---
  Widget _bottomNav(bool wide) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 16,
      child: Center(
        child: IgnorePointer(
          ignoring: !_showNavBar,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: _showNavBar ? 1.0 : 0.0,
            child: Container(
              constraints: const BoxConstraints(minHeight: 80, maxHeight: 90),
              margin: EdgeInsets.symmetric(
                horizontal: wide
                    ? MediaQuery.of(context).size.width * 0.15
                    : 16,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade300, width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _navBarItem(
                      icon: Icons.dashboard_rounded,
                      label: 'Dashboard',
                      selected: _tab == 0,
                      onTap: () => setState(() => _tab = 0),
                    ),
                    _navBarItem(
                      icon: Icons.trending_up_rounded,
                      label: 'Contributions',
                      selected: _tab == 1,
                      onTap: () => setState(() => _tab = 1),
                    ),
                    _navBarItem(
                      icon: Icons.assignment_rounded,
                      label: 'Claims',
                      selected: _tab == 2,
                      onTap: () => setState(() => _tab = 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Modern Icon Button ---
  Widget _iconBtn({
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

  // --- Modern Nav Item ---
  Widget _navBarItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              constraints: const BoxConstraints(minHeight: 60, maxHeight: 70),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF1E40AF).withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: selected
                    ? Border.all(
                        color: const Color(0xFF1E40AF).withValues(alpha: 0.3),
                        width: 1,
                      )
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF1E40AF)
                          : Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFF1E40AF,
                                ).withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      icon,
                      color: selected ? Colors.white : Colors.grey[700],
                      size: 20,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF1E40AF)
                          : Colors.grey[700],
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 12,
                      letterSpacing: 0.2,
                      fontFamily: 'Montserrat',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _homePage() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _overviewSection(),
          const SizedBox(height: 24),
          _modernActionCards(),
          const SizedBox(height: 24),
          _modernRecentActivity(),
          const SizedBox(height: 24),
          _modernQuickActions(),
          const SizedBox(height: 100), // Space for bottom nav
        ],
      ),
    );
  }

  Widget _overviewSection() {
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
                child: InkWell(
                  onTap: () {
                    setState(() => _tab = 2);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 180,
                    child: _modernStatCard(
                      icon: Icons.groups_rounded,
                      title: 'Active Members',
                      value: _loading ? '—' : _activeMembers.toString(),
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
                    child: _recentDeathsCard(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() => _tab = 1);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 180,
                    child: _modernStatCard(
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
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modernStatCard({
    required IconData icon,
    required String title,
    required String value,
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
        crossAxisAlignment: CrossAxisAlignment.center,
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
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color.withOpacity(0.8),
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

  Widget _recentDeathsCard() {
    final names = _recentDeaths;
    final display = names.take(2).toList();
    final extra = names.length - display.length;

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
          if (extra > 0)
            Text(
              'View All',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                fontFamily: 'OpenSans',
                color: Colors.blue[700],
              ),
            ),
        ],
      ),
    );
  }

  // ...existing code...

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
        _modernActionCard(
          icon: Icons.account_balance_wallet_rounded,
          title: 'Collect Cash',
          subtitle: 'Record cash payment',
          color: const Color(0xFF3B82F6),
          onTap: _recordCashPayment,
        ),
        const SizedBox(height: 8),
        _modernActionCard(
          icon: Icons.receipt_long_rounded,
          title: 'Show Receipts',
          subtitle: 'View payment receipts',
          color: const Color(0xFF10B981),
          onTap: _showReceipts,
        ),
        const SizedBox(height: 8),
        _modernActionCard(
          icon: Icons.qr_code_2_rounded,
          title: 'Open GCash QR',
          subtitle: 'Show payment QR',
          color: const Color(0xFFF59E0B),
          onTap: _openGcashQr,
        ),
        // Add more actions as needed, following the Treasurer's style
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

  // ...existing code...
  Widget _modernRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Recent Activity",
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
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.payment_rounded,
                      color: Color(0xFF3B82F6),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Collection Activity",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _ActivityRow(
                icon: Icons.calendar_today,
                color: Color(0xFF3B82F6),
                text: 'Jun 15    Contribution received     +₱ 23,000',
              ),
              const SizedBox(height: 12),
              const _ActivityRow(
                icon: Icons.handshake,
                color: Color(0xFF10B981),
                text: 'May 15   Assistance Received',
              ),
              const SizedBox(height: 12),
              const _ActivityRow(
                icon: Icons.calendar_today,
                color: Color(0xFF3B82F6),
                text: 'Apr 15    Contribution received     +₱ 23,000',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _modernQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Quick Access",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _modernQuickActionCard(
                icon: Icons.info_outline_rounded,
                title: "Collection Tips",
                color: const Color(0xFF3B82F6),
                onTap: () {
                  // Keep existing functionality
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _modernQuickActionCard(
                icon: Icons.analytics_rounded,
                title: "View Reports",
                color: const Color(0xFFF59E0B),
                onTap: () {
                  // TODO: Add reports functionality
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _modernQuickActionCard({
    required IconData icon,
    required String title,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontFamily: 'Montserrat',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openGcashQr() {
    // TODO: integrate actual QR view
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Open GCASH QR (coming soon)')),
    );
  }

  void _recordCashPayment() {
    if (_dayungUnitId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No dayung selected.')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CollectCashPage(dayungUnitId: _dayungUnitId!),
      ),
    );
  }

  void _showReceipts() {
    // TODO: open receipts page
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Show Receipts (coming soon)')),
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
