import 'dart:convert';

import 'package:capstone_app/shared/pres_sec_dashboard_overview.dart';
import 'package:capstone_app/shared/collector_progress_page.dart';
import 'package:capstone_app/President/manage_roles.dart';
import 'package:capstone_app/President/president_payment_page.dart';
import 'package:capstone_app/President/post_announcement.dart';
import 'package:capstone_app/President/presclaims.dart' hide kPrimary;
import 'package:capstone_app/President/prescontribution.dart' hide kPrimary;
import 'package:capstone_app/President/presidentmemberspage.dart'
    hide kPrimary, kNeutralText;
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/pages/recentdeathnotices.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/pages/notification.dart';
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
  int _unreadNotifCount = 0;
  Map<String, dynamic>? _latestAnnouncement;
  bool _loadingAnnouncement = true;
  int _currentIndex = 0;
  bool _showNavBar = true;
  int? _dayungUnitId;
  List<int> _managedUnitIds = [];
  int? get _primaryUnitId =>
      _managedUnitIds.isNotEmpty ? _managedUnitIds.first : null;
  int? _effectiveUnitId(BuildContext context) {
    final roleUnitId = context.read<DayungRoleProvider>().unitId;
    final selectedUnitId = context.read<DayungUnitProvider>().currentUnitId;
    return roleUnitId ?? selectedUnitId ?? _dayungUnitId ?? _primaryUnitId;
  }

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
      _fetchUnreadNotifCount(_managedUnitIds),
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
        _fetchUnreadNotifCount(ids),
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

    final ids = List<Map<String, dynamic>>.from(
      rows,
    ).map((e) => e['id'] as int).toList();
    if (ids.isNotEmpty) return ids;
    if (_dayungUnitId != null) return [_dayungUnitId!];
    return <int>[];
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
    final deaths = await _sb
        .from('death_notices')
        .select('user_id, deceased_type')
        .inFilter('user_id', userIds.toList())
        .or('deceased_type.is.null,deceased_type.eq.member');
    final deceasedIds = <String>{
      for (final row in List<Map<String, dynamic>>.from(deaths))
        if ((row['user_id'] ?? '').toString().isNotEmpty)
          row['user_id'].toString(),
    };
    _activeMembersCount = userIds
        .where((id) => !deceasedIds.contains(id))
        .length;
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

    if (ids.isEmpty) return;

    final rows = await _sb
        .from('payments')
        .select('user_id, amount, status')
        .inFilter('dayung_unit_id', ids);

    final memberIds = <String>{};
    double total = 0;
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final status = (row['status'] ?? '').toString().toLowerCase();
      if (status == 'paid') continue;

      final userId = (row['user_id'] ?? '').toString();
      if (userId.isNotEmpty) memberIds.add(userId);

      final amount = row['amount'];
      if (amount is num) {
        total += amount.toDouble();
      } else {
        total += double.tryParse('$amount') ?? 0;
      }
    }

    _pendingMembers = memberIds.length;
    _pendingAmount = total;
  }

  Future<void> _fetchUnreadNotifCount(List<int> ids) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      _unreadNotifCount = 0;
      return;
    }

    try {
      final notifRows = await _sb
          .from('notifications')
          .select('id')
          .eq('recipient_id', uid)
          .isFilter('read_at', null);
      int unread = (notifRows as List).length;

      if (ids.isNotEmpty) {
        final annRows = await _sb
            .from('announcements')
            .select('id')
            .inFilter('dayung_unit_id', ids);
        final annIds = (annRows as List)
            .map((row) => (row as Map)['id'])
            .whereType<int>()
            .toList();

        if (annIds.isNotEmpty) {
          final reads = await _sb
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

        final appRows = await _sb
            .from('dayung_application_notifications')
            .select('id')
            .inFilter('dayung_unit_id', ids)
            .eq('seen', false);
        unread += (appRows as List).length;
      }

      _unreadNotifCount = unread;
    } catch (_) {
      _unreadNotifCount = 0;
    }
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
    final width = MediaQuery.of(context).size.width;
    final provUnit = context.watch<DayungRoleProvider>().unitId;
    if (provUnit != _lastRoleUnitId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeOnProviderUnitChanged(provUnit);
      });
    }

    final wide = width > 820;

    return Container(
      decoration: BoxDecoration(gradient: dayungDashboardGradient(context)),
      child: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildModernHeader(showMenuButton: true),
                _buildContentArea(wide),
              ],
            ),
          ),
          _buildFloatingNavBar(wide),
        ],
      ),
    );
  }

  Widget _buildModernHeader({bool showMenuButton = true}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        children: [
          Row(
            children: [
              if (showMenuButton)
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
              if (showMenuButton) const SizedBox(width: 16),
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
                ).then((_) => _load()),
                badge: _unreadNotifCount > 0 ? '$_unreadNotifCount' : null,
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
    final dashboardUnitId = _effectiveUnitId(context);

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── New shared overview (Row 1 stats, Row 2 chart, Row 3 collections) ──
          if (dashboardUnitId != null)
            PresSecDashboardOverview(
              key: ValueKey(dashboardUnitId),
              dayungUnitId: dashboardUnitId,
              onNavigateToMembers: () async {
                final navigator = Navigator.of(context);
                final ids = await _managedDayungIds();
                if (!mounted) return;
                navigator.push(
                  MaterialPageRoute(
                    builder: (_) => PresidentMembersPage(dayungUnitIds: ids),
                  ),
                );
              },
              onNavigateToDeceased: () {
                final effectiveUnitId = _effectiveUnitId(context);
                if (effectiveUnitId == null) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        RecentDeathNotices(dayungUnitId: effectiveUnitId),
                  ),
                );
              },
            ),
          const SizedBox(height: 24),
          _buildQuickActions(),
        ],
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
        decoration: dayungAccentCardDecoration(
          context,
          accent: const Color(0xFFEC4899),
          lightAlpha: 0.08,
          darkAlpha: 0.14,
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
          color: dayungSurface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: dayungBorder(context)),
          boxShadow: [dayungElevatedShadow(context)],
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
                  child: _modernActionCard(
                    icon: Icons.campaign_rounded,
                    title: 'Post Announcement',
                    subtitle: 'Notify members',
                    color: const Color(0xFF3B82F6),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PostAnnouncementPage(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 140,
                  child: _modernActionCard(
                    icon: Icons.payments_rounded,
                    title: 'Pay Contribution',
                    subtitle: 'Pay your dues',
                    color: const Color(0xFF10B981),
                    onTap: () async {
                      final ids = await _managedDayungIds();
                      if (ids.isEmpty || !mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PresidentPaymentPage(dayungUnitId: ids.first),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 140,
                  child: _modernActionCard(
                    icon: Icons.manage_accounts_rounded,
                    title: 'Manage Roles',
                    subtitle: 'Assign officers',
                    color: const Color(0xFF8B5CF6),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ManageRolesPagePres(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: _modernActionCard(
              icon: Icons.bar_chart_rounded,
              title: 'Collector Progress',
              subtitle: 'View collection status',
              color: const Color(0xFF8B5CF6),
              onTap: () {
                final unitId = _effectiveUnitId(context);
                if (unitId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Select a Dayung first')),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CollectorProgressPage(dayungUnitId: unitId),
                  ),
                );
              },
            ),
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
                  child: _modernActionCard(
                    icon: Icons.bar_chart_rounded,
                    title: 'Contributions',
                    subtitle: 'View records',
                    color: kPrimary,
                    onTap: () => setState(() => _currentIndex = 1),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 110,
                  child: _modernActionCard(
                    icon: Icons.assignment_rounded,
                    title: 'Claims',
                    subtitle: 'View claims',
                    color: const Color(0xFFEF4444),
                    onTap: () => setState(() => _currentIndex = 2),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: SizedBox()),
            ],
          ),
          const SizedBox(height: 16),
          _UpcomingAnnouncementCard(
            loading: _loadingAnnouncement,
            announcement: _latestAnnouncement,
          ),
          const SizedBox(height: 16),
          _ContributionBarChartCard(dayungUnitIds: _managedUnitIds),
        ],
      ),
    );
  }

  Widget _modernActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
    int badgeCount = 0,
  }) {
    final isCompact = MediaQuery.of(context).size.width < 360;
    final titleFontSize = isCompact ? 12.0 : 14.0;
    final subtitleFontSize = isCompact ? 10.0 : 12.0;
    final contentGap = isCompact ? 6.0 : 8.0;

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
            child: Stack(
              children: [
                Column(
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
                    SizedBox(height: contentGap),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Flexible(
                      child: Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: subtitleFontSize,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontFamily: 'OpenSans',
                        ),
                      ),
                    ),
                  ],
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          fontSize: 11,
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
        decoration: dayungAccentCardDecoration(
          context,
          accent: color,
          lightAlpha: 0.10,
          darkAlpha: 0.16,
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

/* ------------------------- SIMPLE BAR CHART CARD ------------------------ */

class _ContributionBarChartCard extends StatefulWidget {
  final List<int> dayungUnitIds;

  const _ContributionBarChartCard({required this.dayungUnitIds});

  @override
  State<_ContributionBarChartCard> createState() =>
      _ContributionBarChartCardState();
}

class _ContributionBarChartCardState extends State<_ContributionBarChartCard> {
  Map<String, double> _yearTotals = {};
  bool _loading = true;
  double _totalAmount = 0;
  int _recordCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant _ContributionBarChartCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameIds(oldWidget.dayungUnitIds, widget.dayungUnitIds)) {
      _loadData();
    }
  }

  bool _sameIds(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  Future<Map<String, double>> fetchYearlyContributions({
    List<int>? unitIds,
  }) async {
    final sb = Supabase.instance.client;

    if (unitIds == null || unitIds.isEmpty) {
      _recordCount = 0;
      _totalAmount = 0;
      return <String, double>{};
    }

    final rows = await sb
        .from('payments')
        .select('paid_at, created_at, amount, dayung_unit_id, status')
        .inFilter('dayung_unit_id', unitIds)
        .eq('status', 'paid');

    final Map<String, double> yearTotals = {};
    var totalAmount = 0.0;
    var recordCount = 0;

    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final paidAtStr = row['paid_at'] ?? row['created_at'];
      final paidAt = DateTime.tryParse(paidAtStr?.toString() ?? '');
      final amount = double.tryParse(row['amount'].toString()) ?? 0.0;
      if (paidAt != null) {
        final year = paidAt.year.toString();
        yearTotals[year] = (yearTotals[year] ?? 0) + amount;
        totalAmount += amount;
        recordCount++;
      }
    }

    _totalAmount = totalAmount;
    _recordCount = recordCount;

    return yearTotals;
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final data = await fetchYearlyContributions(unitIds: widget.dayungUnitIds);
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
    final hasUnits = widget.dayungUnitIds.isNotEmpty;

    return Container(
      decoration: dayungSectionCardDecoration(context, radius: 22),
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
            const SizedBox(height: 8),
            Text(
              hasUnits
                  ? 'Paid contributions across your managed Dayung members and officers.'
                  : 'No managed Dayung units available yet.',
              style: const TextStyle(
                fontFamily: 'OpenSans',
                fontSize: 13,
                color: kSubText,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: dayungSoftSurface(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: dayungBorder(context)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _ChartStat(
                      label: 'Records',
                      value: _recordCount.toString(),
                    ),
                  ),
                  Container(width: 1, height: 36, color: kBorderColor),
                  Expanded(
                    child: _ChartStat(
                      label: 'Total Paid',
                      value: '₱${_totalAmount.toStringAsFixed(0)}',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : !hasUnits
                  ? const Center(child: Text('No managed Dayung units found.'))
                  : barLabels.isEmpty
                  ? const Center(
                      child: Text('No paid contributions found yet.'),
                    )
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

class _ChartStat extends StatelessWidget {
  final String label;
  final String value;

  const _ChartStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: kNeutralText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'OpenSans',
            fontSize: 12,
            color: kSubText,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
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
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (announcement == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: dayungSectionCardDecoration(context, radius: 22),
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
                    Icons.campaign_rounded,
                    color: kPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Latest Announcement',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 18,
                      height: 1.3,
                      color: kNeutralText,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'No announcements posted yet for your managed Dayung units.',
              style: TextStyle(
                fontFamily: 'OpenSans',
                fontSize: 13,
                height: 1.5,
                color: kSubText,
              ),
            ),
          ],
        ),
      );
    }

    final title = (announcement!['title'] ?? '').toString();
    final body = (announcement!['body'] ?? '').toString().trim();
    final createdAt = announcement!['created_at']?.toString();
    String dateStr = '';
    if (createdAt != null && createdAt.isNotEmpty) {
      final dt = DateTime.tryParse(createdAt);
      if (dt != null) {
        dateStr = '${dt.month}/${dt.day}/${dt.year}';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: dayungSectionCardDecoration(context, radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: kPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Latest Announcement',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 18,
                        height: 1.3,
                        color: kNeutralText,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (dateStr.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          dateStr,
                          style: const TextStyle(
                            fontSize: 12,
                            color: kPrimary,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title.isEmpty ? 'Untitled announcement' : title,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 16,
              height: 1.35,
              color: kNeutralText,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'OpenSans',
                fontSize: 13,
                height: 1.5,
                color: kSubText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
