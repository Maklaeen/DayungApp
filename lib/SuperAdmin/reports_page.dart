import 'package:capstone_app/SuperAdmin/superadmin_support.dart';
import 'package:flutter/material.dart';

class SuperAdminReportsPage extends StatefulWidget {
  const SuperAdminReportsPage({super.key});

  @override
  State<SuperAdminReportsPage> createState() => _SuperAdminReportsPageState();
}

class _SuperAdminReportsPageState extends State<SuperAdminReportsPage> {
  bool _loading = true;
  Map<String, dynamic>? _report;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await superAdminGetJson('/superadmin/reports');
      if (!mounted) return;
      setState(() => _report = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = Map<String, dynamic>.from(_report?['summary'] ?? const {});
    final monthlyUsers = List<Map<String, dynamic>>.from(
      _report?['monthly_users'] ?? const [],
    );
    final monthlyApprovals = List<Map<String, dynamic>>.from(
      _report?['monthly_approvals'] ?? const [],
    );
    final monthlyRevenue = List<Map<String, dynamic>>.from(
      _report?['monthly_revenue'] ?? const [],
    );
    final roleBreakdown = Map<String, dynamic>.from(
      _report?['role_breakdown'] ?? const {},
    );
    final topUnits = List<Map<String, dynamic>>.from(
      _report?['top_units'] ?? const [],
    );

    final rolePanel = _Panel(
      title: 'Role Mix',
      subtitle: 'A fast breakdown of who is in the system today.',
      child: Column(
        children: [
          _BreakdownRow(
            label: 'SuperAdmins',
            value: '${roleBreakdown['superadmins'] ?? 0}',
          ),
          _BreakdownRow(
            label: 'Officers',
            value: '${roleBreakdown['officers'] ?? 0}',
          ),
          _BreakdownRow(
            label: 'Members',
            value: '${roleBreakdown['members'] ?? 0}',
          ),
          _BreakdownRow(
            label: 'Disabled',
            value: '${roleBreakdown['disabled'] ?? 0}',
          ),
        ],
      ),
    );

    final healthPanel = _Panel(
      title: 'System Health',
      subtitle:
          'Recent operational activity from notifications and audit logs.',
      child: Column(
        children: [
          _BreakdownRow(
            label: 'Dayung units',
            value: '${summary['dayung_units'] ?? 0}',
          ),
          _BreakdownRow(
            label: 'Notifications in 30 days',
            value: '${summary['notifications_last_30_days'] ?? 0}',
          ),
          _BreakdownRow(
            label: 'Audit logs in 30 days',
            value: '${summary['audit_logs_last_30_days'] ?? 0}',
          ),
          _BreakdownRow(
            label: 'Disabled users',
            value: '${summary['disabled_users'] ?? 0}',
          ),
        ],
      ),
    );

    return SuperAdminAccessGuard(
      title: 'System Reports',
      child: Scaffold(
        backgroundColor: superAdminBackground(context),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    children: [
                      _ReportsHero(
                        generatedAt: _report?['generated_at']?.toString(),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _SummaryCard(
                            title: 'Total users',
                            value: '${summary['total_users'] ?? 0}',
                            subtitle: 'All public accounts in the system',
                            color: kSuperAdminPrimary,
                            icon: Icons.groups_rounded,
                          ),
                          _SummaryCard(
                            title: 'Active users',
                            value: '${summary['active_users'] ?? 0}',
                            subtitle: 'Accounts that can sign in now',
                            color: kSuperAdminAccent,
                            icon: Icons.verified_user_rounded,
                          ),
                          _SummaryCard(
                            title: 'Pending applications',
                            value: '${summary['pending_applications'] ?? 0}',
                            subtitle: 'Applications waiting for review',
                            color: kSuperAdminWarn,
                            icon: Icons.pending_actions_rounded,
                          ),
                          _SummaryCard(
                            title: 'Paid total',
                            value: 'PHP ${_money(summary['paid_total'])}',
                            subtitle:
                                '${summary['paid_transactions'] ?? 0} paid transactions',
                            color: const Color(0xFF7A3EF0),
                            icon: Icons.payments_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _Panel(
                        title: 'Growth Trends',
                        subtitle:
                            'The last six months are grouped into quick visual bars for senior-friendly reading.',
                        child: Column(
                          children: [
                            _MiniBarChart(
                              title: 'New accounts',
                              color: kSuperAdminPrimary,
                              items: monthlyUsers,
                              amountMode: false,
                            ),
                            const SizedBox(height: 18),
                            _MiniBarChart(
                              title: 'Approved memberships',
                              color: kSuperAdminAccent,
                              items: monthlyApprovals,
                              amountMode: false,
                            ),
                            const SizedBox(height: 18),
                            _MiniBarChart(
                              title: 'Revenue collected',
                              color: const Color(0xFFB45309),
                              items: monthlyRevenue,
                              amountMode: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 860) {
                            return Column(
                              children: [
                                rolePanel,
                                const SizedBox(height: 12),
                                healthPanel,
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: rolePanel),
                              const SizedBox(width: 12),
                              Expanded(child: healthPanel),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 18),
                      _Panel(
                        title: 'Top Units By Members',
                        subtitle:
                            'These units currently have the highest approved member counts.',
                        child: topUnits.isEmpty
                            ? const Text(
                                'No approved member data yet.',
                                style: TextStyle(color: kSuperAdminMuted),
                              )
                            : Column(
                                children: topUnits
                                    .map(
                                      (unit) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                unit['name']?.toString() ??
                                                    'Unnamed unit',
                                                style: const TextStyle(
                                                  color: kSuperAdminText,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: kSuperAdminPrimary
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                '${unit['members'] ?? 0} members',
                                                style: const TextStyle(
                                                  color: kSuperAdminPrimary,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  String _money(Object? value) {
    final number = (value is num)
        ? value.toDouble()
        : double.tryParse('${value ?? 0}') ?? 0;
    return number.toStringAsFixed(2);
  }
}

class _ReportsHero extends StatelessWidget {
  final String? generatedAt;

  const _ReportsHero({required this.generatedAt});

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
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'System Reports',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Monitor membership growth, revenue flow, and overall system health without leaving the SuperAdmin workspace.',
            style: TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Last generated: ${_formatDateTime(generatedAt)}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: kSuperAdminCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kSuperAdminBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: kSuperAdminText,
                fontFamily: 'Montserrat',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: kSuperAdminText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(color: kSuperAdminMuted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSuperAdminCard,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kSuperAdminBorder),
      ),
      child: Column(
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
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _MiniBarChart extends StatelessWidget {
  final String title;
  final Color color;
  final List<Map<String, dynamic>> items;
  final bool amountMode;

  const _MiniBarChart({
    required this.title,
    required this.color,
    required this.items,
    required this.amountMode,
  });

  @override
  Widget build(BuildContext context) {
    final values = items
        .map(
          (item) => item['value'] is num
              ? (item['value'] as num).toDouble()
              : double.tryParse('${item['value'] ?? 0}') ?? 0,
        )
        .toList();
    final maxValue = values.isEmpty
        ? 1.0
        : values
              .reduce((left, right) => left > right ? left : right)
              .clamp(1, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: kSuperAdminText,
          ),
        ),
        const SizedBox(height: 12),
        ...items.map((item) {
          final value = item['value'] is num
              ? (item['value'] as num).toDouble()
              : double.tryParse('${item['value'] ?? 0}') ?? 0;
          final ratio = (value / maxValue).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _formatMonth(item['month']?.toString()),
                        style: const TextStyle(
                          color: kSuperAdminMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      amountMode
                          ? 'PHP ${value.toStringAsFixed(2)}'
                          : value.toStringAsFixed(0),
                      style: const TextStyle(
                        color: kSuperAdminText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 12,
                    backgroundColor: color.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String value;

  const _BreakdownRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: kSuperAdminMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: kSuperAdminText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: kSuperAdminDanger,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kSuperAdminMuted, height: 1.5),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: kSuperAdminPrimary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(String? raw) {
  final parsed = DateTime.tryParse(raw ?? '');
  if (parsed == null) return 'Unknown';
  final local = parsed.toLocal();
  final hour = local.hour > 12
      ? local.hour - 12
      : (local.hour == 0 ? 12 : local.hour);
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.month}/${local.day}/${local.year} $hour:$minute $suffix';
}

String _formatMonth(String? raw) {
  final value = raw ?? '';
  final parts = value.split('-');
  if (parts.length != 2) return value;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = int.tryParse(parts[1]);
  if (month == null || month < 1 || month > 12) return value;
  return '${months[month - 1]} ${parts[0]}';
}
