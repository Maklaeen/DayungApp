import 'package:capstone_app/President/manage_roles.dart';
import 'package:capstone_app/President/post_announcement.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/profile/profile.dart';

// Palette aligned with Secretary
const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kWarn = Color(0xFFF57C00);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);

class PresidentDashboardPage extends StatefulWidget {
  const PresidentDashboardPage({super.key});

  @override
  State<PresidentDashboardPage> createState() => _PresidentDashboardPageState();
}

class _PresidentDashboardPageState extends State<PresidentDashboardPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  int _activeMembersCount = 0;
  List<String> _recentDeaths = [];
  int? _lastRoleUnitId;
  int _pendingMembers = 0;
  num _pendingAmount = 0;

  int _currentIndex = 0;
  bool _showNavBar = true;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provUnit = context.read<DayungRoleProvider>().unitId;
      _maybeOnProviderUnitChanged(provUnit);
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ids = await _managedDayungIds();
      await Future.wait([
        _fetchActiveMembersCount(ids),
        _fetchRecentDeaths(ids),
        _fetchPendingPayments(ids),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _maybeOnProviderUnitChanged(int? newUnitId) {
    if (newUnitId == _lastRoleUnitId) return;
    _lastRoleUnitId = newUnitId;
    _load(); // reload all stats (managed dayungs list may differ visually)
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
    _recentDeaths = List<Map<String, dynamic>>.from(rows)
        .map((e) => (e['name'] ?? 'Member') as String)
        .toList();
  }

  Future<void> _fetchPendingPayments(List<int> ids) async {
    // TODO: Replace with your real query (e.g., dues/payments tables).
    _pendingMembers = 0;
    _pendingAmount = 0;
  }

  List<Widget> get _pages => [
    _buildHomePage(context),
    const Placeholder(child: Center(child: Text("Contributions"))),
    const Placeholder(child: Center(child: Text("Claims"))),
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
      backgroundColor: kBg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                const _TopBar(),
                const Divider(height: 1, color: Color(0xFFE1E4E8)),
                if (_currentIndex == 0) const _GreetingRow(),
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
    );
  }

  /* ------------------------------- Home page ------------------------------- */
  Widget _buildHomePage(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        return RefreshIndicator(
          onRefresh: _load,
          edgeOffset: 68,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _overviewFourCards(constraints.maxWidth),
                const SizedBox(height: 16),
                const _PostAnnouncementButton(),
                const SizedBox(height: 18),
                const _UpcomingText(),
                const SizedBox(height: 12),
                const _ContributionBarChartCard(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _overviewFourCards(double maxWidth) {
    const gap = 12.0;

    // Target equal height for all cards
    final targetHeight = _cardHeightFor(maxWidth);
    final isTight = maxWidth < 360;
    final crossAxisCount = isTight ? 1 : 2;

    // Compute aspect ratio so Grid gives each tile the same size
    final itemWidth =
        (maxWidth - (gap * (crossAxisCount - 1))) / crossAxisCount;
    final childAspectRatio = itemWidth / targetHeight;

    final cards = <Widget>[
      StatCard(
        bg: const Color(0xFFD8EEFF),
        title: 'Total Active\nMembers',
        bigText: _loading ? '—' : _activeMembersCount.toString(),
        footerText: 'View All',
        leading: Icons.groups_rounded,
      ),
      StatCard(
        bg: const Color(0xFFFFDAF6),
        title: 'Recent Death\nNotices',
        customListBullets: _loading
            ? const []
            : (_recentDeaths.isEmpty
                  ? const ['No recent notices']
                  : _recentDeaths.take(2).toList()),
        footerText: 'View All',
        leading: Icons.local_florist_rounded,
      ),
      StatCard(
        bg: const Color(0xFFFEFBDC),
        title: 'Pending Payments',
        bigText: _loading ? '—' : '₱ ${_pendingAmount.toStringAsFixed(0)}',
        subText: _loading
            ? ''
            : (_pendingMembers > 0
                  ? 'From $_pendingMembers members'
                  : 'All settled'),
        footerText: '',
        leading: Icons.account_balance_wallet_rounded,
      ),
      StatCard(
        bg: const Color(0xFFE6F0FF),
        title: 'Manage Roles',
        leading: Icons.manage_accounts_rounded,
        footerText: 'Manage',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ManageRolesPagePres()),
          );
        },
      ),
    ];

    return GridView.builder(
      itemCount: cards.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: gap,
        mainAxisSpacing: gap,
        childAspectRatio: childAspectRatio, // forces equal visual size
      ),
      itemBuilder: (context, index) => cards[index],
    );
  }

  double _cardHeightFor(double maxWidth) {
    if (maxWidth < 360) return 200; // small phones (when single column)
    if (maxWidth < 500) return 220; // typical phones
    if (maxWidth < 800) return 220; // large phones / small tablets
    return 230; // tablets
  }

  /* ------------------------- Bottom nav (responsive) ------------------------- */
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

