import 'dart:convert';
import 'package:capstone_app/Auth/logout.dart';
import 'package:capstone_app/Beneficiary/beneficiary.dart';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/Treasurer/treasclaims.dart';
import 'package:capstone_app/Treasurer/treascontributions.dart';
import 'package:capstone_app/Treasurer/treasurer_payment_page.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:capstone_app/settings/profsettings.dart';
import 'package:capstone_app/shared/names_only_members_page.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Palette
const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kWarn = Color(0xFFF57C00);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);
const kSubText = Color(0xFF4B5563);
const kText = Color(0xFF1F2937);

class TreasurerDashboardPage extends StatefulWidget {
  const TreasurerDashboardPage({super.key});

  @override
  State<TreasurerDashboardPage> createState() => _TreasurerDashboardPageState();
}

class _TreasurerDashboardPageState extends State<TreasurerDashboardPage> {
  final sb = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();

  String _fullName = 'Treasurer';

  String _dayungLabel = 'Dayung';
  int _tab = 0;
  bool _showNavBar = true;
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
  List<double> _monthlyCollected = List.filled(12, 0);
  List<Map<String, dynamic>> _recentCollections = [];
  List<Map<String, dynamic>> _topDueMembers = [];
  DateTime? _lastRefreshTime;

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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeOnProviderUnitChanged(int? newUnitId) {
    if (newUnitId == null || newUnitId == _lastRoleUnitId) return;
    _lastRoleUnitId = newUnitId;
    setState(() => _dayungUnitId = newUnitId);
    _loadDayungFromPrefs(); // refresh label
    _fetchAll();
  }

  Future<void> _init() async {
    await _loadUserData();
    await _ensureDayungId();
    await _fetchAll();
  }

