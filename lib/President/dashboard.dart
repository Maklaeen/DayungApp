import 'dart:convert';

import 'package:capstone_app/Auth/logout.dart';
import 'package:capstone_app/Beneficiary/beneficiary.dart' hide kPrimary;
import 'package:capstone_app/President/manage_roles.dart';
import 'package:capstone_app/President/president_payment_page.dart';
import 'package:capstone_app/President/post_announcement.dart';
import 'package:capstone_app/President/presclaims.dart';
import 'package:capstone_app/President/prescontribution.dart';
import 'package:capstone_app/President/presidentmemberspage.dart'
    hide kPrimary, kNeutralText;
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/pages/recentdeathnotices.dart';
import 'package:capstone_app/settings/profsettings.dart' hide kPrimary;
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:fl_chart/fl_chart.dart';

// Palette aligned with Secretary
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimaryLight = Color(0xFF3B82F6);
const kAccentDark = Color(0xFF059669);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);
const kNeutralText = Color(0xFF111827);
const kBg = Color(0xFFFAFAF7);
const kPrimaryDark = Color(0xFF083366);
const kAccent = Color(0xFF0D47A1);

const double kEdge = 16;

class PresidentDashboardPage extends StatefulWidget {
  const PresidentDashboardPage({super.key});

  @override
  State<PresidentDashboardPage> createState() => _PresidentDashboardPageState();
}

class _PresidentDashboardPageState extends State<PresidentDashboardPage> {
  final _sb = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();
  int? _lastRoleUnitId;
  bool _loading = true;
  int _activeMembersCount = 0;
  List<String> _recentDeaths = [];
  int _pendingMembers = 0;
  num _pendingAmount = 0;
  Map<String, dynamic>? _latestAnnouncement;
  bool _loadingAnnouncement = true;
  int _currentIndex = 0;
  bool _showNavBar = true;
  int? _dayungUnitId;
  List<int> _managedUnitIds = [];
  int? get _primaryUnitId =>
      _managedUnitIds.isNotEmpty ? _managedUnitIds.first : null;
  String _fullName = '';
  String _selectedDayungUnit = 'Dayung Unit';

  @override
  void initState() {
    super.initState();
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
    _initLoad();
    _load();
  }

  void _maybeOnProviderUnitChanged(int? newUnitId) async {
    if (newUnitId == null || newUnitId == _lastRoleUnitId) return;
    _lastRoleUnitId = newUnitId;
    setState(() => _dayungUnitId = newUnitId);
    await _loadPresidentInfo();
    await _load();
  }

  Future<void> _initLoad() async {
    await _loadPresidentInfo();
    await Future.wait([
      _fetchActiveMembersCount(_managedUnitIds),
      _fetchRecentDeaths(_managedUnitIds),
      _fetchPendingPayments(_managedUnitIds),
      _fetchLatestAnnouncement(_managedUnitIds),
    ]);
  }

