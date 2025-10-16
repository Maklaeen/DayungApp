import 'dart:convert';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/Secretary/beneficiaries_tab.dart'
    show SecretaryBeneficiariesTab;
import 'package:capstone_app/Secretary/certificates.dart';
import 'package:capstone_app/Secretary/claims.dart';
import 'package:capstone_app/Secretary/contributions.dart';
import 'package:capstone_app/Secretary/deathnotice.dart';
import 'package:capstone_app/Secretary/manage_applications.dart';
import 'package:capstone_app/Secretary/secretarymemberspage.dart';
import 'package:capstone_app/Secretary/service_tracker.dart';
import 'package:capstone_app/pages/dayung_profile.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/pages/recentdeathnotices.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:capstone_app/ui/theme/branding.dart' as branding;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

// Palette
const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kWarn = Color(0xFFF57C00);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);
const double kEdge = 18;

class SecretaryDashboardPage extends StatefulWidget {
  const SecretaryDashboardPage({super.key});
  @override
  State<SecretaryDashboardPage> createState() => _SecretaryDashboardPageState();
}

class _SecretaryDashboardPageState extends State<SecretaryDashboardPage> {
  final supabase = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();

  String _fullName = '';
  String _selectedDayungUnit = 'Dayung Unit';
  int _currentIndex = 0;
  bool _showNavBar = true;

  int _activeMembersCount = 0;
  bool _loadingActiveMembers = true;
  int? _dayungUnitId;
  int? _lastRoleUnitId;
  List<Map<String, dynamic>> _recentCertificates = [];

