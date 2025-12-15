import 'dart:convert';
import 'package:capstone_app/Auth/logout.dart';
import 'package:capstone_app/Beneficiary/beneficiary.dart';
import 'package:capstone_app/Providers/apptheme_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/Secretary/beneficiaries_tab.dart';
import 'package:capstone_app/Secretary/certificates.dart';
import 'package:capstone_app/Secretary/secclaims.dart';
import 'package:capstone_app/Secretary/seccontributions.dart';
import 'package:capstone_app/Secretary/deathnotice.dart';
import 'package:capstone_app/Secretary/manage_applications.dart';
import 'package:capstone_app/Secretary/secretarymemberspage.dart';
import 'package:capstone_app/Secretary/service_tracker.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/pages/recentdeathnotices.dart';
import 'package:capstone_app/pages/reports.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:capstone_app/settings/profsettings.dart';
import 'package:capstone_app/ui/theme/branding.dart' as branding;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// color palette
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
  // ignore: unused_field
  String? _unitBarangay;
  // ignore: unused_field
  String? _unitCity;
  String? _profileUrl;

  double _pendingPaymentsAmount = 0;

  bool _showNavBar = true;
  bool _loadingActiveMembers = true;
  bool _loadingPendingPayments = true;

  int _currentIndex = 0;
  int _activeMembersCount = 0;
  int? _dayungUnitId;
  int? _lastRoleUnitId;
  // ignore: unused_field
  int _pendingPaymentsMembers = 0;
  int _unreadNotifCount = 0;
  int _unseenAppNotifs = 0;

  RealtimeChannel? _notifBadgeChannel;
  RealtimeChannel? _annBadgeChannel;
  RealtimeChannel? _appNotifChannel;

  List<Map<String, dynamic>> _recentCertificates = [];

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
      _fetchUnseenAppNotifs();
      _subscribeNotifBadgeRealtime();
      _subscribeApplicationRealtime();
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

  Future<void> _fetchUnseenAppNotifs() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    final unitId = _dayungUnitId;
    if (uid == null || unitId == null) {
      if (mounted) setState(() => _unseenAppNotifs = 0);
      return;
    }
    try {
      final rows = await sb
          .from('dayung_application_notifications')
          .select('id')
          .eq('secretary_id', uid)
          .eq('dayung_unit_id', unitId)
          .eq('seen', false);
      if (mounted) setState(() => _unseenAppNotifs = (rows as List).length);
    } catch (_) {
      if (mounted) setState(() => _unseenAppNotifs = 0);
    }
  }

  void _subscribeApplicationRealtime() {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    final unitId = _dayungUnitId;
    if (uid == null || unitId == null) return;
    try {
      _appNotifChannel?.unsubscribe();
    } catch (_) {}
    _appNotifChannel = sb.channel('sec_app_notifs_$unitId');
    _appNotifChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'dayung_application_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'dayung_unit_id',
            value: unitId,
          ),
          callback: (payload) async {
            final rec = payload.newRecord;
            // ignore: unnecessary_null_comparison
            if (rec != null &&
                rec['secretary_id'] == uid &&
                rec['seen'] == false) {
              await _fetchUnseenAppNotifs();
            }
          },
        )
        .subscribe();
  }

  void _maybeOnProviderUnitChanged(int? newUnitId) async {
    if (newUnitId == null || newUnitId == _lastRoleUnitId) return;
    _lastRoleUnitId = newUnitId;
    setState(() => _dayungUnitId = newUnitId);
    await _loadSecretaryInfo();
    await _refreshAll();
    await _fetchUnreadNotifCount();
    await _fetchUnseenAppNotifs();
    _subscribeApplicationRealtime();
    _subscribeNotifBadgeRealtime();
  }

  Future<void> _markAllAppNotifsSeen() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    final unitId = _dayungUnitId;
    if (uid == null || unitId == null) return;
    try {
      await sb
          .from('dayung_application_notifications')
          .update({'seen': true})
          .eq('secretary_id', uid)
          .eq('dayung_unit_id', unitId)
          .eq('seen', false);
    } catch (_) {}
  }

  Future<void> _fetchUnreadNotifCount() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    final unitId = _dayungUnitId;
    if (uid == null || unitId == null) {
      if (mounted) setState(() => _unreadNotifCount = 0);
      return;
    }
    try {
      final notifRows = await sb
          .from('notifications')
          .select('id')
          .eq('recipient_id', uid)
          .eq('dayung_unit_id', unitId)
          .isFilter('read_at', null);
      final notifCount = (notifRows as List).length;

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
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    final unitId = _dayungUnitId;
    if (uid == null || unitId == null) return;

    try {
      _notifBadgeChannel?.unsubscribe();
    } catch (_) {}
    try {
      _annBadgeChannel?.unsubscribe();
    } catch (_) {}
    _notifBadgeChannel = null;
    _annBadgeChannel = null;

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
        // ignore: unnecessary_cast
        final rec = payload.newRecord as Map<String, dynamic>;
        if (rec['dayung_unit_id'] == unitId) {
          await _fetchUnreadNotifCount();
        }
      },
    );
    ch1.subscribe();
    _notifBadgeChannel = ch1;

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
        // Get approved applications for this unit
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
          // Only count users who are NOT deceased
          final usersRows = await supabase
              .from('users')
              .select('id')
              .inFilter('id', ids.toList())
              .eq('is_deceased', false);
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
    if (_dayungUnitId == null)
      const Center(child: Text('Select a Dayung first'))
    else
      SecretaryContributionsPage(dayungUnitId: _dayungUnitId!),
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
              Builder(
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
                  'Good Morning,\n${_fullName.isEmpty ? 'Secretary' : _fullName}!',
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
              //       color: Colors.white.withValues(alpha: 0.2),
              //       borderRadius: BorderRadius.circular(32),
              //       boxShadow: [
              //         BoxShadow(
              //           color: Colors.black.withValues(alpha: 0.1),
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

  Widget _buildSideDrawer(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.95),
                borderRadius: const BorderRadius.only(
                  bottomRight: Radius.circular(32),
                  bottomLeft: Radius.circular(32),
                ),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, size: 40, color: kPrimary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _fullName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _ModernDrawerTile(
              icon: Icons.person,
              label: 'Profile',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfilePage()),
                );
                if (!mounted) return;
                setState(() {});
              },
            ),
            _ModernDrawerTile(
              icon: Icons.people_rounded,
              label: 'Beneficiaries',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BeneficiaryPage()),
                );
              },
            ),
            _ModernDrawerTile(
              icon: Icons.settings,
              label: 'Settings',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfSettingsPage()),
                );
              },
            ),
            _ModernDrawerTile(
              icon: isDarkMode ? Icons.light_mode : Icons.dark_mode,
              label: isDarkMode ? 'Light Mode' : 'Dark Mode',
              onTap: () {
                context.read<AppTheme>().toggle();
              },
            ),
            _ModernDrawerTile(
              icon: Icons.translate,
              label: 'Translate',
              onTap: () {
                // TODO: Implement translator
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.logout, color: Colors.white),
                  label: const Text(
                    'Logout',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    await showLogoutDialog(context);
                  },
                ),
              ),
            ),
          ],
        ),
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
          _overviewSection(MediaQuery.of(context).size.width),
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
    final names = _recentCertificates;
    final display = names.take(2).toList();
    // final extra = names.length - display.length;

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
                            name['deceased_name'] ?? 'Unknown',
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
          // if (extra > 0)
          //   Text(
          //     'View All',
          //     textAlign: TextAlign.center,
          //     style: TextStyle(
          //       fontSize: 13.5,
          //       fontWeight: FontWeight.w800,
          //       fontFamily: 'OpenSans',
          //       color: Colors.blue[700],
          //     ),
          //   ),
        ],
      ),
    );
  }

  Widget _overviewSection(double maxWidth) {
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
                  child: InkWell(
                    onTap: () {
                      if (_dayungUnitId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Select a Dayung first'),
                          ),
                        );
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SecretaryMembersPage(
                            dayungUnitId: _dayungUnitId!,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
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
                      if (_dayungUnitId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Select a Dayung first'),
                          ),
                        );
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              RecentDeathNotices(dayungUnitId: _dayungUnitId!),
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
                child: SizedBox(
                  height: 180,
                  child: InkWell(
                    onTap: () => setState(() => _currentIndex = 1),
                    borderRadius: BorderRadius.circular(16),
                    child: _modernStatCard(
                      icon: Icons.account_balance_wallet_rounded,
                      title: 'Pending Amount',
                      value: _loadingPendingPayments
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
                    height: 150,
                    onTap: () {
                      if (_dayungUnitId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Select a Dayung first'),
                          ),
                        );
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CreateDeathNoticePage(
                            dayungUnitId: _dayungUnitId!,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _modernActionCard(
                    icon: Icons.family_restroom_rounded,
                    title: "Manage",
                    subtitle: "Beneficiaries                     ",
                    color: const Color(0xFF3B82F6),
                    height: 150,
                    onTap: () {
                      if (_dayungUnitId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Select a Dayung first'),
                          ),
                        );
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SecretaryBeneficiariesTab(
                            dayungUnitId: _dayungUnitId!,
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
                    title: "Manage",
                    subtitle: "Applications                   ",
                    color: const Color(0xFF10B981),
                    height: 150,
                    badgeCount: _unseenAppNotifs,
                    onTap: () async {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SecretaryApplicationsPage(),
                        ),
                      ).then((_) async {
                        await _markAllAppNotifsSeen();
                        await _fetchUnseenAppNotifs();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _modernActionCard(
                    icon: Icons.track_changes_rounded,
                    title: "Service Tracking       ",
                    subtitle: "Monitor services",
                    color: const Color(0xFF8B5CF6),
                    height: 150,
                    onTap: () {
                      if (_dayungUnitId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Select a Dayung first'),
                          ),
                        );
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ServiceTrackerPage(dayungUnitId: _dayungUnitId!),
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
    int badgeCount = 0,
    double height = 150,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Container(
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
                  maxLines: 1,
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
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontFamily: 'OpenSans',
                  ),
                ),
              ],
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
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
                icon: Icons.bar_chart_rounded,
                title: "Reports",
                color: branding.kPrimary,
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
                      builder: (_) => ReportsPage(unitId: _dayungUnitId),
                    ),
                  );
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
                    Expanded(
                      child: _navBarItem(
                        icon: Icons.dashboard_rounded,
                        label: 'Dashboard',
                        selected: _currentIndex == 0,
                        onTap: () => setState(() => _currentIndex = 0),
                      ),
                    ),
                    Expanded(
                      child: _navBarItem(
                        icon: Icons.trending_up_rounded,
                        label: 'Contributions',
                        selected: _currentIndex == 1,
                        onTap: () => setState(() => _currentIndex = 1),
                      ),
                    ),
                    Expanded(
                      child: _navBarItem(
                        icon: Icons.assignment_rounded,
                        label: 'Claims',
                        selected: _currentIndex == 2,
                        onTap: () => setState(() => _currentIndex = 2),
                      ),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              constraints: const BoxConstraints(minHeight: 56, maxHeight: 64),
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
                  const SizedBox(height: 2),
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
    final hoverColor = kPrimary.withOpacity(0.08);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _hovering ? hoverColor : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(widget.icon, color: kPrimary),
              const SizedBox(width: 18),
              Text(
                widget.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: kPrimary,
                  fontFamily: 'Montserrat',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