  Future<void> _loadPresidentInfo() async {
    final prefs = await SharedPreferences.getInstance();
    String name = prefs.getString('presidentFullName') ?? 'President';
    String dayungLabelRaw =
        prefs.getString('selectedDayungUnit') ?? 'Dayung Unit';
    int? unitId;
    String? jsonFull = prefs.getString('selectedDayungUnitData');
    Map<String, dynamic>? parsed;
    try {
      if (jsonFull != null) {
        parsed = jsonDecode(jsonFull);
      }
    } catch (_) {}
    if (parsed == null &&
        dayungLabelRaw.trim().startsWith('{') &&
        dayungLabelRaw.contains('"name"')) {
      try {
        parsed = jsonDecode(dayungLabelRaw);
      } catch (_) {}
    }
    String resolvedLabel = dayungLabelRaw;
    if (parsed != null) {
      if (parsed['id'] != null) {
        unitId = int.tryParse(parsed['id'].toString());
      }
      if ((parsed['name'] ?? '').toString().trim().isNotEmpty) {
        resolvedLabel = parsed['name'].toString();
      }
    }
    setState(() {
      _fullName = name;
      _selectedDayungUnit = resolvedLabel;
      _dayungUnitId = unitId ?? _dayungUnitId ?? 1;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadingAnnouncement = true;
    });
    try {
      final ids = await _managedDayungIds();
      _managedUnitIds = ids;
      if (ids.isEmpty) {
        // No units to manage, stop loading and show placeholder
        if (mounted) {
          setState(() {
            _loading = false;
            _loadingAnnouncement = false;
          });
        }
        return;
      }
      await Future.wait([
        _fetchActiveMembersCount(ids),
        _fetchRecentDeaths(ids),
        _fetchPendingPayments(ids),
        _fetchLatestAnnouncement(ids),
      ]);
    } catch (e) {
      // Always set loading to false on error
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingAnnouncement = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingAnnouncement = false;
        });
      }
    }
  }

  Future<void> _fetchLatestAnnouncement(List<int> unitIds) async {
    _latestAnnouncement = null;
    if (unitIds.isEmpty) return;
    final rows = await _sb
        .from('announcements')
        .select('id, title, body, created_at')
        .inFilter('dayung_unit_id', unitIds)
        .order('created_at', ascending: false)
        .limit(1);
    final list = List<Map<String, dynamic>>.from(rows);
    if (list.isNotEmpty) {
      _latestAnnouncement = list.first;
    }
  }

  Future<List<int>> _managedDayungIds() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return <int>[];

    final rows = await _sb
        .from('dayung_units')
        .select('id')
        .eq('president_id', uid)
        .order('id');

    return List<Map<String, dynamic>>.from(
      rows,
    ).map((e) => e['id'] as int).toList();
  }

  // No filepath: utility snippet
  Future<void> addCollector({
    required int dayungUnitId,
    required String userId,
  }) async {
    await Supabase.instance.client.from('dayung_collectors').insert({
      'dayung_unit_id': dayungUnitId,
      'user_id': userId,
      'added_by': Supabase.instance.client.auth.currentUser?.id,
    });
  }

  Future<void> removeCollector({
    required int dayungUnitId,
    required String userId,
  }) async {
    await Supabase.instance.client.from('dayung_collectors').delete().match({
      'dayung_unit_id': dayungUnitId,
      'user_id': userId,
    });
  }

  Future<List<Map<String, dynamic>>> listCollectors(int dayungUnitId) async {
    final rows = await Supabase.instance.client
        .from('dayung_collectors')
        .select('user_id')
        .eq('dayung_unit_id', dayungUnitId);
    final ids = List<Map<String, dynamic>>.from(
      rows,
    ).map((r) => (r['user_id'] as String)).toList();
    if (ids.isEmpty) return [];
    final users = await Supabase.instance.client
        .from('users')
        .select('id, full_name, mobile_number')
        .inFilter('id', ids);
    return List<Map<String, dynamic>>.from(users);
  }

  Future<void> _fetchActiveMembersCount(List<int> ids) async {
    if (ids.isEmpty) {
      _activeMembersCount = 0;
      return;
    }
    final apps = await _sb
        .from('applications')
        .select('user_id')
        .inFilter('dayung_unit_id', ids)
        .eq('status', 'approved');
    final userIds = <String>{};
    for (final r in List<Map<String, dynamic>>.from(apps)) {
      final id = (r['user_id'] ?? '').toString();
      if (id.isNotEmpty) userIds.add(id);
    }
    if (userIds.isEmpty) {
      _activeMembersCount = 0;
      return;
    }
    final users = await _sb
        .from('users')
        .select('id,is_deceased')
        .inFilter('id', userIds.toList());
    final alive = List<Map<String, dynamic>>.from(users)
        .where((u) => (u['is_deceased'] ?? false) == false)
        .map((u) => u['id'].toString())
        .toSet();
    _activeMembersCount = alive.length;
  }

  Future<void> _fetchRecentDeaths(List<int> ids) async {
    if (ids.isEmpty) {
      _recentDeaths = [];
      return;
    }
    final rows = await _sb
        .from('death_notices')
        .select('name')
        .inFilter('dayung_unit_id', ids)
        .order('date_of_death', ascending: false)
        .limit(2);
    _recentDeaths = List<Map<String, dynamic>>.from(
      rows,
    ).map((e) => (e['name'] ?? 'Member') as String).toList();
  }

  Future<void> _fetchPendingPayments(List<int> ids) async {
    _pendingMembers = 0;
    _pendingAmount = 0;
  }

  List<Widget> get _pages => [
    _buildHomePage(context),
    if (_primaryUnitId == null)
      const Center()
    else
      PresidentContributionsPage(dayungUnitId: _primaryUnitId!),
    if (_primaryUnitId == null)
      const SizedBox.shrink()
    else
      PresidentClaimsPage(dayungUnitId: _primaryUnitId!),
  ];

  @override
  Widget build(BuildContext context) {
    final provUnit = context.watch<DayungRoleProvider>().unitId;
    if (provUnit != _lastRoleUnitId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeOnProviderUnitChanged(provUnit);
      });
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeBg = isDark ? const Color(0xFF18181B) : const Color(0xFFF8FAFC);
    final wide = MediaQuery.of(context).size.width > 820;

    return Scaffold(
      backgroundColor: themeBg,
      drawer: _buildSideDrawer(context),
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
                Text(
                  _selectedDayungUnit,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 15,
                    fontFamily: 'OpenSans',
                  ),
                ),
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
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationPage(),
                      ),
                    );
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
                    const Text(
                      'Dayung',
                      style: TextStyle(
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
                  'Good Morning,\nPresident!',
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
              //   onTap: () async {
              //     final prevUnitId = context
              //         .read<DayungUnitProvider>()
              //         .currentUnitId;
              //     await Navigator.push(
              //       context,
              //       MaterialPageRoute(builder: (_) => const ProfilePage()),
              //     );
              //     if (!mounted) return;
              //     final newUnitId = context
              //         .read<DayungUnitProvider>()
              //         .currentUnitId;
              //     if (prevUnitId != newUnitId) {
              //       context.read<DayungRoleProvider>().refreshRoles(newUnitId);
              //     }
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
          child: RefreshIndicator(
            onRefresh: _load, // or your refresh method
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
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
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

  /* ------------------------------- Home page ------------------------------- */
  Widget _buildHomePage(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      edgeOffset: 68,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildModernStatsCards(),
            const SizedBox(height: 24),
            _buildQuickActions(),
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
            color: Colors.black.withValues(alpha: 0.05),
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
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1,
            children: [
              _buildModernStatCard(
                icon: Icons.groups_rounded,
                title: 'Active Members',
                value: _loading ? '—' : _activeMembersCount.toString(),
                color: const Color(0xFF3B82F6),
                bgColor: const Color(0xFFEFF6FF),
                onTap: () async {
                  final ids = await _managedDayungIds();
                  if (!mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PresidentMembersPage(dayungUnitIds: ids),
                    ),
                  );
                },
              ),
              _buildModernStatCard(
                icon: Icons.account_balance_wallet_rounded,
                title: 'Pending Amount',
                value: _loading ? '—' : '₱${_pendingAmount.toStringAsFixed(0)}',
                subtitle: _loading ? '' : 'From $_pendingMembers members',
                color: const Color(0xFFF59E0B),
                bgColor: const Color(0xFFFEF3C7),
              ),
              _buildOverviewRecentDeathsTile(),
              _buildOverviewManageRolesTile(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewRecentDeathsTile() {
    final hasDeaths = _recentDeaths.isNotEmpty;
    final subtitle = hasDeaths ? _recentDeaths.take(2).join(', ') : 'None';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        final roleProv = context.read<DayungRoleProvider>();
        final unitProv = context.read<DayungUnitProvider>();
        final effId = roleProv.unitId ?? unitProv.currentUnitId;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RecentDeathNotices(dayungUnitId: effId),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFDF2F8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFEC4899).withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Center vertically
          crossAxisAlignment: CrossAxisAlignment.center, // Center horizontally
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEC4899).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.local_florist_rounded,
                color: Color(0xFFEC4899),
                size: 20,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Recent Deaths',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFFEC4899),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9F1239),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewManageRolesTile() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ManageRolesPagePres()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Center vertically
          crossAxisAlignment: CrossAxisAlignment.center, // Center horizontally
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.manage_accounts_rounded,
                color: Color(0xFF3B82F6),
                size: 22,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Manage Roles',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1F2937),
                fontFamily: 'Montserrat',
              ),
            ),
            const SizedBox(height: 2),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: Color(0xFF3B82F6).withValues(alpha: 0.7),
            ),
          ],
        ),
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
        const _PostAnnouncementButton(),
        const SizedBox(height: 18),
        _payContributionButton(context),
        const SizedBox(height: 12),
        _UpcomingAnnouncementCard(
          loading: _loadingAnnouncement,
          announcement: _latestAnnouncement,
        ),
        const SizedBox(height: 12),
        const _ContributionBarChartCard(),
      ],
    );
  }

  Widget _payContributionButton(BuildContext context) {
    return Material(
      color: kPrimary,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        onTap: () async {
          final navigator = Navigator.of(context);
          final ids = await _managedDayungIds();
          if (ids.isEmpty) return;
          if (!mounted) return;
          navigator.push(
            MaterialPageRoute(
              builder: (context) =>
                  PresidentPaymentPage(dayungUnitId: ids.first),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimary, kPrimaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: kPrimary.withValues(alpha: 0.4),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.payments_rounded, color: Colors.white, size: 24),
              SizedBox(width: 12),
              Text(
                'Pay Contribution',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  color: Colors.white,
                  fontSize: 18.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
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
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: color.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/* ----------------------- POST ANNOUNCEMENT BUTTON ----------------------- */

class _PostAnnouncementButton extends StatelessWidget {
  const _PostAnnouncementButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kPrimary,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PostAnnouncementPage()),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimary, kPrimaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: kPrimary.withValues(alpha: 0.4),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_rounded, color: Colors.white, size: 24),
              SizedBox(width: 12),
              Text(
                'Post Announcement',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  color: Colors.white,
                  fontSize: 18.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ------------------------- SIMPLE BAR CHART CARD ------------------------ */

class _ContributionBarChartCard extends StatefulWidget {
  const _ContributionBarChartCard();

  @override
  State<_ContributionBarChartCard> createState() =>
      _ContributionBarChartCardState();
}

class _ContributionBarChartCardState extends State<_ContributionBarChartCard> {
  Map<String, double> _yearTotals = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<Map<String, double>> fetchYearlyContributions({
    List<int>? unitIds,
  }) async {
    final sb = Supabase.instance.client;

    // Build query: only paid payments, optionally filter by unit
    var query = sb
        .from('payments')
        .select('paid_at, amount')
        .eq('status', 'paid');

    if (unitIds != null && unitIds.isNotEmpty) {
      query = query.inFilter('dayung_unit_id', unitIds);
    }

    final rows = await query;

    // Aggregate by year
    final Map<String, double> yearTotals = {};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final paidAtStr = row['paid_at'] ?? row['created_at'];
      final paidAt = DateTime.tryParse(paidAtStr?.toString() ?? '');
      if (paidAt != null) {
        final year = paidAt.year.toString();
        final amount = double.tryParse(row['amount'].toString()) ?? 0.0;
        yearTotals[year] = (yearTotals[year] ?? 0) + amount;
      }
    }

    return yearTotals;
  }

  Future<void> _loadData() async {
    // Optionally pass unitIds if you want to filter
    final data = await fetchYearlyContributions();
    if (mounted) {
      setState(() {
        _yearTotals = data;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final barLabels = _yearTotals.keys.toList()..sort();
    final barValues = barLabels.map((y) => _yearTotals[y] ?? 0).toList();
    final maxY = barValues.isNotEmpty
        ? (barValues.reduce((a, b) => a > b ? a : b) * 1.2)
        : 25.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: kBorderColor.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.bar_chart_rounded,
                    color: kPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Contribution Records',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kNeutralText,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : barLabels.isEmpty
                  ? const Center(child: Text('No data'))
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: maxY,
                        minY: 0,
                        groupsSpace: 24,
                        barTouchData: BarTouchData(enabled: true),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: ((maxY ~/ 5) > 0
                                  ? (maxY ~/ 5).toDouble()
                                  : 1.0),
                              getTitlesWidget: (value, meta) => Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: Text(
                                  value.toInt().toString(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                return idx >= 0 && idx < barLabels.length
                                    ? Padding(
                                        padding: const EdgeInsets.only(
                                          top: 6.0,
                                        ),
                                        child: Text(
                                          barLabels[idx],
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: kSubText,
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink();
                              },
                            ),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        gridData: FlGridData(
                          show: true,
                          horizontalInterval: ((maxY ~/ 5) > 0
                              ? (maxY ~/ 5).toDouble()
                              : 1.0),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: List.generate(barValues.length, (i) {
                          return BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: barValues[i],
                                color: const Color(0xFF2D63D6),
                                width: 22,
                                borderRadius: BorderRadius.circular(4),
                                backDrawRodData: BackgroundBarChartRodData(
                                  show: true,
                                  toY: maxY,
                                  color: const Color(0xFFE5E7EB),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            const _MiniLegendRow(),
          ],
        ),
      ),
    );
  }
}

class _MiniLegendRow extends StatelessWidget {
  const _MiniLegendRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _dot(const Color(0xFF2D63D6)),
        const SizedBox(width: 6),
        Text(
          'batches',
          style: TextStyle(
            fontFamily: 'OpenSans',
            fontSize: 12,
            color: kSubText,
          ),
        ),
      ],
    );
  }

  Widget _dot(Color c) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
  );
}

class _UpcomingAnnouncementCard extends StatelessWidget {
  final bool loading;
  final Map<String, dynamic>? announcement;

  const _UpcomingAnnouncementCard({
    required this.loading,
    required this.announcement,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (announcement == null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: kCardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: kBorderColor.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.event_rounded, color: kPrimary, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No upcoming announcements.',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 16,
                  height: 1.3,
                  color: kNeutralText,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final title = (announcement!['title'] ?? '').toString();
    final createdAt = announcement!['created_at']?.toString();
    String dateStr = '';
    if (createdAt != null && createdAt.isNotEmpty) {
      final dt = DateTime.tryParse(createdAt);
      if (dt != null) {
        dateStr = '${dt.month}/${dt.day}/${dt.year}';
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: kBorderColor.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.event_rounded, color: kPrimary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 16,
                    height: 1.3,
                    color: kNeutralText,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                if (dateStr.isNotEmpty)
                  Text(
                    dateStr,
                    style: const TextStyle(
                      fontSize: 12,
                      color: kSubText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
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
