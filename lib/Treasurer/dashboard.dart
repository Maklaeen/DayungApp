import 'dart:convert';
import 'package:capstone_app/Treasurer/collected.dart';
import 'package:capstone_app/Treasurer/manage_fund.dart';
import 'package:capstone_app/pages/claims.dart';
import 'package:capstone_app/pages/notification.dart';
import 'package:capstone_app/profile/profile.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/foundation.dart';

// Palette
const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kWarn = Color(0xFFF57C00);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);

class TreasurerDashboardPage extends StatefulWidget {
  const TreasurerDashboardPage({super.key});

  @override
  State<TreasurerDashboardPage> createState() => _TreasurerDashboardPageState();
}

class _TreasurerDashboardPageState extends State<TreasurerDashboardPage> {
  final sb = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();
  Future<List<Map<String, dynamic>>>? _deathNoticesFutureCached;
  Future<Map<int, Map<String, dynamic>>>? _paymentStatsFutureCached;
  List<int> _lastNoticeIds = const [];
  int? _lastStatsDayungId;

  String _dayungLabel = 'Dayung';
  int? _dayungUnitId;

  bool _loading = true;
  int _activeMembers = 0;
  double _pendingAmount = 0;
  int _pendingMembers = 0;
  DateTime? _lastRefreshTime;
  List<String> _recentDeaths = [];

  int _tab = 0;
  bool _showNavBar = true;

  @override
  void initState() {
    super.initState();
    // Prime the notices future immediately so the first build doesn't recreate it
    _deathNoticesFutureCached = _deathNoticesFuture();
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
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _ensureDayungId();
    await _fetchAll();
  }

  void _ensureStatsFuture(List<int> noticeIds, int dayungUnitId) {
    if (_paymentStatsFutureCached != null &&
        listEquals(_lastNoticeIds, noticeIds) &&
        _lastStatsDayungId == dayungUnitId) {
      return;
    }
    _lastNoticeIds = List<int>.from(noticeIds);
    _lastStatsDayungId = dayungUnitId;
    _paymentStatsFutureCached = _paymentStatsByNotice(noticeIds, dayungUnitId);
  }

  Future<List<int>> _selectedDayungIds() async {
    await _ensureDayungId();
    if (_dayungUnitId != null) return [_dayungUnitId!];
    return const [];
  }

  Future<List<Map<String, dynamic>>> _deathNoticesFuture() async {
    final ids = await _selectedDayungIds();
    return _fetchDeathNotices(ids);
  }