/* ------------------------------- TOP BAR -------------------------------- */

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: Colors.white,
      child: Row(
        children: [
          Text(
            'Dayung',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: kPrimaryDark,
              letterSpacing: 0.4,
            ),
          ),
          const Spacer(),
          _iconBtn(
            icon: Icons.notifications_active_rounded,
            color: kWarn,
            tooltip: 'Notifications',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationPage()),
              );
            },
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

/* ------------------------------ GREETING ROW ----------------------------- */

class _GreetingRow extends StatelessWidget {
  const _GreetingRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8), // more breathing room
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, // left-align title
              children: [
                Text(
                  'Maayung buntag,',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 22,
                    color: kNeutralText.withOpacity(0.85),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'President!',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 26,
                    height: 1.05,
                    color: kNeutralText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14), // add gap from the avatar
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
}

/* -------------------------------- CARDS --------------------------------- */

class StatCard extends StatelessWidget {
  final Color bg;
  final String title;
  final String bigText;
  final String subText;
  final String footerText;
  final IconData leading;
  final List<String>? customListBullets;
  final VoidCallback? onTap; // NEW

  const StatCard({
    super.key,
    required this.bg,
    required this.title,
    required this.leading,
    this.bigText = '',
    this.subText = '',
    this.footerText = '',
    this.customListBullets,
    this.onTap, // NEW
  });

  @override
  Widget build(BuildContext context) {
    final isListCard =
        customListBullets != null && customListBullets!.isNotEmpty;

    return Material(
      color: bg,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap, // use per-card handler
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300, width: 1.8),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
          child: Column(
            mainAxisSize: MainAxisSize.max, // fill given height
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // header
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.92),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(leading, size: 30, color: kPrimary),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 15.5,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: kNeutralText,
                    ),
                  ),
                ],
              ),

              // body
              if (isListCard)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: customListBullets!
                      .take(2)
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.local_florist_rounded,
                                size: 16,
                                color: Color(0xFFEC4899),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  item,
                                  style: const TextStyle(
                                    fontFamily: 'OpenSans',
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: kNeutralText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                )
              else
                Column(
                  children: [
                    if (bigText.isNotEmpty)
                      Text(
                        bigText,
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: kNeutralText,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    if (subText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          fontSize: 13,
                          color: kSubtleText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),

              // footer
              if (footerText.isNotEmpty)
                Text(
                  footerText,
                  style: const TextStyle(
                    fontFamily: 'OpenSans',
                    fontSize: 14,
                    color: Color(0xFF2D63D6),
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
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
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PostAnnouncementPage()),
          );
        },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          alignment: Alignment.center,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline, color: Colors.white),
              SizedBox(width: 10),
              Text(
                'Post Announcement',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  color: Colors.white,
                  fontSize: 18.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ------------------------------ UPCOMING TEXT --------------------------- */

class _UpcomingText extends StatelessWidget {
  const _UpcomingText();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Upcoming:  July 16 - Monthly\nMeeting @ 3PM',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 18,
          height: 1.25,
          color: kNeutralText,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/* ------------------------- SIMPLE BAR CHART CARD ------------------------ */

class _ContributionBarChartCard extends StatelessWidget {
  const _ContributionBarChartCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.black.withOpacity(0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Contribution Records by Year',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: kNeutralText,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: _MiniBarChart(
                values: const [14, 20, 13],
                maxY: 25,
                labels: const ['2023', '2024', '2025'],
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

class _MiniBarChart extends StatelessWidget {
  final List<int> values;
  final int maxY;
  final List<String> labels;

  const _MiniBarChart({
    required this.values,
    required this.maxY,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    const barColor = Color(0xFF2D63D6);
    return LayoutBuilder(
      builder: (context, c) {
        final barWidth = (c.maxWidth - 40) / (values.length * 2);
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _GridLinesPainter(maxY: maxY)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 4, 12, 28),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(values.length, (i) {
                  final h = (values[i] / maxY) * (c.maxHeight - 36);
                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: h,
                          width: barWidth,
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          labels[i],
                          style: TextStyle(
                            fontFamily: 'OpenSans',
                            fontSize: 12,
                            color: kSubtleText,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GridLinesPainter extends CustomPainter {
  final int maxY;
  _GridLinesPainter({required this.maxY});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.08)
      ..strokeWidth = 1;

    const leftPad = 26.0;
    const bottomPad = 28.0;
    final chartHeight = size.height - bottomPad - 8;

    for (int y = 0; y <= maxY; y += 5) {
      final dy = size.height - bottomPad - (y / maxY) * chartHeight;
      canvas.drawLine(Offset(leftPad, dy), Offset(size.width - 8, dy), paint);
      final tp = TextPainter(
        text: TextSpan(
          text: y == 0 ? '0' : '$y',
          style: TextStyle(
            fontFamily: 'OpenSans',
            fontSize: 10,
            color: Colors.black.withOpacity(0.6),
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, dy - 6));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
            color: kSubtleText,
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
