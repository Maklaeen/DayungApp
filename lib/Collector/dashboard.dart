import 'dart:convert';
import 'package:capstone_app/Collector/collclaims.dart' hide kPrimary;
import 'package:capstone_app/Collector/collcontributions.dart';
import 'package:capstone_app/Collector/collector_receipts_page.dart';
import 'package:capstone_app/Collector/collect_cash.dart';
import 'package:capstone_app/Collector/collector_overall_reports_page.dart';
import 'package:capstone_app/Collector/collector_records_page.dart';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/pages/members_page.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/shared/active_members_page.dart';
import 'package:capstone_app/shared/names_only_members_page.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Additional colors for collector-specific styling
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimaryLight = Color(0xFF3B82F6);
const kAccentDark = Color(0xFF059669);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);
const kBg = Color(0xFFFAFAF7);
const kPrimaryDark = Color(0xFF083366);
const kAccent = Color(0xFF0D47A1);

const double kEdge = 16;

DateTime? _parseDashboardDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

bool _isSameCalendarDay(DateTime? value, DateTime reference) {
  if (value == null) return false;
  return value.year == reference.year &&
      value.month == reference.month &&
      value.day == reference.day;
}

class CollectorDashboardPage extends StatefulWidget {
  const CollectorDashboardPage({super.key});

  @override
  State<CollectorDashboardPage> createState() => _CollectorDashboardPageState();
}

class _CollectorDashboardPageState extends State<CollectorDashboardPage> {
  final sb = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();

  String _dayungLabel = 'Dayung';
  int? _dayungUnitId;
  int? _lastRoleUnitId;
  bool _loading = true;
  int _activeMembers = 0;
  int _removedMembers = 0;
  int _todayDeceased = 0;
  int _pendingMembers = 0;
  int _unreadNotifCount = 0;
  double _currentFunds = 0;
  double _collectorCollected = 0;
  double _todayCollected = 0;
  List<Map<String, dynamic>> _recentCollections = [];
  List<double> _monthlyCollected = List.filled(12, 0);
  List<Map<String, dynamic>> _topDueMembers = [];

  int _tab = 0;
  bool _showNavBar = true;