  Future<List<Map<String, dynamic>>> _fetchDeathNotices(
    List<int> dayungIds,
  ) async {
    try {
      final ids = dayungIds.isNotEmpty
          ? dayungIds
          : (_dayungUnitId != null ? [_dayungUnitId!] : const <int>[]);
      if (ids.isEmpty) return [];

      // A) direct matches on death_notices.dayung_unit_id
      final dnDirect = await sb
          .from('death_notices')
          .select('id,name,date_of_death,dayung_unit_id,user_id')
          .inFilter('dayung_unit_id', ids)
          .order('date_of_death', ascending: false);

      final direct = List<Map<String, dynamic>>.from(dnDirect);

      // B) rows where dayung_unit_id is NULL but user's dayung matches
      final usersRes = await sb
          .from('users')
          .select('id')
          .inFilter('dayung_unit_id', ids);
      final userIds = List<Map<String, dynamic>>.from(usersRes)
          .map((e) => (e['id'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();

      List<Map<String, dynamic>> viaUser = [];
      if (userIds.isNotEmpty) {
        final dnViaUser = await sb
            .from('death_notices')
            .select('id,name,date_of_death,dayung_unit_id,user_id')
            .isFilter('dayung_unit_id', null)
            .inFilter('user_id', userIds);
        viaUser = List<Map<String, dynamic>>.from(dnViaUser);
      }

      // Merge unique by id and sort desc by date
      final map = <int, Map<String, dynamic>>{};
      for (final m in [...direct, ...viaUser]) {
        final id = int.tryParse((m['id']).toString());
        if (id != null) map[id] = m;
      }
      final list = map.values.toList();
      list.sort(
        (a, b) => DateTime.parse(
          (b['date_of_death']).toString(),
        ).compareTo(DateTime.parse((a['date_of_death']).toString())),
      );
      return list;
    } catch (_) {
      return [];
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

      // Refresh death notices only when explicitly refreshing
      _deathNoticesFutureCached = _deathNoticesFuture();
      // Reset stats cache; it will be re-initialized lazily when notices arrive
      _paymentStatsFutureCached = null;
      _lastNoticeIds = const [];
      _lastStatsDayungId = _dayungUnitId;

      await Future.wait([
        _fetchActiveMembers(selected),
        _fetchPendingPayments(selected),
        _fetchRecentDeaths(selected),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  Future<void> _fetchPendingPayments(List<int> ids) async {
    try {
      _pendingAmount = 0;
      _pendingMembers = 0;

      if (ids.isEmpty) return;

      // Prefer RPC if available, passing only the selected dayung id(s)
      try {
        final rpc = await sb.rpc(
          'treasurer_pending_payments',
          params: {'p_dayung_ids': ids},
        );
        if (rpc is Map && rpc['total_amount'] != null) {
          _pendingAmount = double.tryParse(rpc['total_amount'].toString()) ?? 0;
          _pendingMembers = int.tryParse(rpc['member_count'].toString()) ?? 0;
          return;
        }
      } catch (_) {}

      // Fallback: query only pending payments belonging to selected dayung(s)
      final rows = await sb
          .from('payments')
          .select('amount,user_id')
          .inFilter('dayung_unit_id', ids)
          .eq('status', 'pending');

      double total = 0;
      final memberSet = <String>{};
      for (final m in List<Map<String, dynamic>>.from(rows)) {
        total += (m['amount'] is num) ? (m['amount'] as num).toDouble() : 0.0;
        final uid = (m['user_id'] ?? '').toString();
        if (uid.isNotEmpty) memberSet.add(uid);
      }
      _pendingAmount = total;
      _pendingMembers = memberSet.length;
    } catch (_) {
      _pendingAmount = 0;
      _pendingMembers = 0;
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

  Future<void> _fetchRecentDeaths(List<int> ids) async {
    try {
      if (ids.isEmpty) {
        _recentDeaths = [];
        return;
      }
      final rows = await sb
          .from('users')
          .select('full_name')
          .inFilter('dayung_unit_id', ids)
          .eq('is_deceased', true)
          .order('date_of_death', ascending: false)
          .limit(2);
      _recentDeaths = List<Map<String, dynamic>>.from(
        rows,
      ).map((e) => (e['full_name'] ?? 'Member') as String).toList();
    } catch (_) {
      _recentDeaths = [];
    }
  }

  Future<void> _triggerPaymentCollection(
    int deathNoticeId,
    int dayungUnitId,
  ) async {
    // Get active members for the dayung
    final usersRes = await sb
        .from('users')
        .select('id')
        .eq('dayung_unit_id', dayungUnitId)
        .eq('is_deceased', false);
    final members = List<Map<String, dynamic>>.from(usersRes);

    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active members to charge.')),
      );
      return;
    }

    // Fetch already generated payments for this notice/dayung
    final existingRes = await sb
        .from('payments')
        .select('user_id')
        .eq('death_notice_id', deathNoticeId)
        .eq('dayung_unit_id', dayungUnitId);
    final existingIds = {
      for (final r in List<Map<String, dynamic>>.from(existingRes))
        (r['user_id'] ?? '').toString(),
    };

    // Prepare only new rows (skip duplicates)
    final rows = <Map<String, dynamic>>[];
    for (final u in members) {
      final uid = (u['id'] ?? '').toString();
      if (uid.isEmpty || existingIds.contains(uid)) continue;
      rows.add({
        'user_id': uid,
        'amount': 1, // adjust as needed
        'status': 'pending',
        'death_notice_id': deathNoticeId,
        'dayung_unit_id': dayungUnitId,
      });
    }

    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payments already generated for all members.'),
        ),
      );
      await _fetchAll();
      return;
    }

    try {
      await sb.from('payments').insert(rows);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created ${rows.length} payment(s).')),
      );
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        // Unique conflict due to race; safe to ignore
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Some payments already existed. New ones added.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create payments: ${e.message}')),
        );
      }
    }

    await _fetchAll();
  }

  Future<Map<int, Map<String, dynamic>>> _paymentStatsByNotice(
    List<int> noticeIds,
    int dayungUnitId,
  ) async {
    if (noticeIds.isEmpty) return {};
    final rows = await sb
        .from('payments')
        .select('death_notice_id,status,amount')
        .inFilter('death_notice_id', noticeIds)
        .eq('dayung_unit_id', dayungUnitId);

    final stats = <int, Map<String, dynamic>>{};
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final id = r['death_notice_id'] as int?;
      if (id == null) continue;
      final s = (r['status'] ?? '').toString().toLowerCase();
      final amt = (r['amount'] is num) ? (r['amount'] as num).toDouble() : 0.0;
      final m = stats.putIfAbsent(
        id,
        () => {
          'paidCount': 0,
          'unpaidCount': 0,
          'paidAmount': 0.0,
          'pendingAmount': 0.0,
          'totalCount': 0,
        },
      );
      m['totalCount'] = (m['totalCount'] as int) + 1;
      if (s == 'paid') {
        m['paidCount'] = (m['paidCount'] as int) + 1;
        m['paidAmount'] = (m['paidAmount'] as double) + amt;
      } else {
        m['unpaidCount'] = (m['unpaidCount'] as int) + 1;
        m['pendingAmount'] = (m['pendingAmount'] as double) + amt;
      }
    }
    return stats;
  }

