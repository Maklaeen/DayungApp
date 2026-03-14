import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/Treasurer/treasurer_payment_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kPrimary = Color(0xFF0D47A1);
const kPrimaryDark = Color(0xFF083366);
const kPaid = Color(0xFF2E7D32);
const kPending = Color(0xFFF57C00);
const kDanger = Color(0xFFC62828);
const kCardRadius = 20.0;

class TreasurerContributionsPage extends StatefulWidget {
  final int dayungUnitId;
  const TreasurerContributionsPage({super.key, required this.dayungUnitId});

  @override
  State<TreasurerContributionsPage> createState() =>
      _TreasurerContributionsPageState();
}

class _TreasurerContributionsPageState
    extends State<TreasurerContributionsPage> {
  final sb = Supabase.instance.client;
  bool _loading = true;
  double _paidTotal = 0;
  double _pendingTotal = 0;
  int _paidCount = 0;
  int _pendingCount = 0;
  List<Map<String, dynamic>> _recent = [];
  List<Map<String, dynamic>> _myContributions = [];
  List<Map<String, dynamic>> _otherContributions = [];
  double _myTotal = 0;
  int _myCount = 0;
  String _fullName = 'Treasurer';
  final Map<String, String> _userNames = {};
  final Map<int, Map<String, dynamic>> _deathNotices = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = sb.auth.currentUser?.id;
      if (uid == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _paidTotal = 0;
          _pendingTotal = 0;
          _paidCount = 0;
          _pendingCount = 0;
          _recent = [];
          _myContributions = [];
          _otherContributions = [];
          _myTotal = 0;
          _myCount = 0;
        });
        return;
      }

      final res = await sb
          .from('payments')
          .select(
            'id, user_id, amount, status, created_at, paid_at, dayung_unit_id, death_notice_id, collected_by',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .order('created_at', ascending: false)
          .limit(200);

      final rows = List<Map<String, dynamic>>.from(res);
      final userIds = rows
          .map((r) => (r['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      userIds.add(uid);

      final usersRes = userIds.isEmpty
          ? <dynamic>[]
          : await sb
                .from('users')
                .select('id, full_name')
                .inFilter('id', userIds);
      _userNames
        ..clear()
        ..addEntries(
          List<Map<String, dynamic>>.from(usersRes).map(
            (row) => MapEntry(
              (row['id'] ?? '').toString(),
              (row['full_name'] ?? 'Member').toString(),
            ),
          ),
        );

      _fullName = _userNames[uid] ?? 'Treasurer';

      final noticeIds = rows
          .map((r) => int.tryParse('${r['death_notice_id'] ?? ''}'))
          .whereType<int>()
          .toSet()
          .toList();
      final noticesRes = noticeIds.isEmpty
          ? <dynamic>[]
          : await sb
                .from('death_notices')
                .select('id, name, date_of_death')
                .inFilter('id', noticeIds);
      _deathNotices
        ..clear()
        ..addEntries(
          List<Map<String, dynamic>>.from(noticesRes)
              .map((row) => MapEntry(int.tryParse('${row['id']}') ?? 0, row))
              .where((entry) => entry.key > 0),
        );

      double paidTotal = 0, pendingTotal = 0;
      int paidCount = 0, pendingCount = 0;
      double myTotal = 0;
      final myRows = <Map<String, dynamic>>[];
      final otherRows = <Map<String, dynamic>>[];

      for (final r in rows) {
        final amt = r['amount'] is num
            ? (r['amount'] as num).toDouble()
            : double.tryParse('${r['amount']}') ?? 0.0;
        final st = (r['status'] ?? '').toString().toLowerCase();
        if (st == 'paid') {
          paidTotal += amt;
          paidCount++;
        } else {
          pendingTotal += amt;
          pendingCount++;
        }

        if ((r['user_id'] ?? '').toString() == uid) {
          myRows.add(r);
          if (st == 'paid') {
            myTotal += amt;
          }
        } else {
          otherRows.add(r);
        }
      }

      setState(() {
        _paidTotal = paidTotal;
        _pendingTotal = pendingTotal;
        _paidCount = paidCount;
        _pendingCount = pendingCount;
        _recent = rows.take(20).toList();
        _myContributions = myRows;
        _otherContributions = otherRows;
        _myTotal = myTotal;
        _myCount = myRows
            .where(
              (r) => (r['status'] ?? '').toString().toLowerCase() == 'paid',
            )
            .length;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _paidTotal = 0;
        _pendingTotal = 0;
        _paidCount = 0;
        _pendingCount = 0;
        _recent = [];
        _myContributions = [];
        _otherContributions = [];
        _myTotal = 0;
        _myCount = 0;
        _loading = false;
      });
    }
  }

  double _amountOf(Map<String, dynamic> row) {
    final amount = row['amount'];
    return amount is num
        ? amount.toDouble()
        : double.tryParse('$amount') ?? 0.0;
  }

  String _dateOf(Map<String, dynamic> row) {
    final raw = (row['paid_at'] ?? row['created_at'] ?? '').toString();
    return raw.isEmpty ? 'No date' : raw.split('T').first;
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return kPaid;
      case 'pending':
        return kPending;
      default:
        return kDanger;
    }
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: kText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: kSubText,
            ),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: kSubText)),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: kText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 14,
              color: kSubText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: kText,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 14, color: kSubText),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _paymentCard(Map<String, dynamic> row, {required bool mine}) {
    final amount = _amountOf(row);
    final status = (row['status'] ?? '').toString();
    final statusColor = _statusColor(status);
    final payerId = (row['user_id'] ?? '').toString();
    final payerName = mine ? _fullName : (_userNames[payerId] ?? 'Member');
    final noticeId = int.tryParse('${row['death_notice_id'] ?? ''}');
    final notice = noticeId != null ? _deathNotices[noticeId] : null;
    final deceasedName = (notice?['name'] ?? 'No deceased linked').toString();
    final dateLabel = _dateOf(row);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '₱${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: kPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    status.isEmpty
                        ? 'Unknown'
                        : status[0].toUpperCase() +
                              status.substring(1).toLowerCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              mine ? 'Your contribution' : 'Member: $payerName',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'For deceased: $deceasedName',
              style: const TextStyle(
                fontSize: 14,
                color: kSubText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Text(
                  dateLabel,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentShortcutCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kPrimaryDark, kPrimary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.payments_rounded, color: Colors.white, size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Need to settle your own contribution?',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Open your payment page to review pending records and choose cash or GCash.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      TreasurerPaymentPage(dayungUnitId: widget.dayungUnitId),
                ),
              ).then((_) => _load());
            },
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Open Payment Page'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: kPrimaryDark,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        title: const Text(
          'Contributions',
          style: TextStyle(color: kText, fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const DayungPageSkeleton(
              layout: DayungSkeletonLayout.dashboard,
              itemCount: 4,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  const Text(
                    'Contribution Overview',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: kPrimaryDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // const Text(
                  //   'Your payments are separated from other members so you can review both clearly.',
                  //   style: TextStyle(
                  //     fontSize: 14,
                  //     color: kSubText,
                  //     fontWeight: FontWeight.w600,
                  //   ),
                  // ),
                  const SizedBox(height: 16),
                  _paymentShortcutCard(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _summaryCard(
                          title: 'My Paid Total',
                          value: '₱${_myTotal.toStringAsFixed(2)}',
                          subtitle:
                              '$_myCount paid contribution${_myCount == 1 ? '' : 's'}',
                          color: kPrimary,
                          icon: Icons.person_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _summaryCard(
                          title: 'Unit Paid Total',
                          value: '₱${_paidTotal.toStringAsFixed(2)}',
                          subtitle: '$_paidCount paid records',
                          color: kPaid,
                          icon: Icons.account_balance_wallet_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _summaryCard(
                          title: 'Pending Total',
                          value: '₱${_pendingTotal.toStringAsFixed(2)}',
                          subtitle: '$_pendingCount pending records',
                          color: kPending,
                          icon: Icons.pending_actions_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _summaryCard(
                          title: 'Recent Records',
                          value: '${_recent.length}',
                          subtitle: 'Latest contribution entries',
                          color: kPrimaryDark,
                          icon: Icons.history_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionHeader(
                    'My Contributions',
                    'Payments made under your own account.',
                  ),
                  if (_myContributions.isEmpty)
                    _emptyState(
                      'No personal contributions yet',
                      'Your paid and pending contributions will appear here.',
                    )
                  else
                    ..._myContributions.map(
                      (row) => _paymentCard(row, mine: true),
                    ),
                  const SizedBox(height: 20),
                  _sectionHeader(
                    'Other Members Contributions',
                    'All other contribution records inside this dayung unit.',
                  ),
                  if (_otherContributions.isEmpty)
                    _emptyState(
                      'No other member contributions yet',
                      'Other members will appear here once contribution records exist.',
                    )
                  else
                    ..._otherContributions.map(
                      (row) => _paymentCard(row, mine: false),
                    ),
                ],
              ),
            ),
    );
  }
}
