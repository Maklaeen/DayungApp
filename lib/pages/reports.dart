import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/Secretary/secretary_ui.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';

const Color kCardBg = Color(0xFFFFFFFF);
const Color kBorderColor = Color(0xFFE5E7EB);
const Color kPrimary = Color(0xFF1E40AF);
const Color kAccent = Color(0xFF10B981);
const Color kSubText = Color(0xFF6B7280);

class ReportsService {
  final sb = Supabase.instance.client;

  // gina fetch ang total money collected per collector per month
  Future<List<Map<String, dynamic>>> fetchMoneyCollectedPerCollector({
    int? unitId,
  }) async {
    final query = sb
        .from('payments')
        .select(
          'amount, paid_at, collected_by, collector:users!payments_collected_by_fkey(full_name)',
        )
        .eq('status', 'paid');
    if (unitId != null) query.eq('dayung_unit_id', unitId);
    final rows = List<Map<String, dynamic>>.from(await query);

    // Aggregate: {collector, month, total}
    final Map<String, Map<String, dynamic>> data = {};
    for (final r in rows) {
      final collectorId = r['collected_by']?.toString() ?? 'unknown';
      final collectorName = (r['collector']?['full_name'] ?? 'Unknown')
          .toString();
      final paidAt = DateTime.tryParse(r['paid_at']?.toString() ?? '');
      if (paidAt == null) continue;
      final month = '${paidAt.year}-${paidAt.month.toString().padLeft(2, '0')}';
      final amount = double.tryParse(r['amount'].toString()) ?? 0.0;
      final key = '$collectorId|$month';
      data.putIfAbsent(
        key,
        () => {
          'collector_id': collectorId,
          'collector_name': collectorName,
          'month': month,
          'total': 0.0,
        },
      );
      data[key]!['total'] = (data[key]!['total'] as double) + amount;
    }
    return data.values.toList();
  }

  /// Funds released per month (stub, ready for your table)
  Future<List<Map<String, dynamic>>> fetchFundsReleasedPerMonth({
    int? unitId,
  }) async {
    // blank
    return [];
  }

  /// Number of new members each month
  Future<List<Map<String, dynamic>>> fetchNewMembersPerMonth({
    required int unitId,
  }) async {
    final query = sb
        .from('applications')
        .select('approved_at')
        .eq('status', 'approved')
        .eq('dayung_unit_id', unitId); // Always filter by unitId
    final rows = List<Map<String, dynamic>>.from(await query);

    final Map<String, int> monthCounts = {};
    for (final r in rows) {
      final approvedAt = DateTime.tryParse(r['approved_at']?.toString() ?? '');
      if (approvedAt == null) continue;
      final month =
          '${approvedAt.year}-${approvedAt.month.toString().padLeft(2, '0')}';
      monthCounts[month] = (monthCounts[month] ?? 0) + 1;
    }
    return monthCounts.entries
        .map((e) => {'month': e.key, 'count': e.value})
        .toList();
  }
}

String _formatMonthYear(String ym) {
  // ym is in 'YYYY-MM'
  final parts = ym.split('-');
  if (parts.length != 2) return ym;
  final year = parts[0];
  final monthNum = int.tryParse(parts[1]) ?? 1;
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final monthName = (monthNum >= 1 && monthNum <= 12)
      ? months[monthNum - 1]
      : ym;
  return '$monthName - $year';
}

