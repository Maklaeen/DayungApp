import 'package:capstone_app/shared/collectors_manage_page.dart';
import 'package:capstone_app/shared/removed_members_page.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _kPrimary = Color(0xFF0D47A1);
const Color _kPrimaryDark = Color(0xFF083366);
const Color _kNeutralText = Color(0xFF1F2937);
const Color _kSubText = Color(0xFF4B5563);
const Color _kDanger = Color(0xFFEF4444);
const Color _kSuccess = Color(0xFF10B981);
const Color _kWarn = Color(0xFFF59E0B);
const Color _kPurple = Color(0xFF7C3AED);

/// Shared dashboard overview for President and Secretary.
/// Pass [onNavigateToMembers] to handle tapping "Active Members" card.
/// Pass [onNavigateToDeceased] to handle tapping "Deceased Members" card.
class PresSecDashboardOverview extends StatefulWidget {
  final int dayungUnitId;
  final VoidCallback? onNavigateToMembers;
  final VoidCallback? onNavigateToDeceased;

  const PresSecDashboardOverview({
    super.key,
    required this.dayungUnitId,
    this.onNavigateToMembers,
    this.onNavigateToDeceased,
  });

  @override
  State<PresSecDashboardOverview> createState() =>
      _PresSecDashboardOverviewState();
}

class _PresSecDashboardOverviewState extends State<PresSecDashboardOverview> {
  final _sb = Supabase.instance.client;
  bool _loading = true;

  int _activeMembers = 0;
  int _removedMembers = 0;
  int _deceasedMembers = 0;
  int _collectorsCount = 0;
  double _currentFunds = 0;

  // Monthly cash collected (Jan–Dec current year)
  List<double> _monthlyCollected = List.filled(12, 0);

  // Incomplete collections (deceased with partial payments)
  List<_IncompleteCollection> _incomplete = [];

  bool _isClaimedMoney(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;

    final normalized = value.toString().trim().toLowerCase();
    return normalized == 'yes' || normalized == 'true' || normalized == '1';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PresSecDashboardOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dayungUnitId != widget.dayungUnitId) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await Future.wait([
        _fetchCounts(),
        _fetchMonthlyCollected(),
        _fetchIncompleteCollections(),
      ]);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchCounts() async {
    final unitId = widget.dayungUnitId;

    // Active members
    final apps = await _sb
        .from('applications')
        .select('user_id, status')
        .eq('dayung_unit_id', unitId);

    final appList = List<Map<String, dynamic>>.from(apps);
    final approvedCount =
      appList.where((r) => r['status'] == 'approved').length;
    final removedCount = appList.where((r) => r['status'] == 'removed').length;

    int deceasedCount = 0;
    final claims = await _sb
        .from('claims')
      .select('user_id, deceased_type, status, claimedmoney')
        .eq('dayung_unit_id', unitId);

    final claimList = List<Map<String, dynamic>>.from(claims);
    final approvedClaims = claimList.where((r) {
      return (r['status'] ?? '').toString().toLowerCase() == 'approved';
    }).toList();

    final claimedDeceasedIds = claimList
      .where((r) => _isClaimedMoney(r['claimedmoney']))
      .map((r) => (r['user_id'] ?? '').toString().trim())
      .where((userId) => userId.isNotEmpty)
      .toSet();

    deceasedCount = approvedClaims.length;

    final activeCount = approvedCount;

    // Collectors
    final cols = await _sb
        .from('dayung_collectors')
        .select('user_id')
        .eq('dayung_unit_id', unitId);
    final collectorsCount = (cols as List).length;

    // Current funds (total paid payments)
    final payments = await _sb
        .from('payments')
        .select('amount, status, userdeceased')
        .eq('dayung_unit_id', unitId);
    double totalFunds = 0;
    for (final r in List<Map<String, dynamic>>.from(payments)) {
      final paymentStatus = (r['status'] ?? '').toString().toLowerCase();
      final deceasedId = (r['userdeceased'] ?? '').toString().trim();
      final alreadyClaimed = claimedDeceasedIds.contains(deceasedId);

      if (paymentStatus == 'paid' && !alreadyClaimed) {
        final amt = r['amount'];
        totalFunds += (amt is num)
            ? amt.toDouble()
            : double.tryParse('$amt') ?? 0;
      }
    }

    if (mounted) {
      setState(() {
        _activeMembers = activeCount < 0 ? 0 : activeCount;
        _removedMembers = removedCount;
        _deceasedMembers = deceasedCount;
        _collectorsCount = collectorsCount;
        _currentFunds = totalFunds;
      });
    }
  }

