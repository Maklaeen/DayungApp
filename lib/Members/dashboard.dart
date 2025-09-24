import 'package:capstone_app/pages/claims.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/pages/paymentmethod.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:capstone_app/screens/selectdayung.dart';
import 'package:capstone_app/settings/dayung_provider.dart';
import 'package:flutter/material.dart';
import 'package:capstone_app/pages/contributionhistory.dart';
import 'package:capstone_app/pages/recentdeathnotices.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/Auth/login.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:capstone_app/settings/user_provider.dart';
import 'dart:convert';

// Senior-friendly palette (high contrast, softer background)
const kBg = Color(0xFFFAFAF7); // warm off-white
const kText = Color(0xFF1F2937); // dark neutral text
const kSubText = Color(0xFF4B5563); // softer dark gray
const kAccent = Color(0xFF3E8E7E); // muted teal accent

class MemberDashboard extends StatefulWidget {
  const MemberDashboard({super.key});

  @override
  State<MemberDashboard> createState() => _MemberDashboardState();
}

class _MemberDashboardState extends State<MemberDashboard> {
  final ScrollController _scrollController = ScrollController();

  String? get profileUrl => context.watch<UserProvider>().profileUrl;

  Map<String, dynamic>? _selectedDayungUnitObj;

  bool _showNavBar = true;
  String? selectedDayungUnit;
  User? _user;
  String _fullName = 'Member';
  bool _loading = true;
  int _selectedIndex = 0;
  String? _profileUrl;

