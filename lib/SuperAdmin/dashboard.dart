import 'package:capstone_app/SuperAdmin/admins_page.dart';
import 'package:capstone_app/SuperAdmin/audit_logs_page.dart';
import 'package:capstone_app/SuperAdmin/broadcast_page.dart';
import 'package:capstone_app/SuperAdmin/manage_beneficiaries_page.dart';
import 'package:capstone_app/SuperAdmin/reports_page.dart';
import 'package:capstone_app/SuperAdmin/settings_page.dart';
import 'package:capstone_app/SuperAdmin/users_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kPrimary = Color(0xFF1E40AF);
const kAccent = Color(0xFF059669);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);

class SuperAdminDashboardPage extends StatelessWidget {
  const SuperAdminDashboardPage({super.key});

  Future<int> _fetchUserCount() async {
    final sb = Supabase.instance.client;
    final res = await sb.from('users').select('id');
    return res.length;
  }

  Future<int> _fetchAuditLogsCount() async {
    final sb = Supabase.instance.client;
    final res = await sb.from('audit_logs').select('id');
    return res.length;
  }

  Future<int> _fetchAdminCount() async {
    final sb = Supabase.instance.client;

    // Fetch all admin user IDs from dayung_units
    final units = await sb
        .from('dayung_units')
        .select('president_id, secretary_id, treasurer_id');
    final Set<String> adminIds = {};

    for (final unit in units) {
      if (unit['president_id'] != null) adminIds.add(unit['president_id']);
      if (unit['secretary_id'] != null) adminIds.add(unit['secretary_id']);
      if (unit['treasurer_id'] != null) adminIds.add(unit['treasurer_id']);
    }

    // Fetch all collector user IDs from dayung_collectors
    final collectors = await sb.from('dayung_collectors').select('user_id');
    for (final c in collectors) {
      if (c['user_id'] != null) adminIds.add(c['user_id']);
    }

    return adminIds.length;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeBg = isDark ? const Color(0xFF18181B) : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: themeBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildModernHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  decoration: const BoxDecoration(
                    color: kCardBg,
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
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 600;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildOverviewCards(context, isWide: isWide),
                          const SizedBox(height: 24),
                          _buildQuickActions(context, isWide: isWide),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernHeader() {
    return Container(
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E40AF), Color(0xFF3B82F6), Color(0xFFF8FAFC)],
          stops: [0.0, 0.65, 0.85],
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.8),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: kPrimary.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.security, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              'SuperAdmin Dashboard',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCards(BuildContext context, {required bool isWide}) {
    return FutureBuilder<int>(
      future: _fetchUserCount(),
      builder: (context, snapshot) {
        final totalUsers = snapshot.hasData ? snapshot.data.toString() : '...';
        final stats = [
          _modernStatCard(
            icon: Icons.people,
            title: 'Total Users',
            value: totalUsers,
            color: kPrimary,
            bgColor: const Color(0xFFEFF6FF),
          ),
          FutureBuilder<int>(
            future: _fetchAdminCount(),
            builder: (context, snapshot) {
              final value = snapshot.hasData ? snapshot.data.toString() : '...';
              return _modernStatCard(
                icon: Icons.admin_panel_settings,
                title: 'Admins',
                value: value,
                color: Colors.deepPurple,
                bgColor: const Color(0xFFEDE9FE),
              );
            },
          ),
          _modernStatCard(
            icon: Icons.analytics,
            title: 'Reports',
            value: '8', // TODO: Replace with real value
            color: Colors.orange,
            bgColor: const Color(0xFFFFF7ED),
          ),
          FutureBuilder<int>(
            future: _fetchAuditLogsCount(),
            builder: (context, snapshot) {
              final value = snapshot.hasData ? snapshot.data.toString() : '...';
              return _modernStatCard(
                icon: Icons.list_alt,
                title: 'Audit Logs',
                value: value,
                color: Colors.teal,
                bgColor: const Color(0xFFE0F2F1),
              );
            },
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'System Overview',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: kPrimary,
                fontFamily: 'Montserrat',
              ),
            ),
            const SizedBox(height: 16),
            isWide
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: stats
                        .map(
                          (card) => Flexible(
                            fit: FlexFit.loose,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: card,
                            ),
                          ),
                        )
                        .toList(),
                  )
                : Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: stats
                        .map(
                          (card) => SizedBox(
                            width:
                                (MediaQuery.of(context).size.width -
                                    24 * 2 -
                                    12) /
                                2,
                            child: card,
                          ),
                        )
                        .toList(),
                  ),
          ],
        );
      },
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
      constraints: const BoxConstraints(minHeight: 150), // <-- Add this line!
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, {required bool isWide}) {
    final actions = [
      _modernActionCard(
        icon: Icons.admin_panel_settings,
        title: 'Manage Admins',
        color: Colors.deepPurple,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SuperAdminAdminsPage()),
        ),
      ),
      _modernActionCard(
        icon: Icons.people,
        title: 'Manage Users',
        color: kPrimary,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SuperAdminUsersPage()),
        ),
      ),
      _modernActionCard(
        icon: Icons.family_restroom,
        title: 'Manage Beneficiaries',
        color: Colors.purple,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ManageBeneficiariesPage()),
        ),
      ),
      _modernActionCard(
        icon: Icons.settings,
        title: 'System Settings',
        color: Colors.green,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SuperAdminSettingsPage()),
        ),
      ),
      _modernActionCard(
        icon: Icons.analytics,
        title: 'View Reports',
        color: Colors.orange,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SuperAdminReportsPage()),
        ),
      ),
      _modernActionCard(
        icon: Icons.list_alt,
        title: 'Audit Logs',
        color: Colors.teal,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SuperAdminAuditLogsPage()),
        ),
      ),
      _modernActionCard(
        icon: Icons.campaign,
        title: 'Broadcast Announcement',
        color: Colors.red,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SuperAdminBroadcastPage()),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: kPrimary,
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(height: 12),
        isWide
            ? Wrap(
                spacing: 16,
                runSpacing: 16,
                children: actions
                    .map((a) => SizedBox(width: 260, child: a))
                    .toList(),
              )
            : Column(
                children: actions
                    .map(
                      (a) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: a,
                      ),
                    )
                    .toList(),
              ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Logout'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: () async {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/login', (r) => false);
          },
        ),
      ],
    );
  }

  Widget _modernActionCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 18,
                color: kSubText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
