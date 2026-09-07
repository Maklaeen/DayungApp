import 'package:capstone_app/shared/treasurer_report_header.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _DeathNotice {
  final String id;
  final String name;
  final double amountPerMember;

  const _DeathNotice({
    required this.id,
    required this.name,
    required this.amountPerMember,
  });
}

class _MemberRecord {
  final String memberId;
  final String memberName;
  final double amountPaid;
  final double amountNeeded;
  final String paymentMethod;
  final double advanceAmount;
  final int advanceDeathCount;
  final Map<String, bool> noticePaid;

  const _MemberRecord({
    required this.memberId,
    required this.memberName,
    required this.amountPaid,
    required this.amountNeeded,
    required this.paymentMethod,
    required this.advanceAmount,
    required this.advanceDeathCount,
    required this.noticePaid,
  });

  String get displayAmount =>
      '${amountPaid.toStringAsFixed(0)}/${amountNeeded.toStringAsFixed(0)}';
}

class CollectorRecordsPage extends StatefulWidget {
  final int dayungUnitId;

  const CollectorRecordsPage({super.key, required this.dayungUnitId});

  @override
  State<CollectorRecordsPage> createState() => _CollectorRecordsPageState();
}

class _CollectorRecordsPageState extends State<CollectorRecordsPage> {
  List<_DeathNotice> _notices = const [];
  List<_MemberRecord> _records = const [];
  final Set<String> _paidNoticeOverrides = <String>{};
  final Map<String, String> _paymentMethodOverrides = <String, String>{};
  bool _uploaded = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    try {
      final client = Supabase.instance.client;
      final currentUserId = client.auth.currentUser?.id;
      if (currentUserId == null) {
        throw StateError('No signed-in collector found.');
      }

      final collectorRows = List<Map<String, dynamic>>.from(
        await client
            .from('dayung_collectors')
            .select('collectors_id')
            .eq('dayung_unit_id', widget.dayungUnitId)
            .eq('user_id', currentUserId)
            .limit(1),
      );
      if (collectorRows.isEmpty) {
        throw StateError('This user is not assigned as a collector.');
      }
      final collectorId = collectorRows.first['collectors_id'];

      final applicationRows = List<Map<String, dynamic>>.from(
        await client
            .from('applications')
            .select('user_id')
            .eq('dayung_unit_id', widget.dayungUnitId)
            .eq('status', 'approved')
            .eq('assigned_collector', collectorId),
      );
      final memberIds = applicationRows
          .map((row) => (row['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final paymentRows = memberIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await client
                  .from('payments')
                  .select(
                    'user_id, userdeceased, amount, status, type, is_claimed',
                  )
                  .eq('dayung_unit_id', widget.dayungUnitId)
                  .inFilter('user_id', memberIds),
            );
      final advanceRows = memberIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await client
                  .from('advance_payments')
                  .select('user_id, amount')
                  .inFilter('user_id', memberIds),
            );
      final advanceAmountsByUser = <String, double>{};
      for (final row in advanceRows) {
        final userId = (row['user_id'] ?? '').toString();
        if (userId.isEmpty) continue;
        advanceAmountsByUser[userId] =
            (advanceAmountsByUser[userId] ?? 0) +
            (double.tryParse('${row['amount']}') ?? 0);
      }
      paymentRows.removeWhere((row) {
        final type = (row['type'] ?? '').toString().toLowerCase();
        return type == 'deceased_payment' && row['is_claimed'] == true;
      });
      final deceasedIds = paymentRows
          .where((row) {
            final type = (row['type'] ?? '').toString().toLowerCase();
            return type == 'deceased_payment' &&
                (row['is_claimed'] == null || row['is_claimed'] == false);
          })
          .map((row) => (row['userdeceased'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final claimRows = deceasedIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await client
                  .from('claims')
                  .select('user_id, amount')
                  .eq('dayung_unit_id', widget.dayungUnitId)
                  .inFilter('user_id', deceasedIds),
            );
      final claimAmountsByDeceased = <String, double>{};
      for (final row in claimRows) {
        final deceasedId = (row['user_id'] ?? '').toString();
        claimAmountsByDeceased[deceasedId] =
            (claimAmountsByDeceased[deceasedId] ?? 0) +
            (double.tryParse('${row['amount']}') ?? 0);
      }
      final deceasedUsers = deceasedIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await client
                  .from('users')
                  .select('id, full_name')
                  .inFilter('id', deceasedIds),
            );
      final deceasedNames = {
        for (final row in deceasedUsers)
          (row['id'] ?? '').toString(): (row['full_name'] ?? 'Deceased')
              .toString(),
      };
      final notices = <_DeathNotice>[
        for (final deceasedId in deceasedIds.take(2))
          _DeathNotice(
            id: deceasedId,
            name: deceasedNames[deceasedId] ?? 'Deceased',
            amountPerMember: claimAmountsByDeceased[deceasedId] ?? 0,
          ),
      ];
      while (notices.length < 2) {
        notices.add(
          _DeathNotice(
            id: 'missing-${notices.length}',
            name: 'Deceased\n${notices.length + 1}',
            amountPerMember: 0,
          ),
        );
      }

      final memberUsers = memberIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await client
                  .from('users')
                  .select('id, full_name')
                  .inFilter('id', memberIds),
            );
      final memberNames = {
        for (final row in memberUsers)
          (row['id'] ?? '').toString(): (row['full_name'] ?? 'Member')
              .toString(),
      };
      final records = memberIds.map((memberId) {
        final memberPayments = paymentRows.where(
          (row) => (row['user_id'] ?? '').toString() == memberId,
        );
        final noticePaid = {
          for (final notice in notices)
            notice.id: memberPayments.any(
              (row) =>
                  (row['userdeceased'] ?? '').toString() == notice.id &&
                  (row['status'] ?? '').toString().toLowerCase() == 'paid',
            ),
        };
        return _MemberRecord(
          memberId: memberId,
          memberName: memberNames[memberId] ?? 'Member',
          amountPaid: memberPayments.fold<double>(0, (sum, row) {
            final status = (row['status'] ?? '').toString().toLowerCase();
            final type = (row['type'] ?? '').toString().toLowerCase();
            if (status != 'paid' || type != 'deceased_payment') return sum;
            return sum + (double.tryParse('${row['amount']}') ?? 0);
          }),
          amountNeeded: notices.fold(
            0,
            (sum, notice) => sum + notice.amountPerMember,
          ),
          paymentMethod: 'N/Y',
          advanceAmount: advanceAmountsByUser[memberId] ?? 0,
          advanceDeathCount: 0,
          noticePaid: noticePaid,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _notices = notices;
        _records = records;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  double get _totalCash => _records
      .where((m) => m.paymentMethod == 'Cash')
      .fold(0.0, (s, m) => s + m.amountPaid);

  double get _totalCashless => _records
      .where((m) => m.paymentMethod == 'GCash')
      .fold(0.0, (s, m) => s + m.amountPaid);

  double get _totalAdvance => _records.fold(0.0, (s, m) => s + m.advanceAmount);

  double get _totalNeeded => _records.fold(0.0, (s, m) => s + m.amountNeeded);

  double get _overallWithoutAdvance => _totalCash + _totalCashless;
  double get _overallWithAdvance => _overallWithoutAdvance + _totalAdvance;

  static const double _wMember = 150;
  static const double _wNotice = 90;
  static const double _wAmount = 120;
  static const double _wMethod = 120;
  static const double _wAdvance = 120;
  static const double _wTotal = 120;
  static const double _wOverall = 140;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            const TreasurerReportHeader(title: 'Collector Records'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('COLLECTORS RECORDS'),
                    const SizedBox(height: 10),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (_error != null)
                      Text(
                        _error!,
                        style: const TextStyle(
                          fontFamily: 'OpenSans',
                          color: Color(0xFFB91C1C),
                        ),
                      )
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _buildTable(),
                      ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable() {
    final tableWidth =
        _wMember +
        (_wNotice * _notices.length) +
        _wAmount +
        _wMethod +
        _wAdvance +
        (_wTotal * 3) +
        (_wOverall * 2);

    return Container(
      width: tableWidth,
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Color(0xFF111827)),
          top: BorderSide(color: Color(0xFF111827)),
          right: BorderSide(color: Color(0xFF111827)),
          bottom: BorderSide(color: Color(0xFF111827)),
        ),
      ),
      child: Table(
        border: TableBorder.all(
          color: const Color(0xFF111827),
          style: BorderStyle.solid,
        ),
        columnWidths: {
          0: FixedColumnWidth(_wMember),
          1: FixedColumnWidth(_wNotice),
          2: FixedColumnWidth(_wNotice),
          3: FixedColumnWidth(_wAmount),
          4: FixedColumnWidth(_wMethod),
          5: FixedColumnWidth(_wAdvance),
          6: FixedColumnWidth(_wTotal),
          7: FixedColumnWidth(_wTotal),
          8: FixedColumnWidth(_wTotal),
          9: FixedColumnWidth(_wOverall),
          10: FixedColumnWidth(_wOverall),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFEAF7EA)),
            children: [
              _headerCell('Member of Collector 1'),
              _headerCell(_notices[0].name),
              _headerCell(_notices[1].name),
              _headerCell('Amount paid / Amount needed'),
              _headerCell('Payment Method'),
              _headerCell('Advance Payment'),
              _headerCell('Total Cash received'),
              _headerCell('Total Advance payment'),
              _headerCell('Total Cashless received'),
              _headerCell('Overall total without advance received'),
              _headerCell('Overall total with advance received'),
            ],
          ),
          ..._records.asMap().entries.map((entry) {
            final index = entry.key;
            final m = entry.value;
            final isFirst = index == 0;

            return TableRow(
              decoration: const BoxDecoration(color: Colors.white),
              children: [
                _bodyCell(m.memberName),
                _checkCell(
                  memberId: m.memberId,
                  noticeId: _notices[0].id,
                  checked: _isNoticePaid(m, _notices[0].id),
                ),
                _checkCell(
                  memberId: m.memberId,
                  noticeId: _notices[1].id,
                  checked: _isNoticePaid(m, _notices[1].id),
                ),
                _bodyCell(m.displayAmount),
                _paymentMethodCell(m),
                _bodyCell(
                  m.advanceAmount > 0
                      ? m.advanceAmount.toStringAsFixed(0)
                      : '0',
                ),
                if (isFirst)
                  _totalCell(_totalCash.toStringAsFixed(0))
                else
                  const SizedBox.shrink(),
                if (isFirst)
                  _totalCell(_totalAdvance.toStringAsFixed(0))
                else
                  const SizedBox.shrink(),
                if (isFirst)
                  _totalCell(_totalCashless.toStringAsFixed(0))
                else
                  const SizedBox.shrink(),
                if (isFirst)
                  _totalCell(
                    '${_overallWithoutAdvance.toStringAsFixed(0)}/\n${_totalNeeded.toStringAsFixed(0)}',
                  )
                else
                  const SizedBox.shrink(),
                if (isFirst)
                  _totalCell(
                    '${_overallWithAdvance.toStringAsFixed(0)}/\n${_totalNeeded.toStringAsFixed(0)}',
                  )
                else
                  const SizedBox.shrink(),
              ],
            );
          }),
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFD9F0D4)),
            children: [
              _greenButtonCell('UPLOAD\nRECORD'),
              const SizedBox(),
              const SizedBox(),
              const SizedBox(),
              const SizedBox(),
              const SizedBox(),
              const SizedBox(),
              const SizedBox(),
              const SizedBox(),
              const SizedBox(),
              const SizedBox(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String text) {
    return Container(
      height: 120,
      padding: const EdgeInsets.all(8),
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'Montserrat',
          fontWeight: FontWeight.w800,
          fontSize: 12,
          color: Color(0xFF111827),
          height: 1.1,
        ),
      ),
    );
  }

  Widget _bodyCell(String text) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        textAlign: TextAlign.left,
        style: const TextStyle(
          fontFamily: 'OpenSans',
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: Color(0xFF111827),
          height: 1.1,
        ),
      ),
    );
  }

  bool _isNoticePaid(_MemberRecord member, String noticeId) {
    final key = '${member.memberId}:$noticeId';
    return _paidNoticeOverrides.contains(key) ||
        (!_paidNoticeOverrides.any(
              (entry) => entry.startsWith('${member.memberId}:'),
            ) &&
            (member.noticePaid[noticeId] ?? false));
  }

  Widget _checkCell({
    required String memberId,
    required String noticeId,
    required bool checked,
  }) {
    return GestureDetector(
      onTap: () {
        final key = '$memberId:$noticeId';
        setState(() {
          if (checked) {
            _paidNoticeOverrides.remove(key);
            _paidNoticeOverrides.add('$memberId:!$noticeId');
          } else {
            _paidNoticeOverrides.remove('$memberId:!$noticeId');
            _paidNoticeOverrides.add(key);
          }
        });
      },
      child: Container(
        height: 58,
        alignment: Alignment.center,
        color: checked ? const Color(0xFFD9F0D4) : Colors.white,
        child: checked
            ? const Icon(Icons.check, color: Color(0xFF111827), size: 22)
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _paymentMethodCell(_MemberRecord member) {
    final method =
        _paymentMethodOverrides[member.memberId] ?? member.paymentMethod;
    return Container(
      height: 58,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: method,
          isExpanded: true,
          alignment: Alignment.center,
          items: const [
            DropdownMenuItem(
              value: 'Cash',
              child: Center(child: Text('CASH')),
            ),
            DropdownMenuItem(
              value: 'GCash',
              child: Center(child: Text('GCASH')),
            ),
            DropdownMenuItem(
              value: 'N/Y',
              child: Center(child: Text('N/Y')),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _paymentMethodOverrides[member.memberId] = value);
          },
        ),
      ),
    );
  }

  Widget _totalCell(String text) {
    return Container(
      height: 58,
      padding: const EdgeInsets.all(6),
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'OpenSans',
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: Color(0xFF111827),
          height: 1.1,
        ),
      ),
    );
  }

  Widget _greenButtonCell(String text) {
    return GestureDetector(
      onTap: () {
        setState(() => _uploaded = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Collector record uploaded.')),
        );
      },
      child: Container(
        height: 80,
        alignment: Alignment.center,
        color: const Color(0xFF9FD69D),
        child: Text(
          _uploaded ? 'RECORDED' : text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: Color(0xFF111827),
            height: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Montserrat',
        fontWeight: FontWeight.w800,
        fontSize: 22,
        color: Color(0xFF111827),
      ),
    );
  }
}