  @override
  void initState() {
    super.initState();
    _init();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final current = _scrollController.position.pixels;
      if (current >= maxScroll && _showNavBar) {
        setState(() => _showNavBar = false);
      } else if (current < maxScroll && !_showNavBar) {
        setState(() => _showNavBar = true);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provUnit = context.read<DayungRoleProvider>().unitId;
      _maybeOnProviderUnitChanged(provUnit);
    });
  }

  void _maybeOnProviderUnitChanged(int? newUnitId) {
    if (newUnitId == null || newUnitId == _lastRoleUnitId) return;
    _lastRoleUnitId = newUnitId;
    setState(() => _dayungUnitId = newUnitId);
    _loadDayungFromPrefs();
    _fetchAll();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadDayungFromPrefs();
    await _ensureDayungId();
    await _fetchAll();
  }

  Future<void> _ensureDayungId() async {
    if (_dayungUnitId != null) return;
    try {
      final uid = sb.auth.currentUser?.id;
      if (uid == null) return;
      final res = await sb
          .from('users')
          .select('dayung_unit_id')
          .eq('id', uid)
          .maybeSingle();
      final id = res?['dayung_unit_id'];
      if (id != null) {
        setState(() => _dayungUnitId = int.tryParse(id.toString()));
      }
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> _loadDayungFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    String label = prefs.getString('selectedDayungUnit') ?? 'Dayung';
    String? jsonFull = prefs.getString('selectedDayungUnitData');
    Map<String, dynamic>? parsed;

    if (jsonFull != null) {
      try {
        parsed = jsonDecode(jsonFull);
      } catch (_) {}
    }
    if (parsed == null &&
        label.trim().startsWith('{') &&
        label.contains('"name"')) {
      try {
        parsed = jsonDecode(label);
      } catch (_) {}
    }
    if (parsed != null) {
      if ((parsed['name'] ?? '').toString().isNotEmpty) {
        label = parsed['name'];
      }
      final id = parsed['id'];
      if (id != null) _dayungUnitId = int.tryParse(id.toString());
    }
    setState(() => _dayungLabel = label);
  }

  Future<void> _fetchAll() async {
    setState(() => _loading = true);
    try {
      final managed = await _managedDayungIds();
      await Future.wait([
        _fetchActiveMembers(managed),
        _fetchRemovedMembers(managed),
        _fetchTodayDeceasedCount(managed),
        _fetchCurrentFunds(managed),
        _fetchCollectorCollected(managed),
        _fetchPendingMembersCount(managed),
        _fetchTodayCollectedAmount(managed),
        _fetchMonthlyCollected(managed),
        _fetchRecentCollections(managed),
        _fetchTopDueMembers(managed),
        _fetchUnreadNotifCount(managed),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchUnreadNotifCount(List<int> ids) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _unreadNotifCount = 0);
      return;
    }

    try {
      final notifRows = await sb
          .from('notifications')
          .select('id')
          .eq('recipient_id', uid)
          .isFilter('read_at', null);
      int unread = (notifRows as List).length;

      if (ids.isNotEmpty) {
        final annRows = await sb
            .from('announcements')
            .select('id')
            .inFilter('dayung_unit_id', ids);
        final annIds = (annRows as List)
            .map((row) => (row as Map)['id'])
            .whereType<int>()
            .toList();

        if (annIds.isNotEmpty) {
          final reads = await sb
              .from('announcement_reads')
              .select('announcement_id')
              .eq('user_id', uid)
              .inFilter('announcement_id', annIds);
          final readIds = Set<int>.from(
            (reads as List).map(
              (row) => (row as Map)['announcement_id'] as int,
            ),
          );
          unread += annIds.where((id) => !readIds.contains(id)).length;
        }
      }

      if (mounted) {
        setState(() => _unreadNotifCount = unread);
      }
    } catch (_) {
      if (mounted) setState(() => _unreadNotifCount = 0);
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationPage()),
    );
    await _fetchUnreadNotifCount(await _managedDayungIds());
  }

  Future<List<int>> _managedDayungIds() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return <int>[];

    try {
      final rows = await sb
          .from('dayung_collectors')
          .select('dayung_unit_id')
          .eq('user_id', uid);
      final ids = <int>{
        for (final r in List<Map<String, dynamic>>.from(rows))
          if (r['dayung_unit_id'] != null)
            int.tryParse(r['dayung_unit_id'].toString()) ?? -1,
      }..remove(-1);

      if (ids.isNotEmpty) return ids.toList();
    } catch (_) {}

    // Fallback to selected pref (if any)
    if (_dayungUnitId != null) return [_dayungUnitId!];
    return <int>[];
  }

  Future<void> _fetchActiveMembers(List<int> ids) async {
    try {
      if (ids.isEmpty) {
        _activeMembers = 0;
        return;
      }
      final apps = await sb
          .from('applications')
          .select('user_id')
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'approved');
      final usersSet = <String>{};
      for (final r in List<Map<String, dynamic>>.from(apps)) {
        final id = (r['user_id'] ?? '').toString();
        if (id.isNotEmpty) usersSet.add(id);
      }
      if (usersSet.isEmpty) {
        _activeMembers = 0;
        return;
      }
      final users = await sb
          .from('users')
          .select('id,is_deceased')
          .inFilter('id', usersSet.toList());
      final alive = List<Map<String, dynamic>>.from(
        users,
      ).where((u) => (u['is_deceased'] ?? false) == false).length;
      _activeMembers = alive;
    } catch (_) {
      _activeMembers = 0;
    }
  }

  Future<void> _fetchRemovedMembers(List<int> ids) async {
    try {
      if (ids.isEmpty) {
        _removedMembers = 0;
        return;
      }
      final rows = await sb
          .from('applications')
          .select('id')
          .inFilter('dayung_unit_id', ids)
          .isFilter('isRemovedInDayung', true);
      _removedMembers = (rows as List).length;
    } catch (_) {
      _removedMembers = 0;
    }
  }

  Future<void> _fetchTodayDeceasedCount(List<int> ids) async {
    try {
      if (ids.isEmpty) {
        _todayDeceased = 0;
        return;
      }

      final rows = await sb
          .from('claims')
          .select('id, datesetamount')
          .inFilter('dayung_unit_id', ids);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      var count = 0;

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final claimDate = _parseDashboardDate(row['datesetamount']);
        if (_isSameCalendarDay(claimDate, today)) {
          count += 1;
        }
      }

      _todayDeceased = count;
    } catch (_) {
      _todayDeceased = 0;
    }
  }

  bool _isTrueFlag(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;

    final normalized = value.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  Future<void> _fetchCurrentFunds(List<int> ids) async {
    try {
      _currentFunds = 0;
      if (ids.isEmpty) return;
      final collectorId = sb.auth.currentUser?.id;
      if (collectorId == null) return;

      final payments = await sb
          .from('payments')
          .select(
            'amount, status, userdeceased, dayung_unit_id, collected_by, '
            'iscollectedbytreasurer, is_claimed',
          )
          .inFilter('dayung_unit_id', ids)
          .eq('collected_by', collectorId)
          .eq('type', 'deceased_payment')
          .eq('status', 'paid');

      double total = 0;
      for (final row in List<Map<String, dynamic>>.from(payments)) {
        if (_isTrueFlag(row['iscollectedbytreasurer']) ||
            _isTrueFlag(row['is_claimed'])) {
          continue;
        }
        final amount = row['amount'];
        total += (amount is num)
            ? amount.toDouble()
            : double.tryParse('$amount') ?? 0;
      }
      _currentFunds = total;
    } catch (_) {
      _currentFunds = 0;
    }
  }

  Future<void> _fetchCollectorCollected(List<int> ids) async {
    try {
      _collectorCollected = 0;
      if (ids.isEmpty) return;

      // Sum all deceased_payment records for this dayung unit that are marked as paid.
      final rows = await sb
          .from('payments')
          .select('amount, status, type, dayung_unit_id')
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'paid')
          .eq('type', 'deceased_payment');

      double total = 0;
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final amount = row['amount'];
        total += (amount is num)
            ? amount.toDouble()
            : double.tryParse('$amount') ?? 0;
      }
      _collectorCollected = total;
    } catch (_) {
      _collectorCollected = 0;
    }
  }

  Future<void> _fetchPendingMembersCount(List<int> ids) async {
    try {
      _pendingMembers = 0;
      if (ids.isEmpty) return;

      final rows = await sb
          .from('payments')
          .select('user_id, status, dayung_unit_id')
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'pending');

      final memberIds = <String>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final uid = (row['user_id'] ?? '').toString();
        if (uid.isNotEmpty) memberIds.add(uid);
      }
      _pendingMembers = memberIds.length;
    } catch (_) {
      _pendingMembers = 0;
    }
  }

  Future<void> _fetchTodayCollectedAmount(List<int> ids) async {
    try {
      _todayCollected = 0;
      if (ids.isEmpty) return;

      final collectorId = sb.auth.currentUser?.id;
      if (collectorId == null) return;

      final rows = await sb
          .from('payments')
          .select('amount, status, paid_at, created_at, dayung_unit_id')
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'paid')
          .eq('collected_by', collectorId);

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      double total = 0;

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final dateValue =
            (row['paid_at'] ?? row['created_at'])?.toString() ?? '';
        final date = DateTime.tryParse(dateValue);
        if (date == null) continue;
        if (date.isAfter(
              todayStart.subtract(const Duration(milliseconds: 1)),
            ) &&
            date.isBefore(todayEnd)) {
          final amount = row['amount'];
          total += (amount is num)
              ? amount.toDouble()
              : double.tryParse('$amount') ?? 0;
        }
      }
      _todayCollected = total;
    } catch (_) {
      _todayCollected = 0;
    }
  }

  Future<void> _fetchRecentCollections(List<int> ids) async {
    try {
      _recentCollections = [];
      if (ids.isEmpty) return;

      final collectorId = sb.auth.currentUser?.id;
      if (collectorId == null) return;

      final rows = await sb
          .from('payments')
          .select(
            'id, amount, status, paid_at, created_at, user_id, collected_by, users!payments_user_id_fkey(full_name)',
          )
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'paid')
          .eq('collected_by', collectorId)
          .order('paid_at', ascending: false)
          .limit(5);

      final list = List<Map<String, dynamic>>.from(rows);
      _recentCollections = list
          .map(
            (row) => {
              'member_name':
                  (row['users'] as Map?)?['full_name']?.toString() ?? 'Member',
              'amount': row['amount'],
              'date': (row['paid_at'] ?? row['created_at'])?.toString() ?? '',
            },
          )
          .toList();
    } catch (_) {
      _recentCollections = [];
    }
  }

  Future<void> _fetchMonthlyCollected(List<int> ids) async {
    try {
      if (ids.isEmpty) {
        _monthlyCollected = List.filled(12, 0);
        return;
      }

      final now = DateTime.now();
      final monthlyTotals = List.filled(12, 0.0);
      // Include every paid payment in the current year's monthly totals.
      final rows = await sb
          .from('payments')
          .select('amount, paid_at, created_at, status, dayung_unit_id, type')
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'paid');

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final date = DateTime.tryParse(
          (row['paid_at'] ?? row['created_at'])?.toString() ?? '',
        );
        if (date == null || date.year != now.year) continue;
        final monthIndex = date.month - 1;
        final amount = row['amount'];
        monthlyTotals[monthIndex] += (amount is num)
            ? amount.toDouble()
            : double.tryParse('$amount') ?? 0;
      }
      _monthlyCollected = monthlyTotals;
    } catch (_) {
      _monthlyCollected = List.filled(12, 0);
    }
  }

  Future<void> _fetchTopDueMembers(List<int> ids) async {
    try {
      _topDueMembers = [];
      if (ids.isEmpty) return;

      final rows = await sb
          .from('payments')
          .select(
            'user_id, userdeceased, deceased_name, amount, status, is_due, dayung_unit_id, users!payments_user_id_fkey(full_name)',
          )
          .inFilter('dayung_unit_id', ids)
          .inFilter('status', ['pending', 'unpaid']);

      final grouped = <String, Map<String, dynamic>>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        if (!_isTrueFlag(row['is_due'])) continue;
        final memberUserId = (row['user_id'] ?? '').toString();
        final deceasedUserId = (row['userdeceased'] ?? '').toString();
        if (memberUserId.isEmpty || deceasedUserId.isEmpty) continue;
        final fullName =
            (row['users'] as Map?)?['full_name']?.toString() ?? 'Member';
        final deceasedName = (row['deceased_name'] ?? '').toString().trim();
        final amount = (row['amount'] is num)
            ? (row['amount'] as num).toDouble()
            : double.tryParse('${row['amount']}') ?? 0;
        final entry = grouped.putIfAbsent(
          memberUserId,
          () => {
            'user_id': memberUserId,
            'userdeceased': deceasedUserId,
            'member_name': fullName,
            'deceased_name': deceasedName,
            'total_due': 0.0,
            'is_due': true,
          },
        );
        if ((entry['deceased_name'] ?? '').toString().trim().isEmpty &&
            deceasedName.isNotEmpty) {
          entry['deceased_name'] = deceasedName;
        }
        entry['total_due'] = (entry['total_due'] as double) + amount;
      }

      _topDueMembers = grouped.values.toList()
        ..sort(
          (a, b) =>
              (b['total_due'] as double).compareTo(a['total_due'] as double),
        );
      if (_topDueMembers.length > 5) {
        _topDueMembers = _topDueMembers.sublist(0, 5);
      }
    } catch (_) {
      _topDueMembers = [];
    }
  }

  void _openNamesOnlyMembersPage(String title, List<String> statuses) {
    if (_dayungUnitId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NamesOnlyMembersPage(
          dayungUnitId: _dayungUnitId!,
          title: title,
          statuses: statuses,
        ),
      ),
    );
  }

  void _openActiveMembersPage() {
    if (_dayungUnitId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveMembersPage(dayungUnitId: _dayungUnitId!),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required Color color,
    VoidCallback? onTap,
  }) {
    final card = Container(
      padding: const EdgeInsets.all(16),
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
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }

  String _formatAmount(dynamic amount) {
    final value = (amount is num)
        ? amount.toDouble()
        : double.tryParse('$amount') ?? 0.0;
    return '₱${value.toStringAsFixed(0)}';
  }

  Widget _monthlyCollectionCard() {
    final totals = _monthlyCollected;
    final maxY = totals.isNotEmpty
        ? totals.reduce((a, b) => a > b ? a : b)
        : 0.0;
    final chartMax = maxY <= 0 ? 100.0 : maxY * 1.25;
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
                  color: const Color(0xFF0D47A1).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Current: ₱${_todayCollected.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0D47A1),
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
                  color: Color(0xFF6B7280),
                  fontFamily: 'OpenSans',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                maxY: chartMax,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final month = months[group.x.toInt()];
                      return BarTooltipItem(
                        '$month\n',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        children: [
                          TextSpan(
                            text: '₱${rod.toY.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      );
                    },
                    getTooltipColor: (group) => Colors.blueGrey.shade900,
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: AxisTitles(
                    sideTitles: const SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: const SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      interval: chartMax / 4,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '₱${value.toInt()}',
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= months.length) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            months[index],
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 10,
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
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.withValues(alpha: 0.15),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(
                  totals.length,
                  (index) => BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: totals[index],
                        color: const Color(0xFF0D47A1),
                        width: 14,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Monthly Cash Collection',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              Text(
                'Total: ₱${totals.fold(0.0, (sum, value) => sum + value).toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recentCollectionsAndDueMembersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: dayungSectionCardDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recent Collections',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E40AF),
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 12),
              if (_recentCollections.isEmpty)
                const Text(
                  'No recent collections yet.',
                  style: TextStyle(color: Color(0xFF6B7280)),
                )
              else
                ..._recentCollections.map(
                  (row) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            row['member_name'] ?? 'Member',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatAmount(row['amount']),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Color(0xFF0D47A1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: dayungSectionCardDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Due Members',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E40AF),
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 12),
              if (_topDueMembers.isEmpty)
                const Text(
                  'No pending members found.',
                  style: TextStyle(color: Color(0xFF6B7280)),
                )
              else
                ..._topDueMembers.map((entry) {
                  return GestureDetector(
                    onTap: () => _recordCashPayment(
                      deceasedUserId: (entry['userdeceased'] ?? '').toString(),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Member Name: ${entry['member_name'] ?? 'Member'}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (_isTrueFlag(entry['is_due']))
                                  Text(
                                    (entry['deceased_name'] ?? '')
                                            .toString()
                                            .trim()
                                            .isEmpty
                                        ? 'Deceased Name: N/A'
                                        : 'Deceased Name: ${(entry['deceased_name'] ?? '').toString()}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            _formatAmount(entry['total_due']),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  // List<Widget> get _pages => [
  //   _homePage(),
  //   _dayungUnitId == null
  //       ? const Center(child: Text('Select a Dayung unit first'))
  //       : MembersContributionHistory(dayungUnitId: _dayungUnitId!),
  //   _dayungUnitId == null
  //       ? const Center(child: Text('Select a Dayung unit first'))
  //       : MembersClaimsPage(dayungUnitId: _dayungUnitId!),
  // ];

  List<Widget> get _pages => [
    _homePage(),
    _dayungUnitId == null
        ? const Center(child: Text('Select a Dayung unit first'))
        : CollectorContributionsPage(dayungUnitId: _dayungUnitId!),
    _dayungUnitId == null
        ? const Center(child: Text('Select a Dayung unit first'))
        : CollectorClaimsPage(dayungUnitId: _dayungUnitId!),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provUnit = context.watch<DayungUnitProvider>().currentUnitId;
    if (provUnit != _lastRoleUnitId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeOnProviderUnitChanged(provUnit);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool wide = width > 820;
    // final provUnit = context.watch<DayungRoleProvider>().unitId;
    // if (provUnit != _lastRoleUnitId) {
    //   WidgetsBinding.instance.addPostFrameCallback((_) {
    //     _maybeOnProviderUnitChanged(provUnit);
    //   });
    // }
    return Container(
      decoration: BoxDecoration(gradient: dayungDashboardGradient(context)),
      child: Stack(
        children: [
          SafeArea(
            child: Column(children: [_topBar(), _buildContentArea(wide)]),
          ),
          _bottomNav(wide),
        ],
      ),
    );
  }

  /* ------------------------------- UI parts ------------------------------- */

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        children: [
          // Top bar
          Row(
            children: [
              Builder(
                builder: (context) => Container(
                  padding: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: kPrimary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.menu_rounded, color: Colors.white),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _dayungLabel,
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              _iconBtn(
                icon: Icons.notifications_rounded,
                onTap: _openNotifications,
                badge: _unreadNotifCount > 0 ? '$_unreadNotifCount' : null,
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Greeting section
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Maayung buntag,\nCollector!',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              // GestureDetector(
              //   onTap: () {
              //     Navigator.push(
              //       context,
              //       MaterialPageRoute(builder: (_) => const ProfilePage()),
              //     );
              //   },
              //   child: Container(
              //     padding: const EdgeInsets.all(4),
              //     decoration: BoxDecoration(
              //       color: Colors.white.withValues(alpha: 0.2),
              //       borderRadius: BorderRadius.circular(32),
              //       boxShadow: [
              //         BoxShadow(
              //           color: Colors.black.withValues(alpha: 0.1),
              //           blurRadius: 8,
              //           offset: const Offset(0, 2),
              //         ),
              //       ],
              //     ),
              //     child: const CircleAvatar(
              //       radius: 28,
              //       backgroundColor: Colors.white,
              //       child: Icon(
              //         Icons.person,
              //         size: 34,
              //         color: Color(0xFF1E40AF),
              //       ),
              //     ),
              //   ),
              // ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Modern Content Area ---
  Widget _buildContentArea(bool wide) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: dayungSurface(context),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [dayungTopShadow(context)],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: IndexedStack(index: _tab, children: _pages),
          ),
        ),
      ),
    );
  }

  // --- Modern Floating NavBar ---
  Widget _bottomNav(bool wide) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 16,
      child: Center(
        child: IgnorePointer(
          ignoring: !_showNavBar,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: _showNavBar ? 1.0 : 0.0,
            child: Container(
              constraints: const BoxConstraints(minHeight: 80, maxHeight: 90),
              margin: EdgeInsets.symmetric(
                horizontal: wide
                    ? MediaQuery.of(context).size.width * 0.15
                    : 16,
              ),
              decoration: BoxDecoration(
                color: dayungSurface(context),
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  dayungElevatedShadow(context),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(color: dayungBorder(context), width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _navBarItem(
                      icon: Icons.dashboard_rounded,
                      label: 'Dashboard',
                      selected: _tab == 0,
                      onTap: () => setState(() => _tab = 0),
                    ),
                    _navBarItem(
                      icon: Icons.trending_up_rounded,
                      label: 'Contributions',
                      selected: _tab == 1,
                      onTap: () => setState(() => _tab = 1),
                    ),
                    _navBarItem(
                      icon: Icons.assignment_rounded,
                      label: 'Claims',
                      selected: _tab == 2,
                      onTap: () => setState(() => _tab = 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Modern Icon Button ---
  Widget _iconBtn({
    required IconData icon,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
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
    );
  }

  // --- Modern Nav Item ---
  Widget _navBarItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              constraints: const BoxConstraints(minHeight: 56, maxHeight: 64),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF1E40AF).withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: selected
                    ? Border.all(
                        color: const Color(0xFF1E40AF).withValues(alpha: 0.3),
                        width: 1,
                      )
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF1E40AF)
                          : Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFF1E40AF,
                                ).withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      icon,
                      color: selected ? Colors.white : Colors.grey[700],
                      size: 20,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF1E40AF)
                          : Colors.grey[700],
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 12,
                      letterSpacing: 0.2,
                      fontFamily: 'Montserrat',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _homePage() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _overviewSection(),
          const SizedBox(height: 24),
          _monthlyCollectionCard(),
          const SizedBox(height: 24),
          _recentCollectionsAndDueMembersSection(),
          const SizedBox(height: 24),
          _modernActionCards(),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _overviewSection() {
    final cards = [
      _buildStatCard(
        title: 'Active Members',
        value: _loading ? '—' : '$_activeMembers',
        color: const Color(0xFF3B82F6),
        onTap: _openActiveMembersPage,
      ),
      _buildStatCard(
        title: 'Removed / Inactive',
        value: _loading ? '—' : '$_removedMembers',
        color: const Color(0xFFEF4444),
        onTap: () => _openNamesOnlyMembersPage('Removed Members', ['removed']),
      ),
      _buildStatCard(
        title: 'Today’s Deceased',
        value: _loading ? '—' : '$_todayDeceased',
        color: const Color(0xFF8B5CF6),
      ),
      _buildStatCard(
        title: 'Current Funds',
        value: _loading ? '—' : '₱${_currentFunds.toStringAsFixed(0)}',
        color: const Color(0xFF0D47A1),
      ),
      // _buildStatCard(
      //   title: 'Collected by Collectors',
      //   value: _loading ? '—' : '₱${_collectorCollected.toStringAsFixed(0)}',
      //   color: const Color(0xFF10B981),
      // ),
      // Pending members is currently temporary and hidden until final behavior is confirmed.
      // _buildStatCard(
      //   title: 'Pending Members',
      //   value: _loading ? '—' : '$_pendingMembers',
      //   color: const Color(0xFFF59E0B),
      // ),
      _buildStatCard(
        title: 'Today’s Collected',
        value: _loading ? '—' : '₱${_todayCollected.toStringAsFixed(0)}',
        color: const Color(0xFF2563EB),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: dayungSectionCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Overview',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E40AF),
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: cards
                .map((card) => SizedBox(width: 170, height: 130, child: card))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _modernActionCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E40AF),
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 120,
                child: _modernActionCardGrid(
                  icon: Icons.receipt_long_rounded,
                  title: 'View Receipts',
                  color: kSuccess,
                  onTap: _showReceipts,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 120,
                child: _modernActionCardGrid(
                  icon: Icons.qr_code_rounded,
                  title: 'Collect Cash',
                  color: kPrimary,
                  onTap: () {
                    if (_dayungUnitId == null) return;
                    () async {
                      final changed = await Navigator.push<bool?>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              CollectCashPage(dayungUnitId: _dayungUnitId!),
                        ),
                      );
                      if (changed == true) await _fetchAll();
                    }();
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: _modernActionCardGrid(
            icon: Icons.people_rounded,
            title: 'Members',
            color: kAccent,
            onTap: _showMembers,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 120,
                child: _modernActionCardGrid(
                  icon: Icons.table_rows_rounded,
                  title: 'Collector Records',
                  color: const Color(0xFF0D47A1),
                  onTap: () {
                    if (_dayungUnitId == null) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CollectorRecordsPage(dayungUnitId: _dayungUnitId!),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 120,
                child: _modernActionCardGrid(
                  icon: Icons.assessment_rounded,
                  title: 'Overall Reports',
                  color: const Color(0xFF2E7D32),
                  onTap: () {
                    if (_dayungUnitId == null) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CollectorOverallReportsPage(
                          dayungUnitId: _dayungUnitId!,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _modernActionCardGrid({
    required IconData icon,
    required String title,
    required Color color,
    VoidCallback? onTap,
  }) {
    final isCompact = MediaQuery.of(context).size.width < 360;
    final titleFontSize = isCompact ? 12.0 : 14.0;
    final contentGap = isCompact ? 6.0 : 8.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: color.withValues(alpha: 0.1),
        highlightColor: color.withValues(alpha: 0.05),
        child: Ink(
          decoration: BoxDecoration(
            color: dayungSurface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: dayungBorder(context)),
            boxShadow: [dayungElevatedShadow(context)],
          ),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                SizedBox(height: contentGap),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _recordCashPayment({String? deceasedUserId}) {
    if (_dayungUnitId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No dayung selected.')));
      return;
    }
    () async {
      final changed = await Navigator.push<bool?>(
        context,
        MaterialPageRoute(
          builder: (_) => CollectCashPage(
            dayungUnitId: _dayungUnitId!,
            preselectedDeceasedUserId: deceasedUserId,
          ),
        ),
      );
      if (changed == true) await _fetchAll();
    }();
  }

  void _showReceipts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CollectorReceiptsPage(dayungUnitId: _dayungUnitId),
      ),
    );
  }

  void _showMembers() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MembersPage(dayungUnitId: _dayungUnitId), // Pass ID if needed
      ),
    );
  }
}
