import 'package:flutter/material.dart';

void main() => runApp(const DayungApp());

class DayungApp extends StatelessWidget {
  const DayungApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dayung',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2956A3)),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const PresidentDashboardPage(),
    );
  }
}

class PresidentDashboardPage extends StatelessWidget {
  const PresidentDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Column(
          children: [
            const _TopBar(),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _GreetingRow(),
                    const SizedBox(height: 14),
                    // Four cards grid
                    LayoutBuilder(
  builder: (context, constraints) {
    final isSmallDevice = constraints.maxWidth < 360;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: isSmallDevice ? 0.9 : 1.1, // Adjust for small screens
      children: const [
        StatCard(
          bg: Color(0xFFE6F0FF),
          title: 'Total Active\nMembers',
          bigText: '259',
          footerText: 'View All',
          leading: Icons.groups_rounded,
        ),
        StatCard(
          bg: Color(0xFFFBE6F3),
          title: 'Recent Death\nNotices',
          customListBullets: ['Inday H.', 'Pedro M.'],
          footerText: 'View All',
          leading: Icons.local_florist_rounded,
        ),
        StatCard(
          bg: Color(0xFFFDE6EF),
          title: 'Pending Payments',
          bigText: '₱ 21,900',
          subText: 'From 219 members',
          footerText: '',
          leading: Icons.account_balance_wallet_rounded,
        ),
        StatCard(
          bg: Color(0xFFE6F0FF),
          title: 'Manage Roles',
          bigText: '',
          footerText: 'Manage',
          leading: Icons.manage_accounts_rounded,
        ),
      ],
    );
  },
),
                    const SizedBox(height: 16),
                    const _PostAnnouncementButton(),
                    const SizedBox(height: 18),
                    const _UpcomingText(),
                    const SizedBox(height: 12),
                    const _ContributionBarChartCard(),
                    const SizedBox(height: 80), // space above bottom nav
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const _BottomNav(),
    );
  }
}

/* ------------------------------- TOP BAR -------------------------------- */

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: Colors.white,
      child: Row(
        children: [
          // App name
          Text(
            'Dayung',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.black.withOpacity(0.9),
              letterSpacing: 0.4,
            ),
          ),
          const Spacer(),
          // Notification bell with badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_active_rounded),
                onPressed: () {},
                color: const Color(0xFFFFB703),
              ),
              Positioned(
                right: 8,
                top: 6,
                child: Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '1',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Settings gear + profile circle (combined in one avatar w/ gear bg)
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon: const Icon(
                Icons.settings_rounded,
                color: Color(0xFF4A6BD8),
              ),
              onPressed: () {},
              tooltip: 'Settings',
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
    return Row(
      children: [
        // Greeting
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Maayung buntag,',
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.black.withOpacity(0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'President!',
                style: TextStyle(
                  fontSize: 26,
                  height: 1.05,
                  color: Colors.black.withOpacity(0.9),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        // Profile avatar
        CircleAvatar(
          radius: 28,
          backgroundColor: const Color(0xFFEAEAEA),
          child: Icon(Icons.person, size: 34, color: Colors.blue.shade700),
        ),
      ],
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

  const StatCard({
    super.key,
    required this.bg,
    required this.title,
    required this.leading,
    this.bigText = '',
    this.subText = '',
    this.footerText = '',
    this.customListBullets,
  });

  @override
  Widget build(BuildContext context) {
    final isListCard =
        customListBullets != null && customListBullets!.isNotEmpty;

    return Material(
      color: bg,
      elevation: 1,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {}, // Add navigation or actions
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Top-centered icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  leading,
                  size: 32,
                  color: Colors.blueAccent.shade700, // Eye-catching color
                ),
              ),
              const SizedBox(height: 10),

              // Title
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.5,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withOpacity(0.85),
                ),
              ),
              const SizedBox(height: 10),

              // Big Text / List
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
                              Icon(
                                Icons.local_florist_rounded,
                                size: 16,
                                color: Colors.pink.shade400,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  item,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                )
              else ...[
                if (bigText.isNotEmpty)
                  Text(
                    bigText,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                if (subText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      subText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black.withOpacity(0.65),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],

              const Spacer(),

              // Footer Text
              if (footerText.isNotEmpty)
                Text(
                  footerText,
                  style: const TextStyle(
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
      color: const Color(0xFF2956A3),
      borderRadius: BorderRadius.circular(18),
      elevation: 1,
      child: InkWell(
        onTap: () {},
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
          fontSize: 18,
          height: 1.25,
          color: Colors.black.withOpacity(0.85),
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
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.black.withOpacity(0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Contribution Records by Year',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: _MiniBarChart(
                // simplified sample values for 2023–2025
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
    final barColor = const Color(0xFF2D63D6);
    return LayoutBuilder(
      builder: (context, c) {
        final barWidth = (c.maxWidth - 40) / (values.length * 2);
        return Stack(
          children: [
            // horizontal grid lines (0, 5, 10, 15, 20, 25)
            Positioned.fill(
              child: CustomPaint(painter: _GridLinesPainter(maxY: maxY)),
            ),
            // bars
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
                            fontSize: 12,
                            color: Colors.black.withOpacity(0.75),
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
      // left axis labels
      final tp = TextPainter(
        text: TextSpan(
          text: y == 0 ? '0' : '$y',
          style: TextStyle(
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
          style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.65)),
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

/* ---------------------------- BOTTOM NAVIGATION ------------------------- */

class _BottomNav extends StatelessWidget {
  const _BottomNav();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: const [
          _NavItem(icon: Icons.home_rounded, label: 'Home', active: true),
          _NavItem(
            icon: Icons.volunteer_activism_rounded,
            label: 'Contributions',
          ),
          _NavItem(icon: Icons.description_rounded, label: 'Claims'),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _NavItem({
    required this.icon,
    required this.label,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF2D63D6) : Colors.black54;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 30, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                color: color,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
