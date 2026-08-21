import 'package:capstone_app/SuperAdmin/admins_page.dart';
import 'package:capstone_app/SuperAdmin/audit_logs_page.dart';
import 'package:capstone_app/SuperAdmin/broadcast_page.dart';
import 'package:capstone_app/SuperAdmin/manage_beneficiaries_page.dart';
import 'package:capstone_app/SuperAdmin/organization_page.dart';
import 'package:capstone_app/SuperAdmin/reports_page.dart';
import 'package:capstone_app/SuperAdmin/settings_page.dart';
import 'package:capstone_app/SuperAdmin/superadmin_support.dart';
import 'package:capstone_app/SuperAdmin/users_page.dart';
import 'package:capstone_app/Auth/logout.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SuperAdminDashboardPage extends StatelessWidget {
  const SuperAdminDashboardPage({super.key});

  Future<int> _fetchUserCount() async {
    final res = await Supabase.instance.client.from('users').select('id');
    return res.length;
  }

  Future<int> _fetchAuditLogsCount() async {
    final res = await Supabase.instance.client.from('audit_logs').select('id');
    return res.length;
  }

  Future<int> _fetchAdminCount() async {
    final sb = Supabase.instance.client;
    final units = await sb
        .from('dayung_units')
        .select('president_id, secretary_id, treasurer_id');
    final collectors = await sb.from('dayung_collectors').select('user_id');

    final adminIds = <String>{};
    for (final unit in units) {
      if (unit['president_id'] != null) {
        adminIds.add(unit['president_id'].toString());
      }
      if (unit['secretary_id'] != null) {
        adminIds.add(unit['secretary_id'].toString());
      }
      if (unit['treasurer_id'] != null) {
        adminIds.add(unit['treasurer_id'].toString());
      }
    }
    for (final collector in collectors) {
      if (collector['user_id'] != null) {
        adminIds.add(collector['user_id'].toString());
      }
    }
    return adminIds.length;
  }

  @override
  Widget build(BuildContext context) {
    return SuperAdminAccessGuard(
      title: 'SuperAdmin Dashboard',
      child: Scaffold(
        backgroundColor: superAdminBackground(context),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DashboardHero(
                  onLogout: () async {
                    await showLogoutDialog(context);
                  },
                ),
                const SizedBox(height: 18),
                _buildStatsSection(),
                const SizedBox(height: 18),
                const _SectionHeader(
                  title: 'Quick Actions',
                  subtitle: '',
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 820;
                    final actions = _buildActions(context);
                    if (!wide) {
                      return Column(
                        children: actions
                            .map(
                              (action) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: action,
                              ),
                            )
                            .toList(),
                      );
                    }

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: actions
                          .map((action) => SizedBox(width: 360, child: action))
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'System Overview', subtitle: ''),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 12.0;
            final width = constraints.maxWidth;
            final columns = width >= 1080
                ? 3
                : width >= 700
                ? 2
                : 1;
            final tileWidth =
                (width - (spacing * (columns - 1))).clamp(0, double.infinity) /
                columns;
            final tiles = [
              FutureBuilder<int>(
                future: _fetchUserCount(),
                builder: (context, snapshot) => _StatTile(
                  label: 'Total users',
                  value: snapshot.hasData ? '${snapshot.data}' : '...',
                  hint: 'Public user accounts',
                  icon: Icons.groups_rounded,
                ),
              ),
              FutureBuilder<int>(
                future: _fetchAdminCount(),
                builder: (context, snapshot) => _StatTile(
                  label: 'Assigned officers',
                  value: snapshot.hasData ? '${snapshot.data}' : '...',
                  hint: 'Presidents, secretaries, treasurers, collectors',
                  icon: Icons.admin_panel_settings_rounded,
                ),
              ),
              FutureBuilder<int>(
                future: _fetchAuditLogsCount(),
                builder: (context, snapshot) => _StatTile(
                  label: 'Audit entries',
                  value: snapshot.hasData ? '${snapshot.data}' : '...',
                  hint: 'Recorded administrative actions',
                  icon: Icons.history_rounded,
                ),
              ),
            ];

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: tiles
                  .map(
                    (tile) => SizedBox(
                      width: columns == 1 ? width : tileWidth,
                      child: tile,
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      _ActionTile(
        icon: Icons.people_alt_rounded,
        title: 'Manage Users',
        description:
            'Create accounts, reset passwords, and activate or deactivate access.',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SuperAdminUsersPage()),
        ),
      ),
      _ActionTile(
        icon: Icons.badge_rounded,
        title: 'Manage Admins',
        description:
            'Assign officers and collectors to each Dayung unit with guided controls.',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SuperAdminAdminsPage()),
        ),
      ),
      _ActionTile(
        icon: Icons.family_restroom_rounded,
        title: 'Manage Beneficiaries',
        description:
            'Review beneficiary records and verify eligibility details quickly.',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ManageBeneficiariesPage()),
        ),
      ),
      _ActionTile(
        icon: Icons.account_balance_rounded,
        title: 'Dayung Organization',
        description:
            'Create a Dayung unit by entering its name and location details.',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SuperAdminOrganizationPage()),
        ),
      ),
      _ActionTile(
        icon: Icons.campaign_rounded,
        title: 'Broadcast Announcement',
        description:
            'Send announcements to users, members, officers, or inactive accounts.',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SuperAdminBroadcastPage()),
        ),
      ),
      _ActionTile(
        icon: Icons.bar_chart_rounded,
        title: 'View Reports',
        description:
            'Open the system report dashboard for growth, activity, and revenue trends.',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SuperAdminReportsPage()),
        ),
      ),
      _ActionTile(
        icon: Icons.history_edu_rounded,
        title: 'Audit Logs',
        description:
            'Trace sensitive actions and review the latest administrative events.',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SuperAdminAuditLogsPage()),
        ),
      ),
      _ActionTile(
        icon: Icons.tune_rounded,
        title: 'System Settings',
        description:
            'Control maintenance mode, password policies, and broadcast delivery rules.',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SuperAdminSettingsPage()),
        ),
      ),
    ];
  }
}

class _DashboardHero extends StatelessWidget {
  final Future<void> Function() onLogout;

  const _DashboardHero({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17326B), Color(0xFF2756A4), Color(0xFF0F9D7A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SuperAdmin Dashboard',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    SizedBox(height: 10),
                    // Text(
                    //   'A calmer control center for senior-friendly supervision of users, units, reports, and system-wide actions.',
                    //   style: TextStyle(
                    //     color: Colors.white,
                    //     fontSize: 15,
                    //     height: 1.5,
                    //   ),
                    // ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Logout'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: kSuperAdminText,
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(color: kSuperAdminMuted, height: 1.5),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final IconData icon;

  const _StatTile({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      constraints: const BoxConstraints(minHeight: 190),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kSuperAdminBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kSuperAdminPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: kSuperAdminPrimary),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: kSuperAdminText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: kSuperAdminText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            style: const TextStyle(color: kSuperAdminMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: kSuperAdminBorder),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kSuperAdminPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: kSuperAdminPrimary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: kSuperAdminText,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: const TextStyle(
                        color: kSuperAdminMuted,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 18,
                color: kSuperAdminMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
