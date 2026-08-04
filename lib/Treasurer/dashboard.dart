import 'dart:convert';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/Treasurer/collected.dart';
import 'package:capstone_app/Treasurer/manage_fund.dart';
import 'package:capstone_app/Treasurer/membership_page.dart';
import 'package:capstone_app/Treasurer/paid_unpaid_members_page.dart';
import 'package:capstone_app/Treasurer/treasclaims.dart';
import 'package:capstone_app/Treasurer/treascontributions.dart';
import 'package:capstone_app/Treasurer/ledger_balance.dart';
import 'package:capstone_app/Treasurer/payment_release_history.dart';
import 'package:capstone_app/Treasurer/treasurer_payment_page.dart';
import 'package:capstone_app/Collector/gcash_qr_page.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/pages/recentdeathnotices.dart';
import 'package:capstone_app/Treasurer/assign_collectors_page.dart';
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

bool _isTruthyFlagValue(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    return ['true', '1', 'yes'].contains(value.trim().toLowerCase());
  }
  return false;
}

bool shouldCountCurrentFundPayment(Map<String, dynamic> row) {
  if (!_isTruthyFlagValue(row['iscollectedbytreasurer'])) return false;
  if (_isTruthyFlagValue(row['is_claimed'])) return false;
  if ((row['status']?.toString().toLowerCase() ?? '') != 'paid') return false;
  if ((row['type']?.toString().toLowerCase() ?? '') != 'deceased_payment') {
    return false;
  }
  return true;
}

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
  double _pendingAmount = 0;
  double _currentFunds = 0;
  double _collectorCollected = 0;
  double _todayCollected = 0;
  List<double> _monthlyCollected = List.filled(12, 0);
  List<Map<String, dynamic>> _recentCollections = [];
  List<Map<String, dynamic>> _topDueMembers = [];
  List<String> _recentDeaths = [];
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
        _fetchPendingAmount(selected),
        _fetchCurrentFunds(selected),
        _fetchCollectorCollected(selected),
        _fetchTodayCollectedAmount(selected),
        _fetchMonthlyCollected(selected),
        _fetchRecentCollections(selected),
        _fetchTopDueMembers(selected),
        _fetchRecentDeaths(selected),
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
          .isFilter('isRemovedInDayung', true);
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

  bool _isTruthyFlag(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      return ['true', '1', 'yes'].contains(value.trim().toLowerCase());
    }
    return false;
  }

  Future<void> _fetchCurrentFunds(List<int> ids) async {
    try {
      _currentFunds = 0;
      if (ids.isEmpty) return;
      final rows = await sb
          .from('payments')
          .select('amount, iscollectedbytreasurer')
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'paid')
          .eq('type', 'deceased_payment');
      double total = 0;
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        if (!shouldCountCurrentFundPayment(row)) continue;
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

  Future<void> _fetchPendingAmount(List<int> ids) async {
    try {
      _pendingAmount = 0;
      if (ids.isEmpty) return;
      final rows = await sb
          .from('payments')
          .select('amount')
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'pending');
      double total = 0;
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final amount = row['amount'];
        total += (amount is num)
            ? amount.toDouble()
            : double.tryParse('$amount') ?? 0;
      }
      _pendingAmount = total;
    } catch (_) {
      _pendingAmount = 0;
    }
  }

  Future<void> _fetchRecentDeaths(List<int> ids) async {
    try {
      _recentDeaths = [];
      if (ids.isEmpty) return;
      final rows = await sb
          .from('claims')
          .select('PassedAway,user_id,date_of_death,datesetamount')
          .inFilter('dayung_unit_id', ids)
          .ilike('status', 'approved')
          .order('datesetamount', ascending: false)
          .limit(5);
      final claims = List<Map<String, dynamic>>.from(rows);
      final userIds = claims
          .map((row) => row['user_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final userNames = <String, String>{};
      if (userIds.isNotEmpty) {
        final users = await sb
            .from('users')
            .select('id, full_name')
            .inFilter('id', userIds);
        for (final user in List<Map<String, dynamic>>.from(users)) {
          final id = user['id']?.toString();
          final name = user['full_name']?.toString();
          if (id != null && name != null && name.trim().isNotEmpty) {
            userNames[id] = name.trim();
          }
        }
      }
      _recentDeaths = claims
          .map(
            (row) =>
                userNames[row['user_id']?.toString()] ??
                (row['PassedAway'] ?? 'Member').toString(),
          )
          .toList();
    } catch (_) {
      _recentDeaths = [];
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

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Access',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E40AF),
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(height: 12),
        _buildModernActionCard(
          icon: Icons.account_balance_wallet_rounded,
          title: 'Ledger Balance',
          subtitle: 'Confirm remitted funds before posting to the ledger',
          color: const Color(0xFF3B82F6),
          onTap: () {
            if (_dayungUnitId == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Select a Dayung first')),
              );
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LedgerBalancePage(dayungUnitId: _dayungUnitId!),
              ),
            ).then((_) => _fetchAll());
          },
        ),
        const SizedBox(height: 8),
        _buildModernActionCard(
          icon: Icons.account_balance_wallet_rounded,
          title: 'Manage Fund',
          subtitle: 'View and manage fund details',
          color: const Color(0xFF3B82F6),
          onTap: () {
            if (_dayungUnitId == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Select a Dayung first')),
              );
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ManageFundPage(dayungUnitId: _dayungUnitId!),
              ),
            ).then((_) => _fetchAll());
          },
        ),
        const SizedBox(height: 8),
        _buildModernActionCard(
          icon: Icons.history_rounded,
          title: 'Payment Release History',
          subtitle: 'View claimed payments and release dates',
          color: const Color(0xFF0D9488),
          onTap: () {
            if (_dayungUnitId == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Select a Dayung first')),
              );
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    PaymentReleaseHistoryPage(dayungUnitId: _dayungUnitId!),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        _buildModernActionCard(
          icon: Icons.payments_rounded,
          title: 'My Payment Page',
          subtitle: 'Pay your own contribution records',
          color: const Color(0xFF2563EB),
          onTap: () {
            if (_dayungUnitId == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Select a Dayung first')),
              );
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    TreasurerPaymentPage(dayungUnitId: _dayungUnitId!),
              ),
            ).then((_) => _fetchAll());
          },
        ),
        const SizedBox(height: 8),
        _buildModernActionCard(
          icon: Icons.verified_user_rounded,
          title: 'Paid & Unpaid Members',
          subtitle: 'View paid and unpaid member records in one place',
          color: const Color(0xFF10B981),
          onTap: () {
            if (_dayungUnitId == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Select a Dayung first')),
              );
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    PaidUnpaidMembersPage(dayungUnitId: _dayungUnitId!),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        _buildModernActionCard(
          icon: Icons.qr_code_2_rounded,
          title: 'Open GCash QR',
          subtitle: 'Show payment QR',
          color: const Color(0xFFF59E0B),
          onTap: () {
            if (_dayungUnitId == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Select a Dayung first')),
              );
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GcashQrPage(dayungUnitId: _dayungUnitId!),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        _buildModernActionCard(
          icon: Icons.group_add_rounded,
          title: 'Assign Collectors',
          subtitle: 'Assign collectors to members',
          color: const Color(0xFF8B5CF6),
          onTap: () {
            if (_dayungUnitId == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Select a Dayung first')),
              );
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AssignCollectorsPage(dayungUnitId: _dayungUnitId!),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        _buildModernActionCard(
          icon: Icons.people_alt_rounded,
          title: 'Membership',
          subtitle: 'View and manage membership',
          color: const Color(0xFF8B5CF6),
          onTap: () {
            if (_dayungUnitId == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Select a Dayung first')),
              );
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MembershipPage(dayungUnitId: _dayungUnitId!),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildModernActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: dayungSurface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dayungBorder(context)),
        boxShadow: [dayungElevatedShadow(context)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: color.withValues(alpha: 0.6),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Activity',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: dayungSectionCardDecoration(context, radius: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: dayungAccentSurface(
                        context,
                        const Color(0xFFEC4899),
                        lightAlpha: 0.08,
                        darkAlpha: 0.14,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.family_restroom_rounded,
                      color: Color(0xFFEC4899),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Death Notice Queue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: dayungTextColor(context),
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      if (_dayungUnitId == null) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              RecentDeathNotices(dayungUnitId: _dayungUnitId),
                        ),
                      );
                    },
                    child: const Text(
                      'View All',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF3B82F6),
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_recentDeaths.isEmpty)
                const Text(
                  'No recent activity yet.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                    fontFamily: 'OpenSans',
                  ),
                )
              else
                ..._recentDeaths
                    .take(5)
                    .map(
                      (name) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF3B82F6),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF111827),
                                  fontFamily: 'OpenSans',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCollectedSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF059669)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.account_balance_rounded,
            color: Colors.white,
            size: 32,
          ),
          const SizedBox(height: 12),
          const Text(
            'Collected from Collectors',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (_dayungUnitId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Select a Dayung first')),
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CollectedFromCollectorsPage(
                        dayungUnitId: _dayungUnitId!,
                      ),
                    ),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Text(
                    'View Collections',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeathNoticesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Death Notices',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E40AF),
                fontFamily: 'Montserrat',
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                if (_dayungUnitId == null) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        RecentDeathNotices(dayungUnitId: _dayungUnitId!),
                  ),
                );
              },
              child: const Text(
                'View All',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3B82F6),
                  fontFamily: 'Montserrat',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_recentDeaths.isEmpty)
                const Text(
                  'No death notices yet.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                )
              else
                ..._recentDeaths
                    .take(5)
                    .map(
                      (name) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.notifications_active_rounded,
                              color: Color(0xFF0D47A1),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111827),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Future<Object?> _fetchDayungCollectorId() async {
    if (_dayungUnitId == null) return null;
    try {
      final result = await sb
          .from('dayung_units')
          .select('collector_id')
          .eq('id', _dayungUnitId as Object)
          .maybeSingle();
      if (result == null) return null;
      return result['collector_id'];
    } catch (_) {
      return null;
    }
  }

  Future<bool> _markPaymentAsPaid(String paymentId) async {
    final currentUserId = sb.auth.currentUser?.id;
    if (currentUserId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to mark payment: no logged-in user.'),
          ),
        );
      }
      return false;
    }

    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await sb
          .from('payments')
          .update({
            'status': 'paid',
            'collected_by': currentUserId,
            'paid_at': now,
          })
          .eq('id', paymentId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment marked as paid.')),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update payment: $e')));
      }
      return false;
    }
  }

  Future<void> _showMembersModal({required bool paid}) async {
    if (_dayungUnitId == null) return;
    final statuses = paid ? ['paid'] : ['pending', 'unpaid'];
    final members = <Map<String, dynamic>>[];
    final searchController = TextEditingController();
    var filteredMembers = <Map<String, dynamic>>[];
    final processingIds = <String>{};
    var updated = false;

    void applyFilter(String query) {
      final normalized = query.trim().toLowerCase();
      if (normalized.isEmpty) {
        filteredMembers = List<Map<String, dynamic>>.from(members);
      } else {
        filteredMembers = members.where((entry) {
          final name = (entry['name'] ?? '').toString().toLowerCase();
          final status = (entry['status'] ?? '').toString().toLowerCase();
          return name.contains(normalized) || status.contains(normalized);
        }).toList();
      }
    }

    try {
      final rows = await sb
          .from('payments')
          .select(
            'id, user_id, amount, status, paid_at, created_at, users!payments_user_id_fkey(full_name)',
          )
          .inFilter('dayung_unit_id', [_dayungUnitId!])
          .inFilter('status', statuses)
          .order('created_at', ascending: false);

      final paymentRows = List<Map<String, dynamic>>.from(
        rows as List<dynamic>,
      );
      for (final row in paymentRows) {
        final userId = '${row['user_id'] ?? ''}';
        if (userId.isEmpty) continue;
        final userName =
            ((row['users'] as Map?)?['full_name']?.toString() ?? 'Member');
        members.add({
          'id': row['id']?.toString() ?? '',
          'name': userName,
          'status': row['status']?.toString() ?? '',
          'amount': row['amount']?.toString() ?? '0',
          'date': (row['paid_at'] ?? row['created_at'])?.toString() ?? '',
        });
      }
      applyFilter('');
    } catch (_) {
      // ignore errors and show empty state
    }

    if (!mounted) {
      searchController.dispose();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, modalSetState) {
                return Container(
                  decoration: BoxDecoration(
                    color: dayungSurface(context),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                paid ? 'Paid Members' : 'Unpaid Members',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: TextField(
                          controller: searchController,
                          onChanged: (value) {
                            modalSetState(() => applyFilter(value));
                          },
                          decoration: InputDecoration(
                            hintText: 'Search by name or status',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: dayungSurface(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Colors.grey.withOpacity(0.3),
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: filteredMembers.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 24,
                                ),
                                child: Text(
                                  members.isEmpty
                                      ? paid
                                            ? 'No paid members found.'
                                            : 'No unpaid members found.'
                                      : 'No matching members found.',
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 15,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                itemCount: filteredMembers.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 0),
                                itemBuilder: (_, index) {
                                  final entry = filteredMembers[index];
                                  final paymentId =
                                      entry['id']?.toString() ?? '';
                                  final isProcessing = processingIds.contains(
                                    paymentId,
                                  );
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(entry['name'] ?? 'Member'),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(entry['status'] ?? ''),
                                        const SizedBox(height: 4),
                                        Text(
                                          '₱${entry['amount']} • ${entry['date']}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: paid
                                        ? const Icon(
                                            Icons.check_circle_outline,
                                            color: Color(0xFF10B981),
                                          )
                                        : ElevatedButton(
                                            onPressed:
                                                paymentId.isEmpty ||
                                                    isProcessing
                                                ? null
                                                : () async {
                                                    modalSetState(() {
                                                      processingIds.add(
                                                        paymentId,
                                                      );
                                                    });
                                                    final success =
                                                        await _markPaymentAsPaid(
                                                          paymentId,
                                                        );
                                                    modalSetState(() {
                                                      processingIds.remove(
                                                        paymentId,
                                                      );
                                                    });
                                                    if (success) {
                                                      updated = true;
                                                      modalSetState(() {
                                                        members.removeWhere(
                                                          (item) =>
                                                              item['id']
                                                                  .toString() ==
                                                              paymentId,
                                                        );
                                                        filteredMembers.removeWhere(
                                                          (item) =>
                                                              item['id']
                                                                  .toString() ==
                                                              paymentId,
                                                        );
                                                      });
                                                    }
                                                  },
                                            child: isProcessing
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor:
                                                          AlwaysStoppedAnimation(
                                                            Colors.white,
                                                          ),
                                                    ),
                                                  )
                                                : const Text('Mark Paid'),
                                          ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );

    searchController.dispose();
    if (updated && mounted) {
      await _fetchAll();
    }
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
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
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
        // const SizedBox(height: 16),
        // Container(
        //   padding: const EdgeInsets.all(20),
        //   decoration: BoxDecoration(
        //     color: Colors.white,
        //     borderRadius: BorderRadius.circular(20),
        //     border: Border.all(color: Colors.grey.shade200),
        //     boxShadow: [
        //       BoxShadow(
        //         color: Colors.black.withAlpha(10),
        //         blurRadius: 12,
        //         offset: const Offset(0, 4),
        //       ),
        //     ],
        //   ),
        //   child: Column(
        //     crossAxisAlignment: CrossAxisAlignment.start,
        //     children: [
        //       const Text(
        //         'Top 5 Due Members',
        //         style: TextStyle(
        //           fontSize: 18,
        //           fontWeight: FontWeight.w800,
        //           color: Color(0xFF1E40AF),
        //           fontFamily: 'Montserrat',
        //         ),
        //       ),
        //       const SizedBox(height: 12),
        //       if (_topDueMembers.isEmpty)
        //         const Text(
        //           'No pending members found.',
        //           style: TextStyle(color: Color(0xFF6B7280)),
        //         )
        //       else
        //         ..._topDueMembers.map(
        //           (entry) => GestureDetector(
        //             onTap: () {
        //               if (_dayungUnitId == null) return;
        //               Navigator.push(
        //                 context,
        //                 MaterialPageRoute(
        //                   builder: (_) => TreasurerPaymentPage(
        //                     dayungUnitId: _dayungUnitId!,
        //                   ),
        //                 ),
        //               );
        //             },
        //             child: Container(
        //               margin: const EdgeInsets.only(bottom: 10),
        //               padding: const EdgeInsets.all(14),
        //               decoration: BoxDecoration(
        //                 color: Colors.white,
        //                 borderRadius: BorderRadius.circular(16),
        //                 border: Border.all(color: const Color(0xFFE5E7EB)),
        //               ),
        //               child: Row(
        //                 children: [
        //                   Expanded(
        //                     child: Text(
        //                       entry['member_name'] ?? 'Member',
        //                       style: const TextStyle(
        //                         fontSize: 14,
        //                         fontWeight: FontWeight.w700,
        //                       ),
        //                     ),
        //                   ),
        //                   Text(
        //                     _formatAmount(entry['total_due']),
        //                     style: const TextStyle(
        //                       fontSize: 14,
        //                       fontWeight: FontWeight.w700,
        //                       color: Color(0xFFEF4444),
        //                     ),
        //                   ),
        //                 ],
        //               ),
        //             ),
        //           ),
        //         ),
        //     ],
        //   ),
        // ),
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
    final bool isDesktop = width > 1024;
    final provUnit = context.watch<DayungRoleProvider>().unitId;
    if (provUnit != _lastRoleUnitId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeOnProviderUnitChanged(provUnit);
      });
    }

    if (isDesktop) {
      return Material(
        child: Container(
          decoration: BoxDecoration(gradient: dayungDashboardGradient(context)),
          child: Stack(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    _buildModernHeader(showMenuButton: false),
                    _buildContentArea(wide),
                  ],
                ),
              ),
              _buildFloatingNavBar(wide),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(gradient: dayungDashboardGradient(context)),
      child: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildModernHeader(showMenuButton: true),
                _buildContentArea(wide),
              ],
            ),
          ),
          _buildFloatingNavBar(wide),
        ],
      ),
    );
  }

  /* ------------------------------- UI parts ------------------------------- */

  Widget _buildModernHeader({bool showMenuButton = false}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        children: [
          Row(
            children: [
              if (showMenuButton)
                Builder(
                  builder: (context) => Container(
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
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
              if (showMenuButton) const SizedBox(width: 16),
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
            _buildQuickActions(),
            const SizedBox(height: 24),
            _buildRecentActivity(),
            const SizedBox(height: 24),
            _buildCollectedSection(),
            const SizedBox(height: 24),
            _monthlyCollectionCard(),
            const SizedBox(height: 24),
            _recentCollectionsAndDueMembersSection(),
            const SizedBox(height: 24),
            _buildDeathNoticesSection(),
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
      // _buildStatCard(
      //   title: 'Today’s Deceased',
      //   value: _loading ? '—' : '$_todayDeceased',
      //   color: const Color(0xFF8B5CF6),
      // ),
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
