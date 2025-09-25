import 'dart:convert';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/pages/claims.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/pages/paymentmethod.dart';
import 'package:capstone_app/pages/contributionhistory.dart';
import 'package:capstone_app/pages/recentdeathnotices.dart';
import 'package:capstone_app/profile/profile.dart' hide kPrimary, kWarn;
import 'package:capstone_app/screens/selectdayung.dart';
import 'package:capstone_app/Auth/login.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/widgets/member_header.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Shared palette aligned to Secretary
const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);

class MemberDashboard extends StatefulWidget {
  const MemberDashboard({super.key});
  @override
  State<MemberDashboard> createState() => _MemberDashboardState();
}

class _MemberDashboardState extends State<MemberDashboard> {
  final supabase = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();

  User? _user;
  String _fullName = 'Member';
  String? _profileUrl;

  Map<String, dynamic>? _selectedDayungUnitObj;
  String? selectedDayungUnit;

  bool _showNavBar = true;
  bool _loadingUser = true;
  int _selectedIndex = 0;

  // Dynamic stats
  int _activeMembersCount = 0;
  bool _loadingActiveMembers = true;

  List<Map<String, dynamic>> _recentCertificates = [];
  bool _loadingCertificates = true;

  double _pendingPaymentsAmount = 0;
  int _pendingPaymentCount = 0;
  bool _loadingPending = true;

  @override
  void initState() {
    super.initState();
    _init();
    _scrollController.addListener(() {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final current = _scrollController.position.pixels;
      if (current >= maxScroll && _showNavBar) {
        setState(() => _showNavBar = false);
      } else if (current < maxScroll && !_showNavBar) {
        setState(() => _showNavBar = true);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOrAskDayung();
    });
  }

  Future<void> _init() async {
    await _loadUserData();
    await _reloadDayungFromPrefs();
    await _fetchAllStats();
  }

  Future<void> _fetchAllStats() async {
    await Future.wait([
      _fetchActiveMembers(),
      _fetchRecentDeaths(),
      _fetchPendingPayments(),
    ]);
  }

  Future<void> _reloadDayungFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final unitJson = prefs.getString('selectedDayungUnit');
    if (unitJson == null) {
      setState(() {
        selectedDayungUnit = null;
        _selectedDayungUnitObj = null;
      });
      return;
    }
    try {
      final unit = jsonDecode(unitJson);
      setState(() {
        selectedDayungUnit = unit['name'];
        _selectedDayungUnitObj = Map<String, dynamic>.from(unit as Map);
      });
    } catch (_) {
      await prefs.remove('selectedDayungUnit');
      setState(() {
        selectedDayungUnit = null;
        _selectedDayungUnitObj = null;
      });
    }
  }

  Future<void> _refreshDashboard() async {
    await _loadUserData();
    await _reloadDayungFromPrefs();
    await _fetchAllStats();
  }