  double _pendingPaymentsAmount = 0;
  int _pendingPaymentsMembers = 0;
  bool _loadingPendingPayments = true;
  int _unreadNotifCount = 0; // NEW
  RealtimeChannel? _notifBadgeChannel; // NEW
  RealtimeChannel? _annBadgeChannel; // NEW
  String? _unitBarangay; // NEW
  String? _unitCity;

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
      _fetchUnreadNotifCount();
      _subscribeNotifBadgeRealtime();
    });

    _initLoad();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    try {
      _notifBadgeChannel?.unsubscribe();
    } catch (_) {}
    try {
      _annBadgeChannel?.unsubscribe();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _initLoad() async {
    await _loadSecretaryInfo();
    await Future.wait([
      _fetchActiveMembersCount(),
      _fetchRecentCertificates(),
      _fetchPendingPayments(),
    ]);
  }

  void _maybeOnProviderUnitChanged(int? newUnitId) async {
    if (newUnitId == null || newUnitId == _lastRoleUnitId) return;
    _lastRoleUnitId = newUnitId;
    setState(() => _dayungUnitId = newUnitId);
    await _loadSecretaryInfo(); // updates label from prefs if changed
    await _refreshAll(); // reload counts/panels
    await _fetchUnreadNotifCount(); // NEW: refresh badge for new unit
    _subscribeNotifBadgeRealtime();
  }

  Future<void> _fetchUnreadNotifCount() async {
    // NEW
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    final unitId = _dayungUnitId;
    if (uid == null || unitId == null) {
      if (mounted) setState(() => _unreadNotifCount = 0);
      return;
    }
    try {
      // Unread notifications addressed to the secretary for this unit
      final notifRows = await sb
          .from('notifications')
          .select('id')
          .eq('recipient_id', uid)
          .eq('dayung_unit_id', unitId)
          .isFilter('read_at', null);
      final notifCount = (notifRows as List).length;

      // Unread announcements for this unit (not yet marked read by this user)
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

  void _subscribeNotifBadgeRealtime() {
    // NEW
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    final unitId = _dayungUnitId;
    if (uid == null || unitId == null) return;

    // Cleanup old channels
    try {
      _notifBadgeChannel?.unsubscribe();
    } catch (_) {}
    try {
      _annBadgeChannel?.unsubscribe();
    } catch (_) {}
    _notifBadgeChannel = null;
    _annBadgeChannel = null;

    // Notifications inserts to this recipient; guard by unit in callback
    final ch1 = sb.channel('sec_badge_notifications_$uid');
    ch1.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'recipient_id',
        value: uid,
      ),
      callback: (payload) async {
        final rec = payload.newRecord as Map<String, dynamic>;
        if (rec['dayung_unit_id'] == unitId) {
          await _fetchUnreadNotifCount();
        }
      },
    );
    ch1.subscribe();
    _notifBadgeChannel = ch1;

    // Announcements inserts for current unit
    final ch2 = sb.channel('sec_badge_announcements_$unitId');
    ch2.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'announcements',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'dayung_unit_id',
        value: unitId,
      ),
      callback: (_) async {
        await _fetchUnreadNotifCount();
      },
    );
    ch2.subscribe();
    _annBadgeChannel = ch2;
  }

  Future<void> _loadSecretaryInfo() async {
    final prefs = await SharedPreferences.getInstance();
    String name = prefs.getString('secretaryFullName') ?? 'Secretary';
    String dayungLabelRaw =
        prefs.getString('selectedDayungUnit') ?? 'Dayung Unit';
    int? unitId;
    String? jsonFull = prefs.getString('selectedDayungUnitData');
    Map<String, dynamic>? parsed;
    if (jsonFull != null) {
      try {
        parsed = jsonDecode(jsonFull);
      } catch (_) {}
    }
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
      _unitBarangay = (parsed['barangay'] ?? '').toString().trim().isEmpty
          ? null
          : parsed['barangay'].toString();
      _unitCity = (parsed['city'] ?? '').toString().trim().isEmpty
          ? null
          : parsed['city'].toString();
    }
    setState(() {
      _fullName = name;
      _selectedDayungUnit = resolvedLabel;
      _dayungUnitId = unitId ?? _dayungUnitId ?? 1;
    });
  }

  Future<void> _fetchActiveMembersCount() async {
    setState(() => _loadingActiveMembers = true);
    try {
      final unitId = _dayungUnitId;
      if (unitId == null) {
        _activeMembersCount = 0;
      } else {
        // Approved members for the selected unit only
        final apps = await supabase
            .from('applications')
            .select('user_id')
            .eq('dayung_unit_id', unitId)
            .eq('status', 'approved');

        final ids = (apps as List)
            .map((e) => (e as Map)['user_id'])
            .whereType<String>()
            .toSet();

        if (ids.isEmpty) {
          _activeMembersCount = 0;
        } else {
          // Optional: exclude deceased
          final usersRows = await supabase
              .from('users')
              .select('id, is_deceased')
              .inFilter('id', ids.toList());
          final alive = (usersRows as List)
              .map((e) => (e as Map)['id']?.toString())
              .whereType<String>()
              .toSet();
          _activeMembersCount = alive.length;
        }
      }
    } catch (_) {
      _activeMembersCount = 0;
    } finally {
      if (mounted) setState(() => _loadingActiveMembers = false);
    }
  }

  Future<void> _fetchRecentCertificates() async {
    try {
      final unitId = _dayungUnitId;
      if (unitId == null) {
        if (mounted) setState(() => _recentCertificates = []);
        return;
      }

      // Direct notices for this unit
      final direct = await supabase
          .from('death_notices')
          .select('id, name, date_of_death, dayung_unit_id')
          .eq('dayung_unit_id', unitId)
          .order('date_of_death', ascending: false)
          .limit(5);
      final directList = List<Map<String, dynamic>>.from(direct);

      // Members of this unit via approved applications
      final apps = await supabase
          .from('applications')
          .select('user_id')
          .eq('dayung_unit_id', unitId)
          .eq('status', 'approved');
      final userIds = List<Map<String, dynamic>>.from(apps)
          .map((e) => (e['user_id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();

      // Notices linked to those users where dayung_unit_id is null
      List<Map<String, dynamic>> viaUserList = [];
      if (userIds.isNotEmpty) {
        final viaUser = await supabase
            .from('death_notices')
            .select('id, name, date_of_death, dayung_unit_id, user_id')
            .isFilter('dayung_unit_id', null)
            .inFilter('user_id', userIds)
            .order('date_of_death', ascending: false)
            .limit(5);
        viaUserList = List<Map<String, dynamic>>.from(viaUser);
      }

      // Merge unique by id and sort desc
      final all = <int, Map<String, dynamic>>{};
      for (final n in [...directList, ...viaUserList]) {
        final id = int.tryParse('${n['id']}');
        if (id != null) all[id] = n;
      }
      final list = all.values.toList()
        ..sort(
          (a, b) => DateTime.parse(
            '${b['date_of_death']}',
          ).compareTo(DateTime.parse('${a['date_of_death']}')),
        );

      final normalized = list
          .map(
            (e) => {
              'deceased_name': e['name'],
              'date_of_death': e['date_of_death'],
              'dayung_unit_id': e['dayung_unit_id'],
            },
          )
          .toList();

      if (mounted) setState(() => _recentCertificates = normalized);
    } catch (_) {
      if (mounted) setState(() => _recentCertificates = []);
    }
  }

  Future<void> _fetchPendingPayments() async {
    setState(() => _loadingPendingPayments = true);
    try {
      final unitId = _dayungUnitId;
      if (unitId == null) {
        _pendingPaymentsAmount = 0;
        _pendingPaymentsMembers = 0;
      } else {
        // Unit-scoped pending totals
        final rows = await supabase
            .from('payments')
            .select('amount, user_id, status')
            .eq('dayung_unit_id', unitId)
            .eq('status', 'pending');

        double total = 0;
        final memberSet = <String>{};
        for (final r in rows as List) {
          final m = r as Map;
          total += (m['amount'] is num) ? (m['amount'] as num).toDouble() : 0;
          if (m['user_id'] != null) memberSet.add(m['user_id'].toString());
        }
        _pendingPaymentsAmount = total;
        _pendingPaymentsMembers = memberSet.length;
      }
    } catch (_) {
      _pendingPaymentsAmount = 0;
      _pendingPaymentsMembers = 0;
    } finally {
      if (mounted) setState(() => _loadingPendingPayments = false);
    }
  }

  Future<void> _refreshAll() async {
    await _loadSecretaryInfo();
    await Future.wait([
      _fetchActiveMembersCount(),
      _fetchRecentCertificates(),
      _fetchPendingPayments(),
    ]);
  }

  List<Widget> get _pages => [
    _buildHomePage(context),
    SecretaryContributionsPage(dayungUnitId: _dayungUnitId ?? 1),
    const SecretaryClaimsPage(),
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
              child: Column(
                children: [_buildModernHeader(), _buildContentArea(wide)],
              ),
            ),
            _bottomNav(wide),
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
                  Icons.dashboard_rounded,
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
                    const Text(
                      'Secretary Dashboard',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              _buildModernIconButton(
                icon: Icons.notifications_rounded,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationPage()),
                  );
                  await _fetchUnreadNotifCount();
                },
                badge: _unreadNotifCount > 0 ? '$_unreadNotifCount' : null,
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Greeting section
          Row(
            children: [
              Expanded(
                child: Text(
                  'Maayung buntag,\n${_fullName.isEmpty ? 'Secretary' : _fullName}!',
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
            onRefresh: _refreshAll, // keep old backend refresh
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

  Widget _buildHomePage(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _modernStatsGrid(MediaQuery.of(context).size.width),
          const SizedBox(height: 24),
          _modernActionCards(),
          const SizedBox(height: 24),
          _modernRecentActivity(),
          const SizedBox(height: 24),
          _modernQuickActions(),
          const SizedBox(height: 100), // space for bottom nav
        ],
      ),
    );
  }

  Widget _modernStatsGrid(double maxWidth) {
    return Row(
      children: [
        Expanded(
          child: _modernStatCard(
            icon: Icons.people_rounded,
            title: "Active Members",
            value: _loadingActiveMembers
                ? "..."
                : _activeMembersCount.toString(),
            color: const Color(0xFF10B981),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      SecretaryMembersPage(dayungUnitId: _dayungUnitId ?? 1),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _modernStatCard(
            icon: Icons.history_rounded,
            title: "Recent Deaths",
            value: "${_recentCertificates.length}",
            color: const Color(0xFF8B5CF6),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      RecentDeathNotices(dayungUnitId: _dayungUnitId ?? 1),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _modernStatCard(
            icon: Icons.payment_rounded,
            title: "Pending Payments",
            value: _loadingPendingPayments
                ? "..."
                : "₱${_pendingPaymentsAmount.toStringAsFixed(0)}",
            color: const Color(0xFFF59E0B),
            onTap: () => setState(() => _currentIndex = 1),
          ),
        ),
      ],
    );
  }

  Widget _modernStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 120,
        padding: const EdgeInsets.all(12),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
                fontFamily: 'OpenSans',
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
                fontFamily: 'Montserrat',
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _modernActionCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Quick Actions",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: branding.kNeutralText,
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(height: 16),
        Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _modernActionCard(
                    icon: Icons.add_circle_rounded,
                    title: "Create Death Notice",
                    subtitle: "Record new death",
                    color: const Color(0xFFEF4444),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CreateDeathNoticePage(
                            dayungUnitId: _dayungUnitId ?? 1,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _modernActionCard(
                    icon: Icons.people_rounded,
                    title: "Manage Members",
                    subtitle: "View & edit members",
                    color: const Color(0xFF3B82F6),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SecretaryMembersPage(
                            dayungUnitId: _dayungUnitId ?? 1,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _modernActionCard(
                    icon: Icons.assignment_rounded,
                    title: "Manage Applications",
                    subtitle: "Review applications",
                    color: const Color(0xFF10B981),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SecretaryApplicationsPage(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _modernActionCard(
                    icon: Icons.track_changes_rounded,
                    title: "Service Tracking",
                    subtitle: "Monitor services",
                    color: const Color(0xFF8B5CF6),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ServiceTrackerPage(
                            dayungUnitId: _dayungUnitId ?? 1,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _modernActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 120,
        padding: const EdgeInsets.all(16),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: branding.kNeutralText,
                fontFamily: 'Montserrat',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
                fontFamily: 'OpenSans',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modernRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Recent Activity",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: branding.kNeutralText,
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
                      color: branding.kPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.folder_open_rounded,
                      color: branding.kPrimary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Death Certificate Inbox",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: branding.kNeutralText,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CertificatesPage(),
                        ),
                      );
                    },
                    child: const Text(
                      "View All",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: branding.kPrimary,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                ],
              ),
              if (_recentCertificates.isNotEmpty) ...[
                const SizedBox(height: 16),
                ..._recentCertificates
                    .take(3)
                    .map(
                      (cert) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: branding.kPrimary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                cert['deceased_name'] ?? 'Unknown',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: branding.kNeutralText,
                                  fontFamily: 'OpenSans',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ] else ...[
                const SizedBox(height: 16),
                const Text(
                  "No recent certificates",
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                    fontFamily: 'OpenSans',
                  ),
                ),
              ],
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
            color: branding.kNeutralText,
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _modernQuickActionCard(
                icon: Icons.info_outline_rounded,
                title: "Notify Members",
                color: branding.kPrimary,
                onTap: () {
                  // Keep existing functionality (placeholder)
                },
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: SizedBox.shrink()),
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
                      selected: _currentIndex == 0,
                      onTap: () => setState(() => _currentIndex = 0),
                    ),
                    _navBarItem(
                      icon: Icons.trending_up_rounded,
                      label: 'Contributions',
                      selected: _currentIndex == 1,
                      onTap: () => setState(() => _currentIndex = 1),
                    ),
                    _navBarItem(
                      icon: Icons.assignment_rounded,
                      label: 'Claims',
                      selected: _currentIndex == 2,
                      onTap: () => setState(() => _currentIndex = 2),
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
                    ? branding.kPrimary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: selected
                    ? Border.all(
                        color: branding.kPrimary.withValues(alpha: 0.3),
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
                          ? branding.kPrimary
                          : Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: branding.kPrimary.withValues(alpha: 0.4),
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
                      color: selected ? branding.kPrimary : Colors.grey[700],
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
}
