import 'package:capstone_app/shared/collectors_manage_page.dart';
import 'package:capstone_app/shared/removed_members_page.dart';
import 'package:capstone_app/shared/active_members_page.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PresSecDashboardOverview extends StatefulWidget {
  final int dayungUnitId;
  final VoidCallback? onNavigateToMembers;
  final VoidCallback? onNavigateToDeceased;
  final bool responsiveLayout;

  const PresSecDashboardOverview({
    super.key,
    required this.dayungUnitId,
    this.onNavigateToMembers,
    this.onNavigateToDeceased,
    this.responsiveLayout = false,
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
  double _membershipFunds = 0;

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

  bool _isTruthyFlag(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      return ['true', '1', 'yes'].contains(value.trim().toLowerCase());
    }
    return false;
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
        .select('user_id, status, isRemovedInDayung')
        .eq('dayung_unit_id', unitId);

    final appList = List<Map<String, dynamic>>.from(apps);
    final removedCount = appList
        .where((r) => r['isRemovedInDayung'] == true)
        .length;

    final paymentRows = await _sb
        .from('payments')
        .select('user_id')
        .eq('dayung_unit_id', unitId)
        .eq('type', 'membership_payment')
        .eq('status', 'paid');
    final activeMemberIds = <String>{};
    for (final row in List<Map<String, dynamic>>.from(paymentRows)) {
      final id = (row['user_id'] ?? '').toString().trim();
      if (id.isNotEmpty) activeMemberIds.add(id);
    }

    final unitRow = await _sb
        .from('dayung_units')
        .select('president_id, secretary_id, treasurer_id')
        .eq('id', unitId)
        .maybeSingle();
    if (unitRow != null) {
      for (final key in ['president_id', 'secretary_id', 'treasurer_id']) {
        final value = unitRow[key];
        if (value != null) activeMemberIds.add(value.toString().trim());
      }
    }

    final approvedCount = activeMemberIds.length;
    int deceasedCount = 0;
    final claims = await _sb
        .from('claims')
        .select('user_id, deceased_type, status, claimedmoney')
        .eq('dayung_unit_id', unitId);

    final claimList = List<Map<String, dynamic>>.from(claims);
    final approvedClaims = claimList.where((r) {
      return (r['status'] ?? '').toString().toLowerCase() == 'approved';
    }).toList();

    final claimedDeceasedIds = approvedClaims
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
        .select('amount, status, userdeceased, iscollectedbytreasurer')
        .eq('dayung_unit_id', unitId)
        .eq('type', 'deceased_payment');
    double totalFunds = 0;
    for (final r in List<Map<String, dynamic>>.from(payments)) {
      final paymentStatus = (r['status'] ?? '').toString().toLowerCase();
      final deceasedId = (r['userdeceased'] ?? '').toString().trim();
      final alreadyClaimed = claimedDeceasedIds.contains(deceasedId);
      final isCollectedByTreasurer = _isTruthyFlag(r['iscollectedbytreasurer']);

      if (paymentStatus == 'paid' &&
          !alreadyClaimed &&
          isCollectedByTreasurer) {
        final amt = r['amount'];
        totalFunds += (amt is num)
            ? amt.toDouble()
            : double.tryParse('$amt') ?? 0;
      }
    }

    // Membership Funds (paid membership payments)
    final membershipPayments = await _sb
        .from('payments')
        .select('amount, status')
        .eq('dayung_unit_id', unitId)
        .eq('type', 'membership_payment')
        .eq('status', 'paid');

    double totalMembershipFunds = 0;
    for (final r in List<Map<String, dynamic>>.from(membershipPayments)) {
      final amt = r['amount'];
      totalMembershipFunds += (amt is num)
          ? amt.toDouble()
          : double.tryParse('$amt') ?? 0;
    }

    if (mounted) {
      setState(() {
        _activeMembers = activeCount < 0 ? 0 : activeCount;
        _removedMembers = removedCount;
        _deceasedMembers = deceasedCount;
        _collectorsCount = collectorsCount;
        _currentFunds = totalFunds;
        _membershipFunds = totalMembershipFunds;
      });
    }
  }

  Future<void> _fetchMonthlyCollected() async {
    final now = DateTime.now();
    final yearStart = DateTime(now.year, 1, 1).toIso8601String();
    final yearEnd = DateTime(now.year, 12, 31, 23, 59, 59).toIso8601String();

    final rows = await _sb
        .from('payments')
        .select('amount, paid_at, created_at, iscollectedbytreasurer')
        .eq('dayung_unit_id', widget.dayungUnitId)
        .eq('type', 'deceased_payment')
        .eq('status', 'paid')
        .eq('iscollectedbytreasurer', true)
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
        .eq('type', 'deceased_payment')
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
      return const SizedBox(
        height: 420,
        child: DayungPageSkeleton(
          layout: DayungSkeletonLayout.dashboard,
          padding: EdgeInsets.all(12),
        ),
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
        const SizedBox(height: 12),
        _incompleteCollectionsList(),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  // ── ROW 1 ──────────────────────────────────────────────────────────────────

  Widget _row1StatCards() {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statCard(
                icon: Icons.groups_rounded,
                title: 'Active Members',
                value: '$_activeMembers',
                color: colors.primary,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ActiveMembersPage(dayungUnitId: widget.dayungUnitId),
                    ),
                  ).then((_) => _load());
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                icon: Icons.person_remove_rounded,
                title: 'Removed Members',
                value: '$_removedMembers',
                color: colors.error,
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
                color: colors.tertiary,
                onTap: widget.onNavigateToDeceased,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                icon: Icons.badge_rounded,
                title: 'Collectors',
                value: '$_collectorsCount',
                color: colors.secondary,
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
          color: dayungSurface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.18)),
          boxShadow: [dayungElevatedShadow(context)],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 220;
            final iconContainer = Container(
              padding: EdgeInsets.all(compact ? 8 : 10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: compact ? 20 : 22),
            );
            final stats = Column(
              crossAxisAlignment: compact
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: compact ? Alignment.center : Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: compact ? 26 : 22,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                ),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: compact ? TextAlign.center : TextAlign.start,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );

            if (compact) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [iconContainer, const SizedBox(height: 8), stats],
              );
            }

            return Row(
              children: [
                iconContainer,
                const SizedBox(width: 12),
                Expanded(child: stats),
                if (onTap != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: color.withValues(alpha: 0.5),
                    size: 20,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _fundsCard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: _fundsCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: dayungAccentSurface(
                          context,
                          Theme.of(context).colorScheme.primary,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Funds Summary',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _fundsBalanceTile(
                  'Current Funds Balance',
                  '₱${_currentFunds.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 10),
                _fundsBalanceTile(
                  'Membership Funds',
                  '₱${_membershipFunds.toStringAsFixed(2)}',
                ),
              ],
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: _fundsCardDecoration(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: dayungAccentSurface(
                    context,
                    Theme.of(context).colorScheme.primary,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _fundsBalanceTile(
                  'Current Funds Balance',
                  '₱${_currentFunds.toStringAsFixed(2)}',
                ),
              ),
              const SizedBox(width: 16),
              Container(width: 1, height: 120, color: dayungBorder(context)),
              const SizedBox(width: 16),
              Expanded(
                child: _fundsBalanceTile(
                  'Membership Funds',
                  '₱${_membershipFunds.toStringAsFixed(2)}',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  BoxDecoration _fundsCardDecoration() {
    return dayungSectionCardDecoration(context, radius: 16);
  }

  Widget _fundsBalanceTile(String title, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dayungSoftSurface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dayungBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── ROW 2 ──────────────────────────────────────────────────────────────────

  Widget _monthlyChartCard() {
    final theme = Theme.of(context);
    final chartColor = theme.colorScheme.primary;
    final maxY = _monthlyCollected.reduce((a, b) => a > b ? a : b);
    final chartMax = maxY <= 0 ? 100.0 : maxY * 1.25;
    final totalYear = _monthlyCollected.fold(0.0, (a, b) => a + b);
    const months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: dayungSectionCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.responsiveLayout)
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _yearTotalBadge(totalYear),
                Text(
                  '${DateTime.now().year}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                _yearTotalBadge(totalYear),
                const Spacer(),
                Text(
                  '${DateTime.now().year}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
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
                        TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: theme.textTheme.labelMedium?.fontSize,
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
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
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
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: theme.colorScheme.outlineVariant,
                    strokeWidth: 1,
                  ),
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
                            ? chartColor
                            : chartColor.withValues(alpha: 0.55),
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: chartMax,
                          color: dayungSoftSurface(context),
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
                        ? dayungAccentSurface(context, chartColor)
                        : dayungSoftSurface(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCurrentMonth
                          ? chartColor.withValues(alpha: 0.35)
                          : dayungBorder(context),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        months[i],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isCurrentMonth
                              ? chartColor
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        val > 0 ? '₱${val.toStringAsFixed(0)}' : '—',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: isCurrentMonth
                              ? chartColor
                              : theme.colorScheme.onSurfaceVariant,
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

  Widget _yearTotalBadge(double totalYear) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: dayungAccentSurface(context, theme.colorScheme.primary),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Total: ₱${totalYear.toStringAsFixed(0)}',
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  // ── ROW 3 ──────────────────────────────────────────────────────────────────

  Widget _incompleteCollectionsList() {
    if (_incomplete.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: dayungSectionCardDecoration(context, radius: 16),
        child: Center(
          child: Text(
            'All collections are complete.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    final colors = Theme.of(context).colorScheme;
    final progress = (c.goal > 0) ? (c.paid / c.goal).clamp(0.0, 1.0) : 0.0;
    final pct = (progress * 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: dayungSectionCardDecoration(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: dayungAccentSurface(context, colors.primary),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.local_florist_rounded,
                  color: colors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c.name,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: dayungAccentSurface(context, colors.secondary),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$pct%',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.secondary,
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
              backgroundColor: dayungSoftSurface(context),
              valueColor: AlwaysStoppedAnimation(
                progress >= 0.75 ? colors.secondary : colors.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                '${c.paid.toStringAsFixed(0)} of ${c.goal.toStringAsFixed(0)} members paid',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.secondary,
                ),
              ),
              Text(
                '${(c.goal - c.paid).toStringAsFixed(0)} remaining',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
