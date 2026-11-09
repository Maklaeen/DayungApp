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
      .where(
        (member) =>
            (_paymentMethodOverrides[member.memberId] ??
                member.paymentMethod) ==
            'Cash',
      )
      .fold(0.0, (sum, member) => sum + member.amountPaid);

  double get _totalCashless => _records
      .where(
        (member) =>
            (_paymentMethodOverrides[member.memberId] ??
                member.paymentMethod) ==
            'GCash',
      )
      .fold(0.0, (sum, member) => sum + member.amountPaid);

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
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontFamily: 'OpenSans',
                            fontSize: 15,
                            color: Color(0xFF991B1B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 840) {
                            return _buildMobileRecords();
                          }
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: _buildTable(),
                          );
                        },
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

  Widget _buildMobileRecords() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Collection summary',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth < 330 ? 1 : 2;
                  const spacing = 10.0;
                  final itemWidth =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      _mobileTotalCard(
                        width: itemWidth,
                        label: 'Cash received',
                        value: _totalCash,
                        color: const Color(0xFF059669),
                      ),
                      _mobileTotalCard(
                        width: itemWidth,
                        label: 'GCash received',
                        value: _totalCashless,
                        color: const Color(0xFF2563EB),
                      ),
                      _mobileTotalCard(
                        width: itemWidth,
                        label: 'Advance received',
                        value: _totalAdvance,
                        color: const Color(0xFFB45309),
                      ),
                      _mobileTotalCard(
                        width: itemWidth,
                        label: 'Total needed',
                        value: _totalNeeded,
                        color: const Color(0xFF4B5563),
                      ),
                      _mobileTotalCard(
                        width: itemWidth,
                        label: 'Total without advance',
                        value: _overallWithoutAdvance,
                        color: const Color(0xFF0D47A1),
                        secondaryValue: _totalNeeded,
                      ),
                      _mobileTotalCard(
                        width: itemWidth,
                        label: 'Total with advance',
                        value: _overallWithAdvance,
                        color: const Color(0xFF0D47A1),
                        secondaryValue: _totalNeeded,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Member records',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            Text(
              '${_records.length} ${_records.length == 1 ? 'member' : 'members'}',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF4B5563),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_records.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: const Text(
              'No member records available.',
              style: TextStyle(color: Color(0xFF4B5563), fontSize: 15),
            ),
          )
        else
          ..._records.map(_mobileMemberRecordCard),
        const SizedBox(height: 4),
        _mobileUploadButton(),
      ],
    );
  }

  Widget _mobileTotalCard({
    required double width,
    required String label,
    required double value,
    required Color color,
    double? secondaryValue,
  }) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE3EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4B5563),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              secondaryValue == null
                  ? '₱${value.toStringAsFixed(0)}'
                  : '₱${value.toStringAsFixed(0)} / ₱${secondaryValue.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileMemberRecordCard(_MemberRecord member) {
    final method =
        _paymentMethodOverrides[member.memberId] ?? member.paymentMethod;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE3EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            member.memberName,
            style: const TextStyle(
              fontSize: 18,
              height: 1.25,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F7FC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Amount paid / needed',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '₱${member.amountPaid.toStringAsFixed(0)} / ₱${member.amountNeeded.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0D47A1),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Payment status by notice',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          ..._notices.map((notice) {
            final checked = _isNoticePaid(member, notice.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                button: true,
                toggled: checked,
                label:
                    '${notice.name.replaceAll('\n', ' ')}: ${checked ? 'paid' : 'unpaid'}',
                child: Material(
                  color: checked
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => _toggleNoticePaid(
                      memberId: member.memberId,
                      noticeId: notice.id,
                      checked: checked,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              notice.name.replaceAll('\n', ' '),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF374151),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            checked
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                            size: 22,
                            color: checked
                                ? const Color(0xFF15803D)
                                : const Color(0xFFB91C1C),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            checked ? 'Paid' : 'Unpaid',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: checked
                                  ? const Color(0xFF166534)
                                  : const Color(0xFF991B1B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          const Text(
            'Payment method',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: method,
            isExpanded: true,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'Cash', child: Text('Cash')),
              DropdownMenuItem(value: 'GCash', child: Text('GCash')),
              DropdownMenuItem(value: 'N/Y', child: Text('Not yet paid')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _paymentMethodOverrides[member.memberId] = value);
            },
          ),
          const SizedBox(height: 14),
          _mobileRecordDetail(
            'Advance payment',
            '₱${member.advanceAmount.toStringAsFixed(0)}',
          ),
        ],
      ),
    );
  }

  void _toggleNoticePaid({
    required String memberId,
    required String noticeId,
    required bool checked,
  }) {
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
  }

  Widget _mobileRecordDetail(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4B5563),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
        ),
      ],
    );
  }

  Widget _mobileUploadButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () {
          setState(() => _uploaded = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Collector record uploaded.')),
          );
        },
        icon: Icon(
          _uploaded ? Icons.check_circle_rounded : Icons.upload_rounded,
        ),
        label: Text(_uploaded ? 'Record uploaded' : 'Upload record'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF15803D),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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
      onTap: () => _toggleNoticePaid(
        memberId: memberId,
        noticeId: noticeId,
        checked: checked,
      ),
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
