import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF1E40AF);
const Color kPrimaryDark = Color(0xFF083366);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);
const Color kBorder = Color(0xFFE5E7EB);
const Color kSurface = Color(0xFFF8FAFC);

class CollectedFromCollectorsPage extends StatefulWidget {
  final int dayungUnitId;
  const CollectedFromCollectorsPage({super.key, required this.dayungUnitId});

  @override
  State<CollectedFromCollectorsPage> createState() =>
      _CollectedFromCollectorsPageState();
}

class _CollectedFromCollectorsPageState
    extends State<CollectedFromCollectorsPage> {
  static const Duration _queryTimeout = Duration(seconds: 10);

  final sb = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _collectors = [];
  List<Map<String, dynamic>> _deceasedList = [];
  int? _selectedDeceasedId;
  DateTimeRange? _selectedDateRange;
  double _totalCollected = 0;
  int _totalPayments = 0;
  int _activeCollectors = 0;
  String? _selectedDeceasedName;

  bool get _hasActiveFilters {
    return _selectedDeceasedId != null || _selectedDateRange != null;
  }

  double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? fallback;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? fallback;
  }

  int _gridColumns(double width) {
    if (width >= 1200) return 3;
    if (width >= 720) return 2;
    return 1;
  }

  @override
  void initState() {
    super.initState();
    _reloadPageData();
  }

  void _clearFilters() {
    setState(() {
      _selectedDeceasedId = null;
      _selectedDateRange = null;
      _selectedDeceasedName = null;
    });
  }

  Future<void> _reloadPageData() async {
    await Future.wait([_fetchDeceasedList(), _fetchCollectors()]);
  }

  String _formatCurrency(double amount) {
    return 'PHP ${amount.toStringAsFixed(2)}';
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return 'Not available';
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return value;
    final month = <String>[
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
    ][parsed.month - 1];
    final hour = parsed.hour == 0
        ? 12
        : (parsed.hour > 12 ? parsed.hour - 12 : parsed.hour);
    final minute = parsed.minute.toString().padLeft(2, '0');
    final period = parsed.hour >= 12 ? 'PM' : 'AM';
    return '$month ${parsed.day}, ${parsed.year} · $hour:$minute $period';
  }

  String _formatDateRangeLabel() {
    final range = _selectedDateRange;
    if (range == null) return 'All payment dates';
    final start = _formatShortDate(range.start);
    final end = _formatShortDate(range.end);
    return '$start to $end';
  }

  String _formatShortDate(DateTime date) {
    final month = <String>[
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
    ][date.month - 1];
    return '$month ${date.day}, ${date.year}';
  }

  Future<void> _fetchDeceasedList() async {
    try {
      final res = await sb
          .from('death_notices')
          .select('id, name, date_of_death')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .order('date_of_death', ascending: false)
          .timeout(_queryTimeout);
      if (!mounted) return;
      setState(() {
        _deceasedList = List<Map<String, dynamic>>.from(res);
        _selectedDeceasedName = _deceasedList
            .where((row) => row['id'] == _selectedDeceasedId)
            .map((row) => (row['name'] ?? 'Unknown').toString())
            .cast<String?>()
            .firstOrNull;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deceasedList = [];
        _selectedDeceasedName = null;
      });
    }
  }

  Future<void> _fetchCollectors() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      dynamic query = sb
          .from('payments')
          .select('collected_by, amount, user_id, paid_at, death_notice_id')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'paid');

      if (_selectedDeceasedId != null) {
        query = query.eq('death_notice_id', _selectedDeceasedId as Object);
      }
      if (_selectedDateRange != null) {
        query = query
            .gte('paid_at', _selectedDateRange!.start.toIso8601String())
            .lte(
              'paid_at',
              _selectedDateRange!.end
                  .add(const Duration(days: 1))
                  .toIso8601String(),
            );
      }

      final paymentResponse = await query
          .order('paid_at', ascending: false)
          .timeout(_queryTimeout);
      final collectorRowsFuture = sb
          .from('dayung_collectors')
          .select('user_id')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .timeout(_queryTimeout);

      final payments = List<Map<String, dynamic>>.from(paymentResponse);
      final collectorRows = List<Map<String, dynamic>>.from(
        await collectorRowsFuture,
      );

      final collectorIds = <String>{
        for (final row in collectorRows) (row['user_id'] ?? '').toString(),
        for (final payment in payments)
          if ((payment['collected_by'] ?? '').toString().isNotEmpty)
            (payment['collected_by']).toString(),
      }..remove('');

      final users = collectorIds.isNotEmpty
          ? await sb
                .from('users')
                .select('id, full_name')
                .inFilter('id', collectorIds.toList())
                .timeout(_queryTimeout)
          : [];
      final userMap = {
        for (final u in List<Map<String, dynamic>>.from(users))
          (u['id'] ?? '').toString(): (u['full_name'] ?? 'Collector')
              .toString(),
      };

      final collectorMap = <String, Map<String, dynamic>>{};
      for (final row in collectorRows) {
        final collectorId = (row['user_id'] ?? '').toString();
        if (collectorId.isEmpty) continue;
        collectorMap[collectorId] = {
          'collector_id': collectorId,
          'collector_name': userMap[collectorId] ?? 'Collector',
          'collector_note': 'Assigned collector for this unit',
          'total_collected': 0.0,
          'payment_count': 0,
          'recent_payment': null,
        };
      }

      for (final p in payments) {
        final collectorId = (p['collected_by'] ?? '').toString();
        final groupingKey = collectorId.isNotEmpty
            ? collectorId
            : '__unassigned__';

        if (!collectorMap.containsKey(groupingKey)) {
          collectorMap[groupingKey] = {
            'collector_id': collectorId,
            'collector_name': collectorId.isNotEmpty
                ? (userMap[collectorId] ?? 'Collector')
                : 'Collector not recorded',
            'collector_note': collectorId.isNotEmpty
                ? 'Recorded paid collections'
                : 'Payments exist but collected_by is empty',
            'total_collected': 0.0,
            'payment_count': 0,
            'recent_payment': null,
          };
        }

        final collector = collectorMap[groupingKey]!;
        collector['total_collected'] =
            _asDouble(collector['total_collected']) + _asDouble(p['amount']);
        collector['payment_count'] = (collector['payment_count'] as int) + 1;
        final paidAt = (p['paid_at'] ?? '').toString();
        final recent = (collector['recent_payment'] ?? '').toString();
        if (recent.isEmpty ||
            (paidAt.isNotEmpty && paidAt.compareTo(recent) > 0)) {
          collector['recent_payment'] = paidAt;
        }
      }

      final collectorList = collectorMap.values.toList()
        ..sort((a, b) {
          final totalCompare = _asDouble(
            b['total_collected'],
          ).compareTo(_asDouble(a['total_collected']));
          if (totalCompare != 0) return totalCompare;
          return (a['collector_name'] ?? '').toString().compareTo(
            (b['collector_name'] ?? '').toString(),
          );
        });

      if (!mounted) return;

      setState(() {
        _collectors = collectorList;
        _totalCollected = payments.fold<double>(
          0,
          (sum, row) => sum + _asDouble(row['amount']),
        );
        _totalPayments = payments.length;
        _activeCollectors = collectorList
            .where((row) => _asInt(row['payment_count']) > 0)
            .length;
        _selectedDeceasedName = _deceasedList
            .where((row) => row['id'] == _selectedDeceasedId)
            .map((row) => (row['name'] ?? 'Unknown').toString())
            .cast<String?>()
            .firstOrNull;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 860;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildModernHeader(wide),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
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
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  child: RefreshIndicator(
                    color: kPrimary,
                    onRefresh: _reloadPageData,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                      children: [
                        _buildOverviewCard(wide),
                        const SizedBox(height: 18),
                        _buildFilterCard(wide),
                        const SizedBox(height: 18),
                        _buildStateSection(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernHeader(bool wide) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        wide ? 36 : 28,
        wide ? 24 : 16,
        wide ? 32 : 24,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF083366), Color(0xFF1E40AF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x22083366),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            icon: const Icon(
              Icons.chevron_left_rounded,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Collected from Collectors',
                  style: TextStyle(
                    fontSize: wide ? 24 : 21,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    fontFamily: 'Montserrat',
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                // Text(
                //   'Review paid remittances, assigned collectors, and the most recent collections recorded for this unit.',
                //   style: TextStyle(
                //     fontSize: wide ? 14 : 13,
                //     height: 1.35,
                //     fontWeight: FontWeight.w600,
                //     color: Colors.white70,
                //     fontFamily: 'OpenSans',
                //   ),
                // ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _headerPill(
                      icon: Icons.groups_rounded,
                      label: '$_activeCollectors active collectors',
                    ),
                    _headerPill(
                      icon: Icons.receipt_long_rounded,
                      label: '$_totalPayments paid records',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(bool wide) {
    final cards = [
      _buildStatCard(
        icon: Icons.payments_rounded,
        label: 'Total Collected',
        value: _formatCurrency(_totalCollected),
        tone: const Color(0xFF1E40AF),
      ),
      _buildStatCard(
        icon: Icons.receipt_long_rounded,
        label: 'Paid Payments',
        value: '$_totalPayments',
        tone: const Color(0xFF0F766E),
      ),
      _buildStatCard(
        icon: Icons.groups_rounded,
        label: 'Active Collectors',
        value: '$_activeCollectors',
        tone: const Color(0xFFB45309),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Collection Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kNeutralText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Review collector performance, paid member contributions, and the most recent recorded collections for this unit.',
            style: TextStyle(
              fontSize: wide ? 14 : 13,
              color: kSubtleText,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildInfoBadge(
                icon: Icons.person_outline_rounded,
                label: _selectedDeceasedName ?? 'All deceased notices',
                color: const Color(0xFF1E40AF),
              ),
              _buildInfoBadge(
                icon: Icons.schedule_rounded,
                label: _formatDateRangeLabel(),
                color: const Color(0xFF0F766E),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWideStats = constraints.maxWidth >= 760;
              if (isWideStats) {
                return Row(
                  children: [
                    for (int index = 0; index < cards.length; index++) ...[
                      Expanded(child: cards[index]),
                      if (index != cards.length - 1) const SizedBox(width: 12),
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  for (int index = 0; index < cards.length; index++) ...[
                    cards[index],
                    if (index != cards.length - 1) const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: tone),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: kSubtleText,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kNeutralText,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterCard(bool wide) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Filters',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kNeutralText,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
              if (_hasActiveFilters)
                TextButton.icon(
                  onPressed: () {
                    _clearFilters();
                    _fetchCollectors();
                  },
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  label: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Filter the paid collections by deceased member and payment date window to audit what collectors have already remitted.',
            style: TextStyle(
              fontSize: wide ? 14 : 13,
              color: kSubtleText,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: wide ? 320 : double.infinity,
                child: _buildDropdownFilter(),
              ),
              SizedBox(
                width: wide ? 250 : double.infinity,
                child: _buildActionFilter(
                  icon: Icons.date_range_rounded,
                  label: 'Payment Dates',
                  value: _formatDateRangeLabel(),
                  onTap: () async {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: DateTime.now(),
                    );
                    if (range == null) return;
                    setState(() => _selectedDateRange = range);
                    _fetchCollectors();
                  },
                ),
              ),
              SizedBox(
                width: wide ? 250 : double.infinity,
                child: _buildActionFilter(
                  icon: Icons.refresh_rounded,
                  label: 'Refresh Data',
                  value: 'Reload latest collector payments',
                  onTap: _reloadPageData,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFilterChip(
                icon: Icons.person_outline_rounded,
                label: _selectedDeceasedName ?? 'All deceased notices',
              ),
              _buildFilterChip(
                icon: Icons.schedule_rounded,
                label: _formatDateRangeLabel(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _selectedDeceasedId,
          isExpanded: true,
          hint: const Text('All deceased notices'),
          style: const TextStyle(
            color: kNeutralText,
            fontWeight: FontWeight.w700,
            fontFamily: 'OpenSans',
          ),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('All deceased notices'),
            ),
            ..._deceasedList.map(
              (row) => DropdownMenuItem<int?>(
                value: _asInt(row['id']),
                child: Text((row['name'] ?? 'Unknown').toString()),
              ),
            ),
          ],
          onChanged: (value) {
            setState(() {
              _selectedDeceasedId = value;
              _selectedDeceasedName = _deceasedList
                  .where((row) => row['id'] == value)
                  .map((row) => (row['name'] ?? 'Unknown').toString())
                  .cast<String?>()
                  .firstOrNull;
            });
            _fetchCollectors();
          },
        ),
      ),
    );
  }

  Widget _buildActionFilter({
    required IconData icon,
    required String label,
    required String value,
    required Future<void> Function() onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: kPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: kNeutralText,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: kSubtleText,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'OpenSans',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w700,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kPrimary.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: kPrimary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: kPrimaryDark,
              fontWeight: FontWeight.w700,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateSection() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Color(0xFFB45309)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Could not load collector records',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: kNeutralText,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 13,
                color: kSubtleText,
                fontWeight: FontWeight.w600,
                fontFamily: 'OpenSans',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _reloadPageData,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry fetch'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_collectors.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: kBorder),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                size: 42,
                color: kPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _selectedDeceasedId != null
                  ? 'No paid collections for this death notice yet'
                  : 'No collected payments found yet',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                color: kNeutralText,
                fontWeight: FontWeight.w800,
                fontFamily: 'Montserrat',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _hasActiveFilters
                  ? 'Try another filter combination or clear the current filters to see more collector activity.'
                  : _selectedDeceasedId != null
                  ? 'Try another deceased notice or wait until a payment is marked as paid by a collector.'
                  : 'Assigned collectors will appear here once paid collections start coming in.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: kSubtleText,
                fontWeight: FontWeight.w600,
                fontFamily: 'OpenSans',
                height: 1.4,
              ),
            ),
            if (_hasActiveFilters) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () {
                  _clearFilters();
                  _fetchCollectors();
                },
                icon: const Icon(Icons.filter_alt_off_rounded),
                label: const Text('Reset filters'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _gridColumns(constraints.maxWidth);
        final ratio = columns == 1 ? 1.48 : 1.10;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _collectors.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: ratio,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemBuilder: (context, index) {
            final collector = _collectors[index];
            final paymentCount = _asInt(collector['payment_count']);
            final totalCollected = _asDouble(collector['total_collected']);
            final recentPayment = (collector['recent_payment'] ?? '')
                .toString();
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: kBorder),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (collector['collector_name'] ?? 'Collector')
                                  .toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: kNeutralText,
                                fontFamily: 'Montserrat',
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              paymentCount > 0
                                  ? 'Collector has recorded paid remittances'
                                  : 'Assigned but no paid remittances yet',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: kSubtleText,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'OpenSans',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _formatCurrency(totalCollected),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: kPrimary,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildMiniChip(
                        icon: Icons.receipt_long_rounded,
                        label:
                            '$paymentCount payment${paymentCount == 1 ? '' : 's'}',
                        color: const Color(0xFF047857),
                        background: const Color(0xFFECFDF5),
                      ),
                      _buildMiniChip(
                        icon: Icons.schedule_rounded,
                        label: recentPayment.isEmpty
                            ? 'No recent payment'
                            : _formatDate(recentPayment),
                        color: const Color(0xFF1D4ED8),
                        background: const Color(0xFFEFF6FF),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    (collector['collector_note'] ?? '').toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: kSubtleText,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'OpenSans',
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMiniChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      ),
    );
  }
}