class ReportsPage extends StatefulWidget {
  final int? unitId;
  const ReportsPage({super.key, this.unitId});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final service = ReportsService();
  List<Map<String, dynamic>> moneyCollected = [];
  List<Map<String, dynamic>> newMembers = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => loading = true);
    moneyCollected = await service.fetchMoneyCollectedPerCollector(
      unitId: widget.unitId,
    );
    // Pass unitId as required
    newMembers = widget.unitId != null
        ? await service.fetchNewMembersPerMonth(unitId: widget.unitId!)
        : [];
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700;
            final horizontalPadding = isWide
                ? constraints.maxWidth * 0.15
                : 20.0;
            final cardMaxWidth = isWide ? 600.0 : double.infinity;
            final sectionTitleFontSize = isWide ? 22.0 : 18.0;

            return Column(
              children: [
                SecretaryPageHeader(
                  title: 'Reports',
                  icon: Icons.bar_chart_rounded,
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    isWide ? 48 : 32,
                    horizontalPadding,
                    isWide ? 24 : 24,
                  ),
                ),
                // Content
                Expanded(
                  child: loading
                      ? const DayungPageSkeleton(
                          layout: DayungSkeletonLayout.dashboard,
                          itemCount: 4,
                        )
                      : ListView(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            isWide ? 32 : 20,
                            horizontalPadding,
                            isWide ? 32 : 20,
                          ),
                          children: [
                            Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: cardMaxWidth,
                                ),
                                child: _modernSectionCard(
                                  title:
                                      'Money Collected Per Collector (Monthly)',
                                  icon: Icons.account_balance_rounded,
                                  titleFontSize: sectionTitleFontSize,
                                  child: Column(
                                    children: [
                                      _MoneyCollectedBarChart(
                                        data: moneyCollected,
                                        isWide: isWide,
                                      ),
                                      const SizedBox(height: 12),
                                      ...moneyCollected.map(
                                        (r) => Container(
                                          margin: const EdgeInsets.symmetric(
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: kCardBg,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: kBorderColor.withValues(
                                                alpha: 0.2,
                                              ),
                                            ),
                                          ),
                                          child: ListTile(
                                            leading: CircleAvatar(
                                              backgroundColor: kAccent
                                                  .withValues(alpha: 0.12),
                                              child: Icon(
                                                Icons.person,
                                                color: kAccent,
                                              ),
                                            ),
                                            title: Text(
                                              '${r['collector_name']}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            subtitle: Text(
                                              '${r['month']}',
                                              style: const TextStyle(
                                                color: kSubText,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            trailing: SizedBox(
                                              width: isWide ? 120 : 90,
                                              child: Text(
                                                '₱${r['total'].toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.right,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: cardMaxWidth,
                                ),
                                child: _modernSectionCard(
                                  title: 'New Members Per Month',
                                  icon: Icons.person_add_alt_1_rounded,
                                  titleFontSize: sectionTitleFontSize,
                                  child: Column(
                                    children: [
                                      _NewMembersBarChart(
                                        data: newMembers,
                                        isWide: isWide,
                                      ),
                                      const SizedBox(height: 12),
                                      ...newMembers.map(
                                        (r) => Container(
                                          margin: const EdgeInsets.symmetric(
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: kCardBg,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: kBorderColor.withValues(
                                                alpha: 0.2,
                                              ),
                                            ),
                                          ),
                                          child: ListTile(
                                            leading: CircleAvatar(
                                              backgroundColor: kPrimary
                                                  .withValues(alpha: 0.12),
                                              child: Icon(
                                                Icons.person,
                                                color: kPrimary,
                                              ),
                                            ),
                                            title: Text(
                                              _formatMonthYear(r['month']),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            trailing: SizedBox(
                                              width: isWide ? 80 : 50,
                                              child: Text(
                                                '${r['count']}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.right,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _modernSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    double titleFontSize = 18,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: kBorderColor.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: kPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.w800,
                    color: kPrimary,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

// Chart for Money Collected Per Collector (Monthly)
class _MoneyCollectedBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool isWide;
  const _MoneyCollectedBarChart({required this.data, required this.isWide});

  @override
  Widget build(BuildContext context) {
    final months = data.map((e) => e['month'] as String).toSet().toList()
      ..sort();
    final collectors = data
        .map((e) => e['collector_name'] as String)
        .toSet()
        .toList();
    final Map<String, Map<String, double>> grouped = {};
    for (final month in months) {
      grouped[month] = {};
      for (final collector in collectors) {
        grouped[month]![collector] = 0.0;
      }
    }
    for (final row in data) {
      final month = row['month'] as String;
      final collector = row['collector_name'] as String;
      final total = row['total'] as double;
      grouped[month]![collector] = total;
    }

    final maxY =
        grouped.values
            .expand((m) => m.values)
            .fold<double>(0, (prev, v) => v > prev ? v : prev) *
        1.2;

    return SizedBox(
      height: isWide ? 260 : 220,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY > 0 ? maxY : 10,
          minY: 0,
          groupsSpace: isWide ? 36 : 24,
          barTouchData: BarTouchData(enabled: true),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: ((maxY ~/ 5) > 0 ? (maxY ~/ 5).toDouble() : 1.0),
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(
                    value.toInt().toString(),
                    style: TextStyle(
                      fontSize: isWide ? 14 : 10,
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  return idx >= 0 && idx < months.length
                      ? Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text(
                            _formatMonthYear(months[idx]),
                            style: TextStyle(
                              fontSize: isWide ? 14 : 12,
                              color: Colors.black87,
                            ),
                          ),
                        )
                      : const SizedBox.shrink();
                },
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            horizontalInterval: ((maxY ~/ 5) > 0
                ? (maxY ~/ 5).toDouble()
                : 1.0),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(months.length, (i) {
            final month = months[i];
            final collectorTotals = grouped[month]!;
            return BarChartGroupData(
              x: i,
              barRods: List.generate(collectors.length, (j) {
                return BarChartRodData(
                  toY: collectorTotals[collectors[j]] ?? 0,
                  color: Colors.primaries[j % Colors.primaries.length],
                  width: isWide ? 18 : 14,
                  borderRadius: BorderRadius.circular(4),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: const Color(0xFFE5E7EB),
                  ),
                );
              }),
            );
          }),
        ),
      ),
    );
  }
}

// Chart for New Members Per Month
class _NewMembersBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool isWide;
  const _NewMembersBarChart({required this.data, required this.isWide});

  @override
  Widget build(BuildContext context) {
    final months = data.map((e) => e['month'] as String).toList()..sort();
    final counts = months
        .map((m) => data.firstWhere((e) => e['month'] == m)['count'] as int)
        .toList();
    final maxY = counts.isNotEmpty
        ? (counts.reduce((a, b) => a > b ? a : b) * 1.2)
        : 10.0;

    return SizedBox(
      height: isWide ? 200 : 180,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          minY: 0,
          groupsSpace: isWide ? 36 : 24,
          barTouchData: BarTouchData(enabled: true),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: ((maxY ~/ 5) > 0 ? (maxY ~/ 5).toDouble() : 1.0),
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Text(
                    value.toInt().toString(),
                    style: TextStyle(
                      fontSize: isWide ? 14 : 10,
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  return idx >= 0 && idx < months.length
                      ? Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text(
                            _formatMonthYear(months[idx]),
                            style: TextStyle(
                              fontSize: isWide ? 14 : 12,
                              color: Colors.black87,
                            ),
                          ),
                        )
                      : const SizedBox.shrink();
                },
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            horizontalInterval: ((maxY ~/ 5) > 0
                ? (maxY ~/ 5).toDouble()
                : 1.0),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(months.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: counts[i].toDouble(),
                  color: Colors.blueAccent,
                  width: isWide ? 26 : 22,
                  borderRadius: BorderRadius.circular(4),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: const Color(0xFFE5E7EB),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
