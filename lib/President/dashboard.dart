import 'dart:convert';

import 'package:capstone_app/shared/pres_sec_dashboard_overview.dart';
import 'package:capstone_app/shared/collector_progress_page.dart';
import 'package:capstone_app/President/manage_roles.dart';
import 'package:capstone_app/President/manage_rules.dart';
import 'package:capstone_app/President/president_payment_page.dart';
import 'package:capstone_app/President/president_activity_page.dart';
import 'package:capstone_app/President/post_announcement.dart';
import 'package:capstone_app/President/sms_announcement_page.dart';
import 'package:capstone_app/President/presclaims.dart' hide kPrimary;
import 'package:capstone_app/President/prescontribution.dart' hide kPrimary;
import 'package:capstone_app/President/presidentmemberspage.dart'
    hide kPrimary, kNeutralText;
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/pages/recentdeathnotices.dart';
import 'package:capstone_app/pages/reports.dart' as reports;
import 'package:capstone_app/shared/dayung_role_navigation_bar.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/profile/required_application_page.dart';
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
  int? _dayungUnitId;
  List<int> _managedUnitIds = [];
  int? get _primaryUnitId =>
      _managedUnitIds.isNotEmpty ? _managedUnitIds.first : null;
  int? _effectiveUnitId(BuildContext context) {
    final roleUnitId = context.read<DayungRoleProvider>().unitId;
    final selectedUnitId = context.read<DayungUnitProvider>().currentUnitId;
    return roleUnitId ?? selectedUnitId ?? _dayungUnitId ?? _primaryUnitId;
  }

  // ignore: unused_field
  String _fullName = '';
  // ignore: unused_field
  String _selectedDayungUnit = 'Dayung Unit';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provUnit = context.read<DayungRoleProvider>().unitId;
      _maybeOnProviderUnitChanged(provUnit);
    });
    _initLoad();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
    final provUnit = context.watch<DayungRoleProvider>().unitId;
    if (provUnit != _lastRoleUnitId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeOnProviderUnitChanged(provUnit);
      });
    }

    return Container(
      decoration: BoxDecoration(gradient: dayungDashboardGradient(context)),
      child: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [_buildModernHeader(), _buildContentArea()],
            ),
          ),
          _buildFloatingNavBar(),
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
              Semantics(
                button: true,
                label: 'Open menu',
                onTap: () => Scaffold.of(context).openDrawer(),
                child: ExcludeSemantics(
                  child: Builder(
                    builder: (context) => Container(
                      padding: const EdgeInsets.all(1),
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
                      child: IconButton(
                        icon: const Icon(
                          Icons.menu_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    ),
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
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationPage()),
                  );
                  await _load();
                },
                badge: _unreadNotifCount > 0 ? '$_unreadNotifCount' : null,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: dayungGreetingPanel(
                  child: Text(
                    'Good Morning,\n${_fullName.isEmpty ? 'President' : _fullName}!',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
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
              ),
            ],
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
    return Semantics(
      button: true,
      label: 'Notifications',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Tooltip(
              message: 'Notifications',
              child: Container(
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
        ),
      ),
    );
  }

  Widget _buildContentArea() {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: dayungSurface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [dayungTopShadow(context)],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: RefreshIndicator(
            onRefresh: _load,
            edgeOffset: 16,
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

  Widget _buildFloatingNavBar() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.paddingOf(context).bottom + 8,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: DayungRoleNavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) =>
                setState(() => _currentIndex = index),
          ),
        ),
      ),
    );
  }

  /* ------------------------------- Home page ------------------------------- */
  Widget _buildHomePage(BuildContext context) {
    final dashboardUnitId = _effectiveUnitId(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 400 ? 16.0 : 24.0;
        final bottomPadding = dayungRoleNavigationClearance(context);
        return SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            20,
            horizontalPadding,
            bottomPadding,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (dashboardUnitId != null)
                    PresSecDashboardOverview(
                      key: ValueKey(dashboardUnitId),
                      dayungUnitId: dashboardUnitId,
                      responsiveLayout: true,
                      onNavigateToMembers: () async {
                        final navigator = Navigator.of(context);
                        final ids = await _managedDayungIds();
                        if (!mounted) return;
                        navigator.push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PresidentMembersPage(dayungUnitIds: ids),
                          ),
                        );
                      },
                      onNavigateToDeceased: () {
                        final effectiveUnitId = _effectiveUnitId(context);
                        if (effectiveUnitId == null) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RecentDeathNotices(
                              dayungUnitId: effectiveUnitId,
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 24),
                  _UpcomingAnnouncementCard(
                    loading: _loadingAnnouncement,
                    announcement: _latestAnnouncement,
                  ),
                  const SizedBox(height: 24),
                  _buildQuickActions(),
                  const SizedBox(height: 24),
                  _ContributionBarChartCard(dayungUnitIds: _managedUnitIds),
                ],
              ),
            ),
          ),
        );
      },
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
    final managementActions = [
      _PresidentDashboardAction(
        icon: Icons.campaign_rounded,
        title: 'Post Announcement',
        color: Theme.of(context).colorScheme.primary,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PostAnnouncementPage()),
        ),
      ),
      _PresidentDashboardAction(
        icon: Icons.payments_rounded,
        title: 'Pay Contribution',
        color: Theme.of(context).colorScheme.secondary,
        onTap: () async {
          final ids = await _managedDayungIds();
          if (ids.isEmpty || !mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PresidentPaymentPage(dayungUnitId: ids.first),
            ),
          );
        },
      ),
      _PresidentDashboardAction(
        icon: Icons.rule_rounded,
        title: 'Manage User Preferences',
        color: Theme.of(context).colorScheme.tertiary,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ManageRulesPagePres()),
        ),
      ),
      _PresidentDashboardAction(
        icon: Icons.bar_chart_rounded,
        title: 'Collector Progress',
        color: Theme.of(context).colorScheme.primary,
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
      _PresidentDashboardAction(
        icon: Icons.sms_outlined,
        title: 'Announcement for SMS',
        color: Theme.of(context).colorScheme.secondary,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SmsAnnouncementPage()),
        ),
      ),
      _PresidentDashboardAction(
        icon: Icons.assessment_rounded,
        title: 'Reports',
        color: Theme.of(context).colorScheme.tertiary,
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
              builder: (_) => reports.ReportsPage(unitId: unitId),
            ),
          );
        },
      ),
    ];
    final quickAccessActions = [
      _PresidentDashboardAction(
        icon: Icons.bar_chart_rounded,
        title: 'Contributions',
        color: Theme.of(context).colorScheme.primary,
        onTap: () => setState(() => _currentIndex = 1),
      ),
      _PresidentDashboardAction(
        icon: Icons.assignment_rounded,
        title: 'Claims',
        color: Theme.of(context).colorScheme.error,
        onTap: () => setState(() => _currentIndex = 2),
      ),
      _PresidentDashboardAction(
        icon: Icons.description_rounded,
        title: 'Required Application',
        color: Theme.of(context).colorScheme.tertiary,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RequiredApplicationsPage()),
        ),
      ),
      _PresidentDashboardAction(
        icon: Icons.history_rounded,
        title: 'Activity',
        color: Theme.of(context).colorScheme.secondary,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PresidentActivityPage()),
        ).then((_) => _load()),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildActionSection('Management tools', managementActions),
        const SizedBox(height: 24),
        _buildActionSection('Quick access', quickAccessActions),
      ],
    );
  }

  Widget _buildActionSection(
    String title,
    List<_PresidentDashboardAction> actions,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 520
                ? 1
                : constraints.maxWidth < 900
                ? 2
                : 3;
            const spacing = 12.0;
            final itemWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: actions
                  .map(
                    (action) => SizedBox(
                      width: itemWidth,
                      child: _modernActionCard(
                        icon: action.icon,
                        title: action.title,
                        color: action.color,
                        onTap: action.onTap,
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _modernActionCard({
    required IconData icon,
    required String title,
    required Color color,
    VoidCallback? onTap,
    int badgeCount = 0,
  }) {
    return Material(
      color: Colors.transparent,
      child: Semantics(
        button: true,
        label: badgeCount > 0 ? '$title, $badgeCount items' : title,
        onTap: onTap,
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
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 88),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (badgeCount > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '$badgeCount',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 24,
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

class _PresidentDashboardAction {
  const _PresidentDashboardAction({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;
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
    final theme = Theme.of(context);
    final chartColor = theme.colorScheme.primary;
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
                    color: dayungAccentSurface(context, chartColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.bar_chart_rounded,
                    color: chartColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Contribution Records',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            // const SizedBox(height: 8),
            // Text(
            //   hasUnits
            //       ? 'Paid contributions across your managed Dayung members and officers.'
            //       : 'No managed Dayung units available yet.',
            //   style: const TextStyle(
            //     fontFamily: 'OpenSans',
            //     fontSize: 13,
            //     color: kSubText,
            //     height: 1.4,
            //   ),
            // ),
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
                  Container(width: 1, height: 36, color: dayungBorder(context)),
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
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurfaceVariant,
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
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
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
                                color: chartColor,
                                width: 22,
                                borderRadius: BorderRadius.circular(4),
                                backDrawRodData: BackgroundBarChartRodData(
                                  show: true,
                                  toY: maxY,
                                  color: dayungSoftSurface(context),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            _MiniLegendRow(color: chartColor),
          ],
        ),
      ),
    );
  }
}

class _MiniLegendRow extends StatelessWidget {
  const _MiniLegendRow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _dot(color),
        const SizedBox(width: 6),
        Text(
          'batches',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    final theme = Theme.of(context);
    if (loading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: dayungSectionCardDecoration(context, radius: 18),
        child: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Loading latest announcement…',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ],
        ),
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
                Icon(
                  Icons.campaign_rounded,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Latest Announcement',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'No announcements posted yet for your managed Dayung units.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
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
              Icon(
                Icons.campaign_rounded,
                color: theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Latest Announcement',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
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
                          color: dayungAccentSurface(
                            context,
                            theme.colorScheme.primary,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          dateStr,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
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
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