  Future<void> _loadUserData() async {
    final currentUser = sb.auth.currentUser;
    if (currentUser == null) return;
    try {
      final res = await sb
          .from('users')
          .select('full_name, profile_url')
          .eq('id', currentUser.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _fullName = ((res?['full_name'] ?? 'Treasurer') as String).trim();
      });
    } catch (_) {}
  }

  Future<List<int>> _selectedDayungIds() async {
    await _ensureDayungId();
    if (_dayungUnitId != null) return [_dayungUnitId!];
    return const [];
  }

  Future<void> _loadDayungFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    String label = prefs.getString('selectedDayungUnit') ?? 'Dayung';
    String? jsonFull = prefs.getString('selectedDayungUnitData');
    Map<String, dynamic>? parsed;

    try {
      if (jsonFull != null) {
        parsed = jsonDecode(jsonFull);
      }
    } catch (_) {}
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
    // Prevent refreshing more than once every 2 seconds
    final now = DateTime.now();
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!).inSeconds < 2) {
      return;
    }
    _lastRefreshTime = now;
    setState(() => _loading = true);
    try {
      final selected = await _selectedDayungIds(); // only current dayung

      await Future.wait([
        _fetchActiveMembers(selected),
        _fetchRemovedMembers(selected),
        _fetchTodayDeceasedCount(selected),
        _fetchPendingMembersCount(selected),
        _fetchCurrentFunds(selected),
        _fetchCollectorCollected(selected),
        _fetchTodayCollectedAmount(selected),
        _fetchMonthlyCollected(selected),
        _fetchRecentCollections(selected),
        _fetchTopDueMembers(selected),
        _fetchUnreadNotifCount(selected),
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
    await _fetchUnreadNotifCount(await _selectedDayungIds());
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

  Future<void> _ensureDayungId() async {
    if (_dayungUnitId != null) return;
    await _loadDayungFromPrefs();
    if (_dayungUnitId != null) return;

    try {
      final uid = sb.auth.currentUser?.id;
      if (uid != null) {
        final res = await sb
            .from('dayung_units')
            .select('id')
            .eq('treasurer_id', uid)
            .limit(1);
        final list = List<Map<String, dynamic>>.from(res);
        if (list.isNotEmpty) {
          setState(
            () => _dayungUnitId = int.tryParse(list.first['id'].toString()),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchRemovedMembers(List<int> ids) async {
    try {
      _removedMembers = 0;
      if (ids.isEmpty) return;
      final rows = await sb
          .from('applications')
          .select('id')
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'removed');
      _removedMembers = (rows as List).length;
    } catch (_) {
      _removedMembers = 0;
    }
  }

  Future<void> _fetchTodayDeceasedCount(List<int> ids) async {
    try {
      _todayDeceased = 0;
      if (ids.isEmpty) return;
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));
      final rows = await sb
          .from('claims')
          .select('date_of_death')
          .inFilter('dayung_unit_id', ids)
          .gte('date_of_death', start.toIso8601String())
          .lt('date_of_death', end.toIso8601String());
      _todayDeceased = (rows as List).length;
    } catch (_) {
      _todayDeceased = 0;
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

  Future<void> _fetchCurrentFunds(List<int> ids) async {
    try {
      _currentFunds = 0;
      if (ids.isEmpty) return;
      final rows = await sb
          .from('payments')
          .select('amount')
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'paid');
      double total = 0;
      for (final row in List<Map<String, dynamic>>.from(rows)) {
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
      final rows = await sb
          .from('payments')
          .select('amount')
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'paid');
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

  Future<void> _fetchTodayCollectedAmount(List<int> ids) async {
    try {
      _todayCollected = 0;
      if (ids.isEmpty) return;
      final rows = await sb
          .from('payments')
          .select('amount, paid_at, created_at')
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'paid');
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));
      double total = 0;
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final raw = (row['paid_at'] ?? row['created_at'])?.toString() ?? '';
        final date = DateTime.tryParse(raw);
        if (date == null) continue;
        if (!date.isBefore(start) && date.isBefore(end)) {
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

  Future<void> _fetchMonthlyCollected(List<int> ids) async {
    try {
      _monthlyCollected = List.filled(12, 0);
      if (ids.isEmpty) return;
      final now = DateTime.now();
      final startOfYear = DateTime(now.year, 1, 1).toIso8601String();
      final endOfYear = DateTime(
        now.year,
        12,
        31,
        23,
        59,
        59,
      ).toIso8601String();
      final rows = await sb
          .from('payments')
          .select('amount, paid_at, created_at')
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'paid')
          .gte('created_at', startOfYear)
          .lte('created_at', endOfYear);
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final raw = (row['paid_at'] ?? row['created_at'])?.toString() ?? '';
        final date = DateTime.tryParse(raw);
        if (date == null) continue;
        _monthlyCollected[date.month - 1] += (row['amount'] is num)
            ? (row['amount'] as num).toDouble()
            : double.tryParse('${row['amount']}') ?? 0;
      }
    } catch (_) {
      _monthlyCollected = List.filled(12, 0);
    }
  }

  Future<void> _fetchRecentCollections(List<int> ids) async {
    try {
      _recentCollections = [];
      if (ids.isEmpty) return;
      final rows = await sb
          .from('payments')
          .select(
            'id, amount, paid_at, created_at, user_id, users!payments_user_id_fkey(full_name)',
          )
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'paid')
          .order('paid_at', ascending: false)
          .limit(5);
      _recentCollections = List<Map<String, dynamic>>.from(rows)
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

  Future<void> _fetchTopDueMembers(List<int> ids) async {
    try {
      _topDueMembers = [];
      if (ids.isEmpty) return;
      final rows = await sb
          .from('payments')
          .select(
            'user_id, amount, status, users!payments_user_id_fkey(full_name)',
          )
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'pending');
      final grouped = <String, Map<String, dynamic>>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final userId = (row['user_id'] ?? '').toString();
        if (userId.isEmpty) continue;
        final fullName =
            (row['users'] as Map?)?['full_name']?.toString() ?? 'Member';
        final amount = (row['amount'] is num)
            ? (row['amount'] as num).toDouble()
            : double.tryParse('${row['amount']}') ?? 0;
        final entry = grouped.putIfAbsent(
          userId,
          () => {'user_id': userId, 'member_name': fullName, 'total_due': 0.0},
        );
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
                  'Today: ₱${_todayCollected.toStringAsFixed(0)}',
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
                        if (index < 0 || index >= months.length)
                          return const SizedBox.shrink();
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
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
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
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Top 5 Due Members',
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
                ..._topDueMembers.map(
                  (entry) => GestureDetector(
                    onTap: () {
                      if (_dayungUnitId == null) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TreasurerPaymentPage(
                            dayungUnitId: _dayungUnitId!,
                          ),
                        ),
                      );
                    },
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
                            child: Text(
                              entry['member_name'] ?? 'Member',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
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
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatAmount(dynamic amount) {
    final value = amount is num
        ? amount.toDouble()
        : double.tryParse('$amount') ?? 0.0;
    return '₱${value.toStringAsFixed(0)}';
  }

  List<Widget> get _pages => [
    _homePage(),
    _dayungUnitId == null
        ? const Center()
        : TreasurerContributionsPage(dayungUnitId: _dayungUnitId!),
    _dayungUnitId == null
        ? const SizedBox.shrink()
        : TreasurerClaimsPage(dayungUnitId: _dayungUnitId!),
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
    final wide = width > 820;
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
            child: Column(
              children: [_buildModernHeader(), _buildContentArea(wide)],
            ),
          ),
          _buildFloatingNavBar(wide),
        ],
      ),
    );
  }

  /* ------------------------------- UI parts ------------------------------- */

  Widget _buildModernHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        children: [
          Row(
            children: [
              Builder(
                builder: (context) => Container(
                  padding: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E40AF).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1E40AF).withValues(alpha: 0.3),
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
                      maxLines: 1,
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
              _buildModernIconButton(
                icon: Icons.notifications_active_rounded,
                onTap: _openNotifications,
                badge: _unreadNotifCount > 0 ? '$_unreadNotifCount' : null,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Maayung buntag,\nTreasurer!',
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
              //       color: Colors.white.withOpacity(0.2),
              //       borderRadius: BorderRadius.circular(32),
              //       boxShadow: [
              //         BoxShadow(
              //           color: Colors.black.withOpacity(0.1),
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

  Widget _buildFloatingNavBar(bool wide) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 20,
      child: Center(
        child: IgnorePointer(
          ignoring: !_showNavBar,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: _showNavBar ? 1 : 0,
            child: Container(
              height: 80,
              margin: EdgeInsets.symmetric(horizontal: wide ? 200 : 20),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: dayungSurface(context),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: dayungBorder(context)),
                boxShadow: [dayungElevatedShadow(context)],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNavItem(Icons.dashboard_rounded, "Home", 0),
                  _buildNavItem(Icons.trending_up_rounded, "Contributions", 1),
                  _buildNavItem(Icons.assignment_rounded, "Claims", 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernIconButton({
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

  Widget _buildNavItem(IconData icon, String label, int index) {
    final selected = _tab == index;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF1E40AF).withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected
                  ? const Color(0xFF1E40AF)
                  : const Color(0xFF6B7280),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? const Color(0xFF1E40AF)
                    : const Color(0xFF6B7280),
                height: 1.0,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _homePage() {
    return RefreshIndicator(
      onRefresh: _fetchAll,
      edgeOffset: 68,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOverviewSection(),
            const SizedBox(height: 24),
            _monthlyCollectionCard(),
            const SizedBox(height: 24),
            _recentCollectionsAndDueMembersSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewSection() {
    final cards = [
      _buildStatCard(
        title: 'Active Members',
        value: _loading ? '—' : '$_activeMembers',
        color: const Color(0xFF3B82F6),
        onTap: () => _openNamesOnlyMembersPage('Active Members', ['approved']),
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
      _buildStatCard(
        title: 'Collected by Collectors',
        value: _loading ? '—' : '₱${_collectorCollected.toStringAsFixed(0)}',
        color: const Color(0xFF10B981),
      ),
      _buildStatCard(
        title: 'Pending Members',
        value: _loading ? '—' : '$_pendingMembers',
        color: const Color(0xFFF59E0B),
      ),
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
}
