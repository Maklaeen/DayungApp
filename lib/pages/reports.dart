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

  /// Money collected per collector per month
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
    // TODO: Replace with your actual fund release table/query
    // Example: SELECT released_at, amount FROM fund_releases WHERE ...
    return [];
  }

  /// Number of new members each month
  Future<List<Map<String, dynamic>>> fetchNewMembersPerMonth({
    int? unitId,
  }) async {
    final query = sb
        .from('applications')
        .select('approved_at')
        .eq('status', 'approved');
    if (unitId != null) query.eq('dayung_unit_id', unitId);
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

// Example usage in a widget
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
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
    moneyCollected = await service.fetchMoneyCollectedPerCollector();
    newMembers = await service.fetchNewMembersPerMonth();
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          // Modern header from service_tracker.dart
          Container(
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
            decoration: BoxDecoration(
              color: kPrimary,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: kPrimary.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.chevron_left_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                const Icon(
                  Icons.bar_chart_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Reports',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontFamily: 'Montserrat',
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    children: [
                      // ...existing cards and charts...
                      _modernSectionCard(
                        title: 'Money Collected Per Collector (Monthly)',
                        icon: Icons.account_balance_rounded,
                        child: Column(
                          children: [
                            _MoneyCollectedBarChart(data: moneyCollected),
                            const SizedBox(height: 12),
                            ...moneyCollected.map(
                              (r) => Container(
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                decoration: BoxDecoration(
                                  color: kCardBg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: kBorderColor.withOpacity(0.2),
                                  ),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: kAccent.withOpacity(0.12),
                                    child: Icon(Icons.person, color: kAccent),
                                  ),
                                  title: Text(
                                    '${r['collector_name']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${r['month']}',
                                    style: const TextStyle(color: kSubText),
                                  ),
                                  trailing: Text(
                                    '₱${r['total'].toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _modernSectionCard(
                        title: 'New Members Per Month',
                        icon: Icons.person_add_alt_1_rounded,
                        child: Column(
                          children: [
                            _NewMembersBarChart(data: newMembers),
                            const SizedBox(height: 12),
                            ...newMembers.map(
                              (r) => Container(
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                decoration: BoxDecoration(
                                  color: kCardBg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: kBorderColor.withOpacity(0.2),
                                  ),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: kPrimary.withOpacity(0.12),
                                    child: Icon(Icons.person, color: kPrimary),
                                  ),
                                  title: Text(
                                    '${r['month']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  trailing: Text(
                                    '${r['count']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _modernSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorderColor.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
                  color: kPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: kPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: kPrimary,
                  letterSpacing: 0.3,
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
  const _MoneyCollectedBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    // Group by month, sum per collector
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
      height: 220,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY > 0 ? maxY : 10,
          minY: 0,
          groupsSpace: 24,
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
                    style: const TextStyle(
                      fontSize: 10,
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
                            months[idx],
                            style: const TextStyle(
                              fontSize: 12,
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
                  width: 14,
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
  const _NewMembersBarChart({required this.data});

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
      height: 180,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          minY: 0,
          groupsSpace: 24,
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
                    style: const TextStyle(
                      fontSize: 10,
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
                            months[idx],
                            style: const TextStyle(
                              fontSize: 12,
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
                  width: 22,
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