  List<Widget> get _pages => [
    _homePage(),
    const Placeholder(), // Contributions
    ClaimsPage(onNavBarVisible: (v) => setState(() => _showNavBar = v)),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wide = width > 820;

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                const Divider(height: 1, color: Color(0xFFE1E4E8)),
                _greeting(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: IndexedStack(index: _tab, children: _pages),
                  ),
                ),
              ],
            ),
          ),
          _bottomNav(wide),
        ],
      ),
    );
  }

  /* ------------------------------- UI parts ------------------------------- */

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _dayungLabel,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: kPrimaryDark,
                letterSpacing: .4,
              ),
            ),
          ),
          _iconBtn(
            icon: Icons.notifications_active_rounded,
            color: kWarn,
            tooltip: 'Notifications',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationPage()),
            ),
            badge: '1',
          ),
          const SizedBox(width: 6),
          _iconBtn(
            icon: Icons.settings_rounded,
            color: kPrimary,
            tooltip: 'Profile & Settings',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _greeting() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Maayung buntag,\nTreasurer!',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.05,
                color: kNeutralText,
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
            child: const CircleAvatar(
              radius: 28,
              backgroundColor: kPrimary,
              child: Icon(Icons.person, size: 34, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _homePage() {
    return RefreshIndicator(
      onRefresh: _fetchAll,
      edgeOffset: 68,
      child: SingleChildScrollView(
        controller: _scrollController,
        // Remove AlwaysScrollableScrollPhysics to prevent refresh at bottom
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tripleCards(),
            const SizedBox(height: 18),
            _primaryAction('Manage Fund', Icons.account_balance_wallet, () {
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
            }),
            const SizedBox(height: 12),
            _primaryAction('Paid Members', Icons.verified_user, () async {
              if (_dayungUnitId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Select a Dayung first')),
                );
                return;
              }
              await _showMembersModal(paid: true);
            }),
            const SizedBox(height: 12),
            _primaryAction('Unpaid Members', Icons.pending_actions, () async {
              if (_dayungUnitId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Select a Dayung first')),
                );
                return;
              }
              await _showMembersModal(paid: false);
            }),
            const SizedBox(height: 14),
            _collectedPanel(),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _deathNoticesFutureCached,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'Failed to load death notices.',
                      style: TextStyle(color: kDanger),
                    ),
                  );
                }
                final notices = snap.data ?? const <Map<String, dynamic>>[];
                if (notices.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'No death notices yet.',
                      style: TextStyle(
                        fontSize: 16,
                        color: kSubtleText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }

                final noticeIds = notices
                    .map<int>((e) => e['id'] as int)
                    .toList();
                final dayungId =
                    _dayungUnitId ??
                    (notices.isNotEmpty
                        ? (notices.first['dayung_unit_id'] ?? 0)
                        : 0);

                _ensureStatsFuture(noticeIds, dayungId);

                return FutureBuilder<Map<int, Map<String, dynamic>>>(
                  future: _paymentStatsByNotice(noticeIds, dayungId),
                  builder: (context, statSnap) {
                    final stats =
                        statSnap.data ?? const <int, Map<String, dynamic>>{};

                    Widget statusPill(String text, Color color) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color),
                      ),
                      child: Text(
                        text,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    );

                    Widget countChip(
                      IconData icon,
                      String label,
                      int count,
                      Color color,
                    ) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withOpacity(.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 16, color: color),
                          const SizedBox(width: 6),
                          Text(
                            '$label $count',
                            style: TextStyle(
                              color: color.withOpacity(.95),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    );

                    Widget noticeCard(Map<String, dynamic> n) {
                      final sid = n['id'] as int;
                      final dId =
                          int.tryParse(
                            (n['dayung_unit_id'] ?? dayungId ?? 0).toString(),
                          ) ??
                          0;
                      final st =
                          stats[sid] ??
                          const {
                            'paidCount': 0,
                            'unpaidCount': 0,
                            'paidAmount': 0.0,
                            'pendingAmount': 0.0,
                            'totalCount': 0,
                          };

                      final paid = (st['paidCount'] ?? 0) as int;
                      final unpaid = (st['unpaidCount'] ?? 0) as int;
                      final totalCount =
                          (st['totalCount'] ?? (paid + unpaid)) as int;
                      final paidAmt = (st['paidAmount'] ?? 0.0) as double;
                      final pendingAmt = (st['pendingAmount'] ?? 0.0) as double;

                      final completed = unpaid == 0 && totalCount > 0;
                      final progress = totalCount == 0
                          ? 0.0
                          : (paid / totalCount).clamp(0.0, 1.0);

                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade300),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(.06),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Title + status
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    (n['name'] ?? 'Death Notice').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: kNeutralText,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                ),
                                statusPill(
                                  completed ? 'Completed' : 'Collecting',
                                  completed ? Colors.teal : Colors.orange,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // Date row
                            Row(
                              children: [
                                const Icon(
                                  Icons.event,
                                  size: 16,
                                  color: kSubtleText,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  (n['date_of_death'] ?? '').toString().isEmpty
                                      ? '—'
                                      : (n['date_of_death']).toString(),
                                  style: const TextStyle(
                                    color: kSubtleText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Counts + amount
                            Row(
                              children: [
                                countChip(
                                  Icons.verified_rounded,
                                  'Paid',
                                  paid,
                                  Colors.green,
                                ),
                                const SizedBox(width: 8),
                                countChip(
                                  Icons.pending_actions_rounded,
                                  'Unpaid',
                                  unpaid,
                                  Colors.red,
                                ),
                                const Spacer(),
                                Text(
                                  '₱${paidAmt.toStringAsFixed(0)} / ₱${(paidAmt + pendingAmt).toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: kNeutralText,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Progress
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 10,
                                      backgroundColor: Colors.grey.shade200,
                                      valueColor: AlwaysStoppedAnimation(
                                        completed ? Colors.teal : Colors.indigo,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '${(progress * 100).round()}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Actions
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      _showPaymentStatusSheet(sid, dId),
                                  icon: const Icon(
                                    Icons.info_outline,
                                    size: 18,
                                  ),
                                  label: const Text('Status'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: completed
                                        ? null
                                        : () => _triggerPaymentCollection(
                                            sid,
                                            dId,
                                          ),
                                    icon: const Icon(
                                      Icons.campaign_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Collect'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kPrimary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }

                    return LayoutBuilder(
                      builder: (context, c) {
                        final isGrid = c.maxWidth >= 720;
                        final cards = notices.map(noticeCard).toList();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Death Notices',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: kPrimaryDark,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kPrimary.withOpacity(.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: kPrimary),
                                  ),
                                  child: Text(
                                    '${notices.length}',
                                    style: const TextStyle(
                                      color: kPrimaryDark,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            if (!isGrid)
                              Column(
                                children: [
                                  for (int i = 0; i < cards.length; i++) ...[
                                    cards[i],
                                    if (i != cards.length - 1)
                                      const SizedBox(height: 10),
                                  ],
                                ],
                              )
                            else
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: cards.length,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: 2.6,
                                    ),
                                itemBuilder: (_, i) => cards[i],
                              ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMembersModal({required bool paid}) async {
    final ids = await _selectedDayungIds();
    if (ids.isEmpty) return;

    // 1. Fetch all death notices for this dayung
    final notices = await sb
        .from('death_notices')
        .select('id, name, date_of_death')
        .inFilter('dayung_unit_id', ids)
        .order('date_of_death', ascending: false);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _modalBackButton(ctx, label: "Close"),
                Text(
                  paid
                      ? 'Paid Members per Deceased'
                      : 'Unpaid Members per Deceased',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kPrimaryDark,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: notices.isEmpty
                      ? const Center(child: Text('No death notices found'))
                      : ListView.separated(
                          itemCount: notices.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final n = notices[i];
                            final deceasedName = (n['name'] ?? 'Deceased')
                                .toString();
                            final date = (n['date_of_death'] ?? '').toString();
                            return ListTile(
                              leading: const Icon(
                                Icons.person_off,
                                color: kDanger,
                              ),
                              title: Text(deceasedName),
                              subtitle: Text(date),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.pop(ctx);
                                _showMembersPerDeathNotice(
                                  deathNoticeId: n['id'],
                                  deceasedName: deceasedName,
                                  paid: paid,
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMembersPerDeathNotice({
    required int deathNoticeId,
    required String deceasedName,
    required bool paid,
  }) async {
    final ids = await _selectedDayungIds();
    if (ids.isEmpty) return;

    try {
      final rows = await sb
          .from('payments')
          .select('user_id,status')
          .eq('death_notice_id', deathNoticeId)
          .eq('dayung_unit_id', ids.first)
          .eq('status', paid ? 'paid' : 'pending');

      final userIds = <String>{
        for (final r in List<Map<String, dynamic>>.from(rows))
          (r['user_id'] ?? '').toString(),
      }..removeWhere((e) => e.isEmpty);

      List<Map<String, dynamic>> users = [];
      if (userIds.isNotEmpty) {
        final res = await sb
            .from('users')
            .select('id, full_name')
            .inFilter('id', userIds.toList())
            .order('full_name', ascending: true);
        users = List<Map<String, dynamic>>.from(res);
      }

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _modalBackButton(
                    ctx,
                    onBack: () {
                      _showMembersModal(paid: paid);
                    },
                  ),
                  Text(
                    '${paid ? "Paid" : "Unpaid"} Members for',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: kPrimaryDark,
                    ),
                  ),
                  Text(
                    deceasedName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: kDanger,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: users.isEmpty
                        ? const Center(child: Text('No members found'))
                        : ListView.separated(
                            itemCount: users.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final u = users[i];
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: paid
                                      ? Colors.green.withOpacity(.12)
                                      : Colors.red.withOpacity(.12),
                                  child: Icon(
                                    paid
                                        ? Icons.verified_rounded
                                        : Icons.pending_actions_rounded,
                                    color: paid
                                        ? Colors.green[700]
                                        : Colors.red[700],
                                  ),
                                ),
                                title: Text(
                                  (u['full_name'] ?? 'Member').toString(),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  (u['id'] ?? '').toString(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: kSubtleText,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load members: $e')));
    }
  }

  Widget _modalBackButton(
    BuildContext context, {
    String label = "Back",
    VoidCallback? onBack,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pop();
              if (onBack != null) onBack();
            },
            tooltip: label,
          ),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: kPrimaryDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tripleCards() {
    final cards = <Widget>[
      _statCard(
        color: const Color(0xFFD8EEFF),
        icon: Icons.groups,
        iconColor: Colors.blue[700],
        title: "Total Active",
        bigText: _loading ? '—' : _activeMembers.toString(),
      ),
      _recentDeathsCard(),
      _statCard(
        color: const Color(0xFFFEFBDC),
        icon: Icons.account_balance_wallet,
        iconColor: Colors.orange[700],
        title: "Pending\nPayments",
        bigText: _loading ? '—' : '₱ ${_pendingAmount.toStringAsFixed(0)}',
        smallSubtitle: _loading
            ? ''
            : (_pendingMembers > 0 ? 'From $_pendingMembers' : 'All settled'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 360) {
          return Column(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i != cards.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
            const SizedBox(width: 12),
            Expanded(child: cards[2]),
          ],
        );
      },
    );
  }

  Widget _recentDeathsCard() {
    final names = _recentDeaths;
    final display = names.take(2).toList();
    final extra = names.length - display.length;

    return _statShell(
      color: const Color(0xFFFFDAF6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(FontAwesomeIcons.dove, size: 30, color: Colors.purple[400]),
          const SizedBox(height: 8),
          const Text(
            "Recent Death Notices",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              fontFamily: 'Montserrat',
              color: kNeutralText,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: names.isEmpty
                ? const Center(
                    child: Text(
                      "None",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        fontFamily: 'Montserrat',
                        color: kNeutralText,
                      ),
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final n in display)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(
                                FontAwesomeIcons.dove,
                                size: 14,
                                color: Colors.black87,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  n,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    fontFamily: 'Montserrat',
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (extra > 0)
                        Text(
                          'View All',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'OpenSans',
                            color: Colors.blue[700],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required Color color,
    required IconData icon,
    required Color? iconColor,
    required String title,
    required String bigText,
    String smallSubtitle = '',
  }) {
    return _statShell(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 32, color: iconColor),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              fontFamily: 'Montserrat',
              color: kNeutralText,
              height: 1.15,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      bigText,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 32,
                        fontFamily: 'Montserrat',
                        color: kNeutralText,
                      ),
                    ),
                  ),
                  if (smallSubtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      smallSubtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'OpenSans',
                        color: kSubtleText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statShell({required Color color, required Widget child}) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300, width: 2),
      ),
      child: child,
    );
  }

  Widget _primaryAction(String label, IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 26, color: kPrimary),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'Montserrat',
              color: kPrimaryDark,
            ),
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size.fromHeight(60),
          side: const BorderSide(color: kPrimary, width: 1.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _collectedPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F8D9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kAccent.withOpacity(.35)),
      ),
      child: Column(
        children: [
          const Text(
            'Collected from the Collectors',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'Montserrat',
              color: kNeutralText,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 160,
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CollectedFromCollectorsPage(
                      dayungUnitId: _dayungUnitId!,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'View',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomNav(bool wide) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 16,
      child: Center(
        child: IgnorePointer(
          ignoring: !_showNavBar,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: _showNavBar ? 1 : 0,
            child: Container(
              height: 86,
              margin: EdgeInsets.symmetric(horizontal: wide ? 170 : 20),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(44),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.08),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _navItem(Icons.home_rounded, "Home", 0),
                  _navItem(Icons.public, "Contributions", 1),
                  _navItem(Icons.description, "Claims", 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPaymentStatusSheet(
    int deathNoticeId,
    int dayungUnitId,
  ) async {
    final rows = await sb
        .from('payments')
        .select('user_id,status')
        .eq('death_notice_id', deathNoticeId)
        .eq('dayung_unit_id', dayungUnitId);

    final paidIds = <String>[];
    final unpaidIds = <String>[];
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final uid = (r['user_id'] ?? '').toString();
      if (uid.isEmpty) continue;
      final s = (r['status'] ?? '').toString().toLowerCase();
      if (s == 'paid') {
        paidIds.add(uid);
      } else {
        unpaidIds.add(uid);
      }
    }

    Future<List<Map<String, dynamic>>> fetchUsers(List<String> ids) async {
      if (ids.isEmpty) return [];
      final res = await sb
          .from('users')
          .select('id, full_name')
          .inFilter('id', ids);
      return List<Map<String, dynamic>>.from(res);
    }

    final paidUsers = await fetchUsers(paidIds);
    final unpaidUsers = await fetchUsers(unpaidIds);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Payment Status',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kPrimaryDark,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _memberListSection(
                          title: 'Paid',
                          color: Colors.green[700]!,
                          users: paidUsers,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _memberListSection(
                          title: 'Unpaid',
                          color: Colors.red[700]!,
                          users: unpaidUsers,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _memberListSection({
    required String title,
    required Color color,
    required List<Map<String, dynamic>> users,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Text(
              '$title (${users.length})',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontFamily: 'Montserrat',
              ),
            ),
          ),
          Expanded(
            child: users.isEmpty
                ? const Center(child: Text('None'))
                : ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (_, i) {
                      final u = users[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.person),
                        title: Text(
                          (u['full_name'] ?? 'Member').toString(),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          (u['id'] ?? '').toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: kSubtleText,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final selected = _tab == index;
    return TextButton(
      onPressed: () => setState(() => _tab = index),
      style: TextButton.styleFrom(
        foregroundColor: selected ? kPrimary : kNeutralText,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 30, color: selected ? kPrimary : kNeutralText),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontFamily: 'OpenSans',
              letterSpacing: .3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? tooltip,
    String? badge,
  }) {
    return Semantics(
      label: tooltip,
      button: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
          ),
          if (badge != null)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: kDanger,
                  borderRadius: BorderRadius.circular(10),
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
      ),
    );
  }
}