  @override
  void initState() {
    super.initState();
    _loadUserData();

    _scrollController.addListener(() {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;

      if (currentScroll >= maxScroll && _showNavBar) {
        setState(() => _showNavBar = false);
      } else if (currentScroll < maxScroll && !_showNavBar) {
        setState(() => _showNavBar = true);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOrAskDayung();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Future<void> _reloadDayungFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final unitJson = prefs.getString('selectedDayungUnit');
    if (unitJson == null) {
      setState(() {
        // Do not navigate on refresh; just keep current state
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
    await Future.wait([_loadUserData(), _reloadDayungFromPrefs()]);
  }

  Future<void> _loadUserData() async {
    final currentUser = Supabase.instance.client.auth.currentUser;

    if (currentUser != null) {
      try {
        final userId = currentUser.id;

        final response = await Supabase.instance.client
            .from('users')
            .select('full_name, sex, profile_url')
            .eq('id', userId)
            .maybeSingle();

        final full = (response?['full_name'] as String?)?.trim();
        final sex = response?['sex'];
        setState(() {
          _user = currentUser;
          _fullName = '${_getTitle(sex)} ${full ?? 'Member'}'.trim();
          _profileUrl = (response?['profile_url'] as String?)?.trim();
          _loading = false;
        });
      } catch (_) {
        setState(() {
          _loading = false;
          _fullName = 'Member';
        });
      }
    } else {
      _redirectToLogin();
    }
  }

  String _getTitle(dynamic sex) {
    final s = (sex ?? '').toString().toLowerCase().trim();
    if (s == 'male') return 'Mr.';
    if (s == 'female') return 'Mrs.';
    return '';
  }

  void _redirectToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const Login()),
    );
  }

  Future<void> _loadOrAskDayung() async {
    final prefs = await SharedPreferences.getInstance();
    final unitJson = prefs.getString('selectedDayungUnit');
    if (unitJson == null) {
      _navigateAndPickUnit();
    } else {
      final unit = jsonDecode(unitJson);
      setState(() {
        selectedDayungUnit = unit['name'];
        _selectedDayungUnitObj = Map<String, dynamic>.from(unit as Map);
      });
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
    }
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
                    height: 76, // larger touch target
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
          foregroundColor: selected ? kAccent : kText,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? kAccent : kText, size: 32),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: selected ? kAccent : kText,
                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                fontSize: 18,
                letterSpacing: 0.2,
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
              child: _buildCards(context, isWide),
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
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;
    final dayungName = _selectedDayungUnitObj?['name'] ?? 'Dayung';
    final barangay = _selectedDayungUnitObj?['barangay'];
    final city = _selectedDayungUnitObj?['city'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AutoSizeText(
              dayungName,
              style: TextStyle(
                fontSize: isWide ? 36 : 28,
                fontWeight: FontWeight.bold,
                color: kText,
                fontFamily: 'Montserrat',
              ),
              maxLines: 1,
              minFontSize: 20,
              overflow: TextOverflow.ellipsis,
            ),
            if (barangay != null)
              Text(
                '$barangay${city != null ? ', $city' : ''}',
                style: TextStyle(
                  fontSize: isWide ? 16 : 13,
                  color: kSubText,
                  fontFamily: 'OpenSans',
                ),
              ),
          ],
        ),
        Row(
          children: [
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NotificationPage(),
                  ),
                );
              },
              child: Icon(
                Icons.notifications_none,
                color: kAccent,
                size: isWide ? 36 : 28,
              ),
            ),
            const SizedBox(width: 18),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfilePage()),
                );
              },
              child: CircleAvatar(
                backgroundColor: kAccent,
                backgroundImage:
                    (_profileUrl != null && _profileUrl!.isNotEmpty)
                    ? NetworkImage(_profileUrl!)
                    : null,
                child: (_profileUrl == null || _profileUrl!.isEmpty)
                    ? const Icon(
                        Icons.account_circle,
                        size: 36,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWelcomeMessage() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          'Maayung buntag,\n$_fullName!',
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: kText,
            fontFamily: 'Montserrat',
            letterSpacing: 1,
            height: 1.1,
          ),
        ),
      ),
    ],
  );

  // Cards/boxes layout unchanged below
  Widget _buildCards(BuildContext context, bool isWide) {
    final cards = [
      _dashboardCard(
        color: const Color(0xFFD8EEFF),
        icon: Icons.groups,
        iconColor: Colors.blue[700],
        title: "Total Active\nMembers",
        value: "259",
        valuePrefix: "",
        subtitle: "",
        iconSize: 30,
      ),
      _dashboardCard(
        color: const Color(0xFFFFDAF6),
        icon: FontAwesomeIcons.dove,
        iconColor: Colors.purple[400],
        title: "Recent Deaths",
        value: "Inday H.\nPedro M.",
        valuePrefix: "",
        subtitle: "",
        iconSize: 30,
        isDeathNotice: true,
        context: context,
      ),
      _dashboardCard(
        color: const Color(0xFFFEFBDC),
        icon: Icons.account_balance_wallet,
        iconColor: Colors.orange[700],
        title: "Pending\nPayments",
        value: "₱ 21,900",
        valuePrefix: "",
        iconSize: 30,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            children: cards
                .map(
                  (card) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: card,
                  ),
                )
                .toList(),
          );
        } else {
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
      },
    );
  }

  Widget _dashboardCard({
    required Color color,
    required IconData icon,
    required Color? iconColor,
    required String title,
    required String value,
    String valuePrefix = "",
    String subtitle = "",
    double iconSize = 32,
    bool isDeathNotice = false,
    BuildContext? context,
  }) {
    return SizedBox(
      height: 220, // fixed height for all cards (unchanged)
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade300, width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: iconSize, color: iconColor),
              const SizedBox(height: 8),
              AutoSizeText(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.black87,
                  fontFamily: 'Montserrat',
                ),
                maxLines: 2,
                minFontSize: 12,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: isDeathNotice
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...value
                              .split('\n')
                              .map(
                                (name) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        FontAwesomeIcons.dove,
                                        size: 14,
                                        color: Colors.black87,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          name,
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
                              )
                              .toList(),
                          Flexible(
                            child: TextButton(
                              onPressed: () {
                                if (context != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const RecentDeathNotices(),
                                    ),
                                  );
                                }
                              },
                              child: const Text(
                                "View All",
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AutoSizeText(
                            "$valuePrefix$value",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 28,
                              color: Colors.black,
                              fontFamily: 'Montserrat',
                            ),
                            maxLines: 1,
                            minFontSize: 12,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle.isNotEmpty)
                            AutoSizeText(
                              subtitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.black87,
                                fontFamily: 'Montserrat',
                              ),
                              maxLines: 2,
                              minFontSize: 10,
                              overflow: TextOverflow.ellipsis,
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

  Widget _buildNextPaymentCard(bool isWide) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isWide ? 32 : 24),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE9FEC8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Next Payment Due:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 28,
              color: Colors.black,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              Text(
                '₱ ',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                  fontFamily: 'Montserrat',
                ),
              ),
              Text(
                '200',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                  fontFamily: 'Montserrat',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Due by: July 19, 2025',
            style: TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PaymentMethodPage(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4285C5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
              ),
              child: const Text(
                'Pay Now',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontFamily: 'Montserrat',
                ),
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
        const Text(
          'Recent Activity',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.black,
            fontFamily: 'Montserrat',
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 40 : 20,
            vertical: isWide ? 24 : 16,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300, width: 1.5),
          ),
          child: Column(
            children: [
              Row(
                children: const [
                  Icon(Icons.calendar_today, color: Colors.redAccent),
                  SizedBox(width: 12),
                  Text(
                    'Jun 15, 2025',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: const [
                  Icon(Icons.attach_money, color: Colors.green),
                  SizedBox(width: 12),
                  Text(
                    '₱23,000',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: const [
                  Icon(Icons.check_circle, color: Colors.teal),
                  SizedBox(width: 12),
                  Text(
                    'Assistance received',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