  Future<void> _fetchMonthlyCollected() async {
    final now = DateTime.now();
    final yearStart = DateTime(now.year, 1, 1).toIso8601String();
    final yearEnd = DateTime(now.year, 12, 31, 23, 59, 59).toIso8601String();

    final rows = await _sb
        .from('payments')
        .select('amount, paid_at, created_at')
        .eq('dayung_unit_id', widget.dayungUnitId)
        .eq('status', 'paid')
        .gte('created_at', yearStart)
        .lte('created_at', yearEnd);

    final monthly = List.filled(12, 0.0);
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final dateStr = (r['paid_at'] ?? r['created_at'])?.toString() ?? '';
      final dt = DateTime.tryParse(dateStr);
      if (dt == null) continue;
      final month = dt.month - 1; // 0-indexed
      final amt = r['amount'];
      monthly[month] += (amt is num)
          ? amt.toDouble()
          : double.tryParse('$amt') ?? 0;
    }

    if (mounted) setState(() => _monthlyCollected = monthly);
  }

  Future<void> _fetchIncompleteCollections() async {
    final rows = await _sb
        .from('payments')
        .select('user_id, userdeceased, deceased_name, status, created_at')
        .eq('dayung_unit_id', widget.dayungUnitId)
        .order('created_at', ascending: false);

    final payments = List<Map<String, dynamic>>.from(rows);
    if (payments.isEmpty) {
      if (mounted) setState(() => _incomplete = []);
      return;
    }

    final grouped = <String, _CollectionProgressBucket>{};

    for (final row in payments) {
      final deceasedId = (row['userdeceased'] ?? '').toString().trim();
      final deceasedName = (row['deceased_name'] ?? '').toString().trim();
      final memberId = (row['user_id'] ?? '').toString().trim();
      final status = (row['status'] ?? '').toString().toLowerCase();

      final bucketKey = deceasedId.isNotEmpty ? deceasedId : deceasedName;
      if (bucketKey.isEmpty || memberId.isEmpty) continue;

      final bucket = grouped.putIfAbsent(
        bucketKey,
        () => _CollectionProgressBucket(
          name: deceasedName.isNotEmpty ? deceasedName : 'Deceased',
        ),
      );

      if (bucket.name == 'Deceased' && deceasedName.isNotEmpty) {
        bucket.name = deceasedName;
      }

      bucket.expectedMemberIds.add(memberId);
      if (status == 'paid') {
        bucket.paidMemberIds.add(memberId);
      }
    }

    final incomplete =
        grouped.entries
            .map(
              (entry) => _IncompleteCollection(
                noticeId: entry.key.hashCode,
                name: entry.value.name,
                paid: entry.value.paidMemberIds.length.toDouble(),
                goal: entry.value.expectedMemberIds.length.toDouble(),
              ),
            )
            .where(
              (collection) =>
                  collection.goal > 0 && collection.paid < collection.goal,
            )
            .toList()
          ..sort((a, b) => (b.goal - b.paid).compareTo(a.goal - a.paid));

    if (mounted) setState(() => _incomplete = incomplete);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: _kPrimary)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── ROW 1: Stat cards ──
        _sectionTitle('Overview'),
        const SizedBox(height: 12),
        _row1StatCards(),
        const SizedBox(height: 24),

        // ── ROW 2: Monthly bar chart ──
        _sectionTitle('Cash Collected per Month'),
        const SizedBox(height: 12),
        _monthlyChartCard(),
        const SizedBox(height: 24),

        // ── ROW 3: Incomplete collections ──
        _sectionTitle('Ongoing Collections'),
        const SizedBox(height: 4),
        const Text(
          'Shows how many members have already paid for each deceased member.',
          style: TextStyle(
            fontSize: 12,
            color: _kSubText,
            fontFamily: 'OpenSans',
          ),
        ),
        const SizedBox(height: 12),
        _incompleteCollectionsList(),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: _kPrimaryDark,
        fontFamily: 'Montserrat',
      ),
    );
  }

  // ── ROW 1 ──────────────────────────────────────────────────────────────────

  Widget _row1StatCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statCard(
                icon: Icons.groups_rounded,
                title: 'Active Members',
                value: '$_activeMembers',
                color: _kPrimary,
                onTap: widget.onNavigateToMembers,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                icon: Icons.person_remove_rounded,
                title: 'Removed Members',
                value: '$_removedMembers',
                color: _kDanger,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        RemovedMembersPage(dayungUnitId: widget.dayungUnitId),
                  ),
                ).then((_) => _load()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _statCard(
                icon: Icons.local_florist_rounded,
                title: 'Deceased Members',
                value: '$_deceasedMembers',
                color: _kPurple,
                onTap: widget.onNavigateToDeceased,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                icon: Icons.badge_rounded,
                title: 'Collectors',
                value: '$_collectorsCount',
                color: _kWarn,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CollectorsManagePage(dayungUnitId: widget.dayungUnitId),
                  ),
                ).then((_) => _load()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _fundsCard(),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: color,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _kSubText,
                      fontFamily: 'OpenSans',
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                color: color.withValues(alpha: 0.5),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _fundsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _kPrimary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current Funds Balance',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                    fontFamily: 'OpenSans',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₱${_currentFunds.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Total collected from all death notices',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white60,
                    fontFamily: 'OpenSans',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── ROW 2 ──────────────────────────────────────────────────────────────────

  Widget _monthlyChartCard() {
    final maxY = _monthlyCollected.reduce((a, b) => a > b ? a : b);
    final chartMax = maxY <= 0 ? 100.0 : maxY * 1.25;
    final totalYear = _monthlyCollected.fold(0.0, (a, b) => a + b);
    const months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Total: ₱${totalYear.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _kPrimary,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${DateTime.now().year}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _kSubText,
                  fontFamily: 'OpenSans',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: chartMax,
                minY: 0,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '₱${rod.toY.toStringAsFixed(0)}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= 12) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            months[idx],
                            style: const TextStyle(
                              fontSize: 11,
                              color: _kSubText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: chartMax / 4,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: Colors.grey.shade100, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(12, (i) {
                  final val = _monthlyCollected[i];
                  final isCurrentMonth = i == DateTime.now().month - 1;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: val,
                        color: isCurrentMonth
                            ? _kPrimary
                            : _kPrimary.withValues(alpha: 0.45),
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: chartMax,
                          color: Colors.grey.shade100,
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Monthly totals text row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(12, (i) {
                final val = _monthlyCollected[i];
                final isCurrentMonth = i == DateTime.now().month - 1;
                return Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isCurrentMonth
                        ? _kPrimary.withValues(alpha: 0.1)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCurrentMonth
                          ? _kPrimary.withValues(alpha: 0.3)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        months[i],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isCurrentMonth ? _kPrimary : _kSubText,
                        ),
                      ),
                      Text(
                        val > 0 ? '₱${val.toStringAsFixed(0)}' : '—',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: isCurrentMonth ? _kPrimary : _kSubText,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── ROW 3 ──────────────────────────────────────────────────────────────────

  Widget _incompleteCollectionsList() {
    if (_incomplete.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: Text(
            'All collections are complete.',
            style: TextStyle(
              color: _kSubText,
              fontFamily: 'OpenSans',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Column(
      children: _incomplete.map((c) => _incompleteCard(c)).toList(),
    );
  }

  Widget _incompleteCard(_IncompleteCollection c) {
    final progress = (c.goal > 0) ? (c.paid / c.goal).clamp(0.0, 1.0) : 0.0;
    final pct = (progress * 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                  color: _kPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.local_florist_rounded,
                  color: _kPurple,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _kNeutralText,
                    fontFamily: 'Montserrat',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _kWarn.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$pct%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _kWarn,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation(
                progress >= 0.75 ? _kSuccess : _kPrimary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${c.paid.toStringAsFixed(0)} of ${c.goal.toStringAsFixed(0)} members paid',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _kSuccess,
                  fontFamily: 'OpenSans',
                ),
              ),
              Text(
                '${(c.goal - c.paid).toStringAsFixed(0)} remaining',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _kSubText,
                  fontFamily: 'OpenSans',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IncompleteCollection {
  final int noticeId;
  final String name;
  final double paid;
  final double goal;

  const _IncompleteCollection({
    required this.noticeId,
    required this.name,
    required this.paid,
    required this.goal,
  });
}

class _CollectionProgressBucket {
  String name;
  final Set<String> expectedMemberIds = <String>{};
  final Set<String> paidMemberIds = <String>{};

  _CollectionProgressBucket({required this.name});
}
