import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/Treasurer/treasurer_payment_page.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:capstone_app/widgets/record_data_table.dart';
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
    required String recordCount,
    required Color color,
    required IconData icon,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: dayungSurface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dayungBorder(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  recordCount,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCards() {
    final cards = [
      _summaryCard(
        title: 'My paid',
        value: '₱${_myTotal.toStringAsFixed(2)}',
        recordCount: '$_myCount records',
        color: kPrimary,
        icon: Icons.person_rounded,
      ),
      _summaryCard(
        title: 'Unit paid',
        value: '₱${_paidTotal.toStringAsFixed(2)}',
        recordCount: '$_paidCount records',
        color: kPaid,
        icon: Icons.account_balance_wallet_rounded,
      ),
      _summaryCard(
        title: 'Pending',
        value: '₱${_pendingTotal.toStringAsFixed(2)}',
        recordCount: '$_pendingCount records',
        color: kPending,
        icon: Icons.pending_actions_rounded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                if (index > 0) const SizedBox(width: 12),
                Expanded(child: cards[index]),
              ],
            ],
          );
        }

        return Column(
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              if (index > 0) const SizedBox(height: 10),
              cards[index],
            ],
          ],
        );
      },
    );
  }

  Widget _sectionHeader(String title) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: colors.onSurface,
          fontFamily: 'Montserrat',
        ),
      ),
    );
  }

  Widget _emptyState(String title) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: dayungSectionCardDecoration(context, radius: 16),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 32, color: colors.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  RecordDataTable _paymentTable(
    List<Map<String, dynamic>> payments, {
    required bool mine,
  }) {
    final colors = Theme.of(context).colorScheme;
    return RecordDataTable(
      minWidth: 760,
      columnSpacing: 18,
      horizontalMargin: 16,
      headingRowHeight: 50,
      dataRowMinHeight: 56,
      dataRowMaxHeight: 72,
      showCheckboxColumn: false,
      headingTextStyle: TextStyle(
        color: colors.onSurface,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        fontFamily: 'Montserrat',
      ),
      dataTextStyle: TextStyle(
        color: colors.onSurface,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        fontFamily: 'OpenSans',
      ),
      columns: const [
        DataColumn(label: Text('Amount')),
        DataColumn(label: Text('Member')),
        DataColumn(label: Text('Deceased')),
        DataColumn(label: Text('Date')),
        DataColumn(label: Text('Status')),
      ],
      rows: payments.map((row) {
        final status = (row['status'] ?? '').toString();
        final statusColor = _statusColor(status);
        final payerId = (row['user_id'] ?? '').toString();
        final payerName = mine ? _fullName : (_userNames[payerId] ?? 'Member');
        final noticeId = int.tryParse('${row['death_notice_id'] ?? ''}');
        final notice = noticeId != null ? _deathNotices[noticeId] : null;
        final deceasedName = (notice?['name'] ?? 'No deceased linked')
            .toString();
        final displayStatus = status.isEmpty
            ? 'Unknown'
            : status[0].toUpperCase() + status.substring(1).toLowerCase();

        return DataRow(
          cells: [
            DataCell(
              Text(
                '₱${_amountOf(row).toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                ),
              ),
            ),
            DataCell(Text(mine ? 'You ($_fullName)' : payerName)),
            DataCell(Text(deceasedName)),
            DataCell(Text(_dateOf(row))),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColor.withValues(alpha: 0.2)),
                ),
                child: Text(
                  displayStatus,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _paymentShortcutCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kPrimaryDark, kPrimary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Make a contribution',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
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
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: const Text('Pay now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: kPrimaryDark,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dayungPageBackground(context),
      appBar: AppBar(
        backgroundColor: dayungPageBackground(context),
        elevation: 0,
        title: Text(
          'Contributions',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh contributions',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            style: IconButton.styleFrom(
              fixedSize: const Size(52, 52),
              backgroundColor: dayungSurface(context),
              foregroundColor: Theme.of(context).colorScheme.primary,
              side: BorderSide(color: dayungBorder(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const DayungPageSkeleton(
              layout: DayungSkeletonLayout.list,
              itemCount: 3,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _paymentShortcutCard(),
                  const SizedBox(height: 14),
                  _summaryCards(),
                  const SizedBox(height: 20),
                  _sectionHeader('My contributions'),
                  if (_myContributions.isEmpty)
                    _emptyState('No personal records yet')
                  else
                    _paymentTable(_myContributions, mine: true),
                  const SizedBox(height: 20),
                  _sectionHeader('Other members'),
                  if (_otherContributions.isEmpty)
                    _emptyState('No other member records yet')
                  else
                    _paymentTable(_otherContributions, mine: false),
                ],
              ),
            ),
    );
  }
}