  Future<void> _loadUserData() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      _redirectToLogin();
      return;
    }
    try {
      final response = await supabase
          .from('users')
          .select('full_name, sex, profile_url')
          .eq('id', currentUser.id)
          .maybeSingle();

      final full = (response?['full_name'] as String?)?.trim();
      final sex = response?['sex'];
      setState(() {
        _user = currentUser;
        _fullName = '${_getTitle(sex)} ${full ?? 'Member'}'.trim();
        _profileUrl = (response?['profile_url'] as String?)?.trim();
        _loadingUser = false;
      });
    } catch (_) {
      setState(() {
        _loadingUser = false;
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

  Future<void> _loadOrAskDayung() async {
    final prefs = await SharedPreferences.getInstance();
    final unitJson = prefs.getString('selectedDayungUnit');
    if (unitJson == null) {
      _navigateAndPickUnit();
    } else {
      try {
        final unit = jsonDecode(unitJson);
        setState(() {
          selectedDayungUnit = unit['name'];
          _selectedDayungUnitObj = Map<String, dynamic>.from(unit as Map);
        });
      } catch (_) {
        await prefs.remove('selectedDayungUnit');
      }
    }
  }

  Future<void> _navigateAndPickUnit() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SelectDayungPage()),
    );
    if (result != null && result is Map) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selectedDayungUnit', jsonEncode(result));
      setState(() {
        selectedDayungUnit = result['name'];
        _selectedDayungUnitObj = Map<String, dynamic>.from(result);
      });
      context.read<DayungUnitProvider>().setDayungUnit(result['name']);
      await _fetchAllStats();
    }
  }

  Future<void> _fetchActiveMembers() async {
    setState(() => _loadingActiveMembers = true);
    try {
      final id = _selectedDayungUnitObj?['id'];
      if (id == null) {
        _activeMembersCount = 0;
      } else {
        final rows = await supabase
            .from('users')
            .select('id')
            .eq('dayung_unit_id', id)
            .eq('status', 'approved');
        _activeMembersCount = (rows as List).length;
      }
    } catch (_) {
      _activeMembersCount = 0;
    } finally {
      if (mounted) setState(() => _loadingActiveMembers = false);
    }
  }

  Future<void> _fetchRecentDeaths() async {
    setState(() => _loadingCertificates = true);
    try {
      final unitId = _selectedDayungUnitObj?['id'];
      List data;
      try {
        // Try filtering by dayung_unit_id if column exists
        data = await supabase
            .from('certificates')
            .select('id, deceased_name, submitted_at, dayung_unit_id')
            .eq('dayung_unit_id', unitId)
            .order('submitted_at', ascending: false)
            .limit(5);
      } catch (_) {
        // Fallback: no column
        data = await supabase
            .from('certificates')
            .select('id, deceased_name, submitted_at')
            .order('submitted_at', ascending: false)
            .limit(5);
      }
      _recentCertificates = data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      _recentCertificates = [];
    } finally {
      if (mounted) setState(() => _loadingCertificates = false);
    }
  }

  Future<void> _fetchPendingPayments() async {
    setState(() => _loadingPending = true);
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) {
        _pendingPaymentsAmount = 0;
        _pendingPaymentCount = 0;
      } else {
        bool done = false;
        // RPC attempt
        try {
          final rpc = await supabase.rpc(
            'member_pending_payments',
            params: {'p_member_id': uid},
          );
          if (rpc is Map && rpc['total_amount'] != null) {
            _pendingPaymentsAmount =
                double.tryParse(rpc['total_amount'].toString()) ?? 0;
            _pendingPaymentCount =
                int.tryParse(rpc['pending_count'].toString()) ?? 0;
            done = true;
          }
        } catch (_) {}
        if (!done) {
          // Table fallback
          try {
            final rows = await supabase
                .from('payments')
                .select('amount, status, user_id')
                .eq('user_id', uid);
            double total = 0;
            int cnt = 0;
            for (final r in rows as List) {
              final m = r as Map;
              final status = (m['status'] ?? '').toString().toLowerCase();
              if (status == 'pending') {
                total += (m['amount'] is num)
                    ? (m['amount'] as num).toDouble()
                    : 0;
                cnt++;
              }
            }
            _pendingPaymentsAmount = total;
            _pendingPaymentCount = cnt;
          } catch (_) {
            _pendingPaymentsAmount = 0;
            _pendingPaymentCount = 0;
          }
        }
      }
    } catch (_) {
      _pendingPaymentsAmount = 0;
      _pendingPaymentCount = 0;
    } finally {
      if (mounted) setState(() => _loadingPending = false);
    }
  }

  void _redirectToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const Login()),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<Widget> get _pages => [
    _buildHomePage(context),
    const ContributionHistory(),
    const ClaimsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          SafeArea(
            child: IndexedStack(index: _selectedIndex, children: _pages),
          ),
          Positioned(
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
                    height: 76,
                    margin: EdgeInsets.symmetric(
                      horizontal: isWide ? width * 0.15 : 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(36),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: Colors.grey.shade300,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _navBarItem(
                          icon: Icons.home,
                          label: 'Home',
                          selected: _selectedIndex == 0,
                          onTap: () => setState(() => _selectedIndex = 0),
                        ),
                        _navBarItem(
                          icon: FontAwesomeIcons.globe,
                          label: 'Contributions',
                          selected: _selectedIndex == 1,
                          onTap: () => setState(() => _selectedIndex = 1),
                        ),
                        _navBarItem(
                          icon: Icons.receipt_long,
                          label: 'Claims',
                          selected: _selectedIndex == 2,
                          onTap: () => setState(() => _selectedIndex = 2),
                        ),
                      ],
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

  Widget _navBarItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: selected ? kPrimary : kNeutralText,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? kPrimary : kNeutralText, size: 32),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: selected ? kPrimary : kNeutralText,
                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                fontSize: 14,
                letterSpacing: 0.2,
                fontFamily: 'OpenSans',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomePage(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;
    return RefreshIndicator(
      onRefresh: _refreshDashboard,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              child: _buildHeader(),
            ),
            const SizedBox(height: 16),
            const Divider(thickness: 1, height: 24, color: Colors.grey),
            const SizedBox(height: 13),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildWelcomeMessage(),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildCards(isWide),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildNextPaymentCard(isWide),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildRecentActivity(isWide),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final dayungName = _selectedDayungUnitObj?['name'] ?? 'Dayung';
    final barangay = _selectedDayungUnitObj?['barangay'];
    final city = _selectedDayungUnitObj?['city'];
    final subtitle = (barangay != null)
        ? '$barangay${city != null ? ', $city' : ''}'
        : null;

    return MemberHeader(
      title: dayungName,
      subtitle: subtitle,
      profileUrl: _profileUrl,
      onNotificationTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotificationPage()),
        );
      },
      onProfileTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfilePage()),
        );
      },
    );
  }

  Widget _buildWelcomeMessage() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          'Maayung buntag,\n$_fullName!',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: kPrimaryDark, // CHANGED to match secretary header tone
            fontFamily: 'Montserrat',
            letterSpacing: .6,
            height: 1.1,
          ),
        ),
      ),
    ],
  );

  Widget _buildCards(bool isWide) {
    // Active Members card value
    final activeValue = _loadingActiveMembers
        ? '…'
        : _activeMembersCount.toString();

    // Recent deaths card lines
    String recentDeathsValue;
    if (_loadingCertificates) {
      recentDeathsValue = 'Loading…';
    } else if (_recentCertificates.isEmpty) {
      recentDeathsValue = 'None';
    } else {
      final names = _recentCertificates
          .map((e) => (e['deceased_name'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
      if (names.length <= 2) {
        recentDeathsValue = names.join('\n');
      } else {
        recentDeathsValue =
            '${names.take(2).join('\n')}\n+${names.length - 2} more';
      }
    }

    final pendingValue = _loadingPending
        ? '…'
        : '₱ ${_pendingPaymentsAmount.toStringAsFixed(0)}';
    final pendingSubtitle = _loadingPending
        ? ''
        : (_pendingPaymentCount > 0
              ? '$_pendingPaymentCount pending'
              : 'No pending');

    final cards = [
      _dashboardCard(
        color: const Color(0xFFD8EEFF),
        icon: Icons.groups,
        iconColor: Colors.blue[700],
        title: "Total Active\nMembers",
        value: activeValue,
      ),
      _dashboardCard(
        color: const Color(0xFFFFDAF6),
        icon: FontAwesomeIcons.dove,
        iconColor: Colors.purple[400],
        title: "Recent Deaths",
        value: recentDeathsValue,
        isDeathNotice: true,
        context: context,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RecentDeathNotices()),
          );
        },
      ),
      _dashboardCard(
        color: const Color(0xFFFEFBDC),
        icon: Icons.account_balance_wallet,
        iconColor: Colors.orange[700],
        title: "Pending\nPayments",
        value: pendingValue,
        subtitle: pendingSubtitle,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            children: cards
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: c,
                  ),
                )
                .toList(),
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
      },
    );
  }

  Widget _dashboardCard({
    required Color color,
    required IconData icon,
    required Color? iconColor,
    required String title,
    required String value,
    String subtitle = "",
    double iconSize = 30,
    bool isDeathNotice = false,
    BuildContext? context,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 220,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: kPrimary.withOpacity(.12), // NEW ripple color
        highlightColor: kPrimary.withOpacity(.05),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade300, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: iconSize, color: iconColor),
              const SizedBox(height: 8),
              AutoSizeText(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: kNeutralText,
                  fontFamily: 'Montserrat',
                  height: 1.15,
                ),
                maxLines: 2,
                minFontSize: 11,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: isDeathNotice
                    ? _recentDeathsValueWidget(value, context)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AutoSizeText(
                            value,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 30,
                              color: kNeutralText,
                              fontFamily: 'Montserrat',
                            ),
                            maxLines: 2,
                            minFontSize: 12,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          if (subtitle.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: AutoSizeText(
                                subtitle,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: kSubtleText.withOpacity(.9),
                                  fontFamily: 'OpenSans',
                                ),
                                maxLines: 2,
                                minFontSize: 10,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentDeathsValueWidget(String raw, BuildContext? ctx) {
    if (raw == 'Loading…') {
      return const Center(
        child: SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: kPrimary, // unified color
          ),
        ),
      );
    }
    if (raw == 'None') {
      return const Center(
        child: Text(
          "None",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: 'Montserrat',
            color: kNeutralText,
          ),
        ),
      );
    }
    final lines = raw.split('\n');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ...lines
            .where((l) => !l.startsWith('+'))
            .map(
              (name) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(
                      FontAwesomeIcons.dove,
                      size: 14,
                      color: kNeutralText,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: kNeutralText,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        if (lines.any((l) => l.startsWith('+')))
          Text(
            lines.firstWhere((l) => l.startsWith('+')),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
              color: kSubtleText,
            ),
          ),
        TextButton(
          onPressed: () {
            if (ctx != null) {
              Navigator.push(
                ctx,
                MaterialPageRoute(builder: (_) => const RecentDeathNotices()),
              );
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: kPrimary,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            "View All",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              fontFamily: 'Montserrat',
            ),
          ),
        ),
      ],
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
        color: kPrimary.withOpacity(.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kPrimary.withOpacity(.25), width: 1.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Next Payment Due:',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: kPrimaryDark,
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
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: kPrimaryDark,
                  fontFamily: 'Montserrat',
                  letterSpacing: .5,
                ),
              ),
              const SizedBox(width: 10),
              if (!_loadingPending)
                Text(
                  _pendingPaymentCount > 0
                      ? '($_pendingPaymentCount pending)'
                      : '(No pending)',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'OpenSans',
                    color: kSubtleText.withOpacity(.9),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            dueDate,
            style: TextStyle(
              color: kSubtleText.withOpacity(.9),
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PaymentMethodPage(),
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

  Widget _buildRecentActivity(bool isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Activity',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: kPrimaryDark,
            fontFamily: 'Montserrat',
            letterSpacing: .2,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 40 : 20,
            vertical: isWide ? 24 : 16,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300, width: 1.3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: const [
              _ActivityRow(
                icon: Icons.calendar_today,
                color: kPrimary,
                text: 'Jun 15, 2025',
              ),
              SizedBox(height: 12),
              _ActivityRow(
                icon: Icons.attach_money,
                color: kAccent,
                text: 'Paid ₱200 contribution',
              ),
              SizedBox(height: 12),
              _ActivityRow(
                icon: Icons.check_circle,
                color: kAccent,
                text: 'Claim approved',
              ),
            ],
          ),
        ),
      ],
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
