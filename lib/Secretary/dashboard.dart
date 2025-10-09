import 'dart:convert';
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
import 'package:flutter/material.dart';
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

  List<Map<String, dynamic>> _recentCertificates = [];

  double _pendingPaymentsAmount = 0;
  int _pendingPaymentsMembers = 0;
  bool _loadingPendingPayments = true;

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

    // Load secretary info + recent deaths/pending on start
    _initLoad();
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) {
        _activeMembersCount = 0;
      } else {
        // Dayungs managed by this secretary
        final dayungs = await supabase
            .from('dayung_units')
            .select('id')
            .eq('secretary_id', uid);

        final ids = (dayungs as List)
            .map((e) => (e as Map)['id'])
            .whereType<int>()
            .toList();

        if (ids.isEmpty) {
          _activeMembersCount = 0;
        } else {
          // Distinct members with an approved application to those dayungs
          final apps = await supabase
              .from('applications')
              .select('user_id, dayung_unit_id')
              .inFilter('dayung_unit_id', ids)
              .eq('status', 'approved');

          final distinctUserIds = <String>{};
          for (final row in (apps as List)) {
            final m = row as Map<String, dynamic>;
            final uidStr = (m['user_id'] ?? '').toString();
            if (uidStr.isNotEmpty) distinctUserIds.add(uidStr);
          }

          if (distinctUserIds.isEmpty) {
            _activeMembersCount = 0;
          } else {
            // Optional: exclude deceased
            final usersRows = await supabase
                .from('users')
                .select('id, is_deceased')
                .inFilter('id', distinctUserIds.toList());

            final aliveIds = (usersRows as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .where((u) => (u['is_deceased'] ?? false) == false)
                .map((u) => u['id'].toString())
                .toSet();

            _activeMembersCount = aliveIds.length;
          }
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

      // Fetch death notices for this dayung, including those where dayung_unit_id is null but user's dayung matches
      final noticesDirect = await supabase
          .from('death_notices')
          .select('id, name, date_of_death, dayung_unit_id, user_id')
          .eq('dayung_unit_id', unitId)
          .order('date_of_death', ascending: false)
          .limit(5);

      // Also fetch notices where dayung_unit_id is null but user's dayung matches
      final usersRes = await supabase
          .from('users')
          .select('id')
          .eq('dayung_unit_id', unitId);
      final userIds = (usersRes as List)
          .map((e) => (e as Map)['id'].toString())
          .where((s) => s.isNotEmpty)
          .toList();

      List<Map<String, dynamic>> noticesViaUser = [];
      if (userIds.isNotEmpty) {
        final viaUser = await supabase
            .from('death_notices')
            .select('id, name, date_of_death, dayung_unit_id, user_id')
            .isFilter('dayung_unit_id', null)
            .inFilter('user_id', userIds)
            .order('date_of_death', ascending: false)
            .limit(5);
        noticesViaUser = (viaUser as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }

      // Merge and deduplicate by id
      final allNotices = <int, Map<String, dynamic>>{};
      for (final n in [...noticesDirect, ...noticesViaUser]) {
        final id = n['id'] as int?;
        if (id != null) allNotices[id] = n;
      }
      final list = allNotices.values.toList();
      list.sort(
        (a, b) => DateTime.parse(
          b['date_of_death'].toString(),
        ).compareTo(DateTime.parse(a['date_of_death'].toString())),
      );

      // Normalize keys for UI
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
      // Try RPC first
      final uid = supabase.auth.currentUser?.id;
      if (uid != null) {
        bool done = false;
        try {
          final rpc = await supabase.rpc(
            'secretary_pending_payments',
            params: {'p_secretary_id': uid},
          );
          if (rpc is Map && rpc['total_amount'] != null) {
            _pendingPaymentsAmount =
                double.tryParse(rpc['total_amount'].toString()) ?? 0;
            _pendingPaymentsMembers =
                int.tryParse(rpc['member_count'].toString()) ?? 0;
            done = true;
          }
        } catch (_) {}
        if (!done) {
          // Fallback: naive table approach
          final rows = await supabase
              .from('payments')
              .select('amount, user_id, status, dayung_unit_id');
          // Filter manually for dayungs managed by secretary (reduce risk of missing col)
          final managed = await supabase
              .from('dayung_units')
              .select('id')
              .eq('secretary_id', uid);
          final managedIds = (managed as List)
              .map((e) => (e as Map)['id'])
              .whereType<int>()
              .toSet();
          double total = 0;
          final memberSet = <String>{};
          for (final r in rows as List) {
            final m = r as Map;
            if ((m['status'] ?? '').toString().toLowerCase() == 'pending') {
              final dId = m['dayung_unit_id'];
              if (dId is int && managedIds.contains(dId)) {
                total += (m['amount'] is num)
                    ? (m['amount'] as num).toDouble()
                    : 0;
                if (m['user_id'] != null)
                  memberSet.add(m['user_id'].toString());
              }
            }
          }
          _pendingPaymentsAmount = total;
          _pendingPaymentsMembers = memberSet.length;
        }
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

  Widget _topHeader(bool wide) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _selectedDayungUnit,
              style: TextStyle(
                fontSize: wide ? 34 : 30,
                fontWeight: FontWeight.w800,
                letterSpacing: .4,
                color: kPrimaryDark,
                fontFamily: 'Montserrat',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _iconBtn(
            tooltip: 'Dayung Profile',
            icon: Icons.settings,
            color: kPrimary,
            onTap: () {
              final id = _dayungUnitId ?? 1;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DayungProfilePage(dayungUnitId: id),
                ),
              );
            },
          ),
          _iconBtn(
            tooltip: 'Notifications',
            icon: Icons.notifications,
            color: kWarn,
            badge: '1',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationPage()),
              );
            },
          ),
        ],
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
              "Maayung buntag, $_fullName!",
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                fontFamily: 'Montserrat',
                color: kNeutralText,
                height: 1.15,
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
            child: const CircleAvatar(
              radius: 30,
              backgroundColor: kPrimary,
              child: Icon(Icons.person, size: 34, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomePage(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        return SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _overviewTripleCards(constraints.maxWidth),
              const SizedBox(height: 28),
              _sectionTitle("Certificates"),
              _panelCard(
                child: Column(
                  children: [
                    const Text(
                      "Death Certificate Inbox",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Montserrat',
                        color: kNeutralText,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _primaryButton(
                      label: "View Certificates",
                      icon: Icons.folder_open,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CertificatesPage(),
                          ),
                        );
                      },
                    ),
                    if (_recentCertificates.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Recent",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: kSubtleText.withOpacity(.9),
                            fontFamily: 'Montserrat',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Column(
                        children: _recentCertificates.take(3).map((c) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: kPrimary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    c['deceased_name'] ?? 'Unknown',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontFamily: 'OpenSans',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 30),
              _sectionTitle("Actions"),
              Row(
                children: [
                  Expanded(
                    child: _actionTile(
                      icon: Icons.info_outline,
                      label: "Notify members to\nupdate info",
                      color: kPrimary,
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _actionTile(
                      icon: Icons.volunteer_activism,
                      label: "Service\nTracking",
                      color: kAccent,
                      onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ServiceTrackerPage(dayungUnitId: _dayungUnitId ?? 1),
    ),
  );
},
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _primaryButton(
                label: "Create Death Notice",
                icon: Icons.add_circle_outline,
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
                fillColor: kPrimary,
              ),
              const SizedBox(height: 30),
              _sectionTitle("Management"),
              _secondaryButton(
                label: "Applications Inbox",
                icon: Icons.mail,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SecretaryApplicationsPage(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              _secondaryButton(
                label: "Beneficiaries",
                icon: Icons.people,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SecretaryBeneficiariesTab(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _overviewTripleCards(double maxWidth) {
    final recentNames = _recentCertificates
        .map((c) => (c['deceased_name'] ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final cards = [
      _statCard(
        color: const Color(0xFFD8EEFF),
        icon: Icons.groups,
        iconColor: Colors.blue[700],
        title: "Total Active\nMembers",
        value: _loadingActiveMembers ? "…" : _activeMembersCount.toString(),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SecretaryMembersPage()),
        ),
      ),
      _recentDeathsCard(recentNames),
      _statCard(
        color: const Color(0xFFFEFBDC),
        icon: Icons.account_balance_wallet,
        iconColor: Colors.orange[700],
        title: "Pending\nPayments",
        value: _loadingPendingPayments
            ? "…"
            : "₱ ${_pendingPaymentsAmount.toStringAsFixed(0)}",
        smallSubtitle: _loadingPendingPayments
            ? ""
            : "From $_pendingPaymentsMembers",
        onTap: () => setState(() => _currentIndex = 1),
      ),
    ];

    if (maxWidth < 360) {
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 12),
        Expanded(child: cards[1]),
        const SizedBox(width: 12),
        Expanded(child: cards[2]),
      ],
    );
  }

  Widget _statCard({
    required Color color,
    required IconData icon,
    required Color? iconColor,
    required String title,
    required String value,
    VoidCallback? onTap,
    bool multiLineValue = false,
    String smallSubtitle = "",
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade300, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(icon, size: 32, color: iconColor),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                fontFamily: 'Montserrat',
                height: 1.15,
                color: kNeutralText,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Center(
                child: multiLineValue
                    ? Text(
                        value,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          height: 1.15,
                          fontFamily: 'Montserrat',
                          color: kNeutralText,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.fade,
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          value,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 32,
                            fontFamily: 'Montserrat',
                            color: kNeutralText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
              ),
            ),
            if (smallSubtitle.isNotEmpty)
              Text(
                smallSubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'OpenSans',
                  color: kSubtleText,
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  Widget _recentDeathsCard(List<String> names) {
    final display = names.take(2).toList();
    final extra = names.length - display.length;

    return InkWell(
      onTap: () {
        final id = _dayungUnitId ?? 1;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RecentDeathNotices(dayungUnitId: id),
          ),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFDAF6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade300, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(FontAwesomeIcons.dove, size: 30, color: Colors.purple[400]),
            const SizedBox(height: 8),
            const Text(
              "Recent Deaths",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                fontFamily: 'Montserrat',
                height: 1.15,
                color: kNeutralText,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: names.isEmpty
                  ? const Center(
                      child: Text(
                        "None",
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
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.black,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (extra > 0)
                          Text(
                            '+$extra more',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'OpenSans',
                              color: kNeutralText,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: .4,
        color: kNeutralText,
        fontFamily: 'Montserrat',
      ),
    ),
  );

  Widget _panelCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kEdge),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(kEdge),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
        decoration: BoxDecoration(
          color: color.withOpacity(.09),
          borderRadius: BorderRadius.circular(kEdge),
          border: Border.all(color: color.withOpacity(.35)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 42),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontFamily: 'OpenSans',
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: kNeutralText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    Color fillColor = kAccent,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 26),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'Montserrat',
            ),
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: fillColor,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onTap,
      ),
    );
  }

  Widget _secondaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: Icon(icon, size: 24, color: kPrimary),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
              color: kPrimaryDark,
            ),
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          minimumSize: const Size.fromHeight(60),
          side: const BorderSide(color: kPrimary, width: 1.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onTap,
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
}
