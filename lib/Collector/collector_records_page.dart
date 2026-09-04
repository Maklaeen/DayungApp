import 'package:capstone_app/shared/treasurer_report_header.dart';
import 'package:flutter/material.dart';

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
  final List<_DeathNotice> _notices = const [
    _DeathNotice(id: 'd1', name: 'Deceased\n1', amountPerMember: 200),
    _DeathNotice(id: 'd2', name: 'Deceased\n2', amountPerMember: 200),
  ];
  late final List<_MemberRecord> _members;
  final Set<String> _paidNoticeOverrides = <String>{};
  final Map<String, String> _paymentMethodOverrides = <String, String>{};
  bool _uploaded = false;

  @override
  void initState() {
    super.initState();
    _members = const [
      _MemberRecord(
        memberId: 'm1',
        memberName: 'Member 1',
        amountPaid: 300,
        amountNeeded: 200,
        paymentMethod: 'Cash',
        advanceAmount: 100,
        advanceDeathCount: 1,
        noticePaid: {'d1': true, 'd2': true},
      ),
      _MemberRecord(
        memberId: 'm2',
        memberName: 'Member 2',
        amountPaid: 100,
        amountNeeded: 200,
        paymentMethod: 'Cash',
        advanceAmount: 0,
        advanceDeathCount: 0,
        noticePaid: {'d1': true, 'd2': true},
      ),
      _MemberRecord(
        memberId: 'm3',
        memberName: 'Member 3',
        amountPaid: 200,
        amountNeeded: 200,
        paymentMethod: 'GCash',
        advanceAmount: 0,
        advanceDeathCount: 0,
        noticePaid: {'d1': true, 'd2': true},
      ),
      _MemberRecord(
        memberId: 'm4',
        memberName: 'Member 4',
        amountPaid: 100,
        amountNeeded: 200,
        paymentMethod: 'GCash',
        advanceAmount: 0,
        advanceDeathCount: 0,
        noticePaid: {'d1': true, 'd2': true},
      ),
      _MemberRecord(
        memberId: 'm5',
        memberName: 'Member 5',
        amountPaid: 500,
        amountNeeded: 200,
        paymentMethod: 'GCash',
        advanceAmount: 300,
        advanceDeathCount: 3,
        noticePaid: {'d1': true, 'd2': true},
      ),
      _MemberRecord(
        memberId: 'm6',
        memberName: 'Member 6',
        amountPaid: 0,
        amountNeeded: 200,
        paymentMethod: 'N/Y',
        advanceAmount: 0,
        advanceDeathCount: 0,
        noticePaid: {'d1': false, 'd2': false},
      ),
    ];
  }

  double get _totalCash => _members
      .where((m) => m.paymentMethod == 'Cash')
      .fold(0.0, (s, m) => s + m.amountPaid);

  double get _totalCashless => _members
      .where((m) => m.paymentMethod == 'GCash')
      .fold(0.0, (s, m) => s + m.amountPaid);

  double get _totalAdvance => _members.fold(0.0, (s, m) => s + m.advanceAmount);

  double get _totalNeeded => _members.fold(0.0, (s, m) => s + m.amountNeeded);

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
              _headerCell('Deceased 1'),
              _headerCell('Deceased 2'),
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
          ..._members.asMap().entries.map((entry) {
            final index = entry.key;
            final m = entry.value;
            final isFirst = index == 0;

            return TableRow(
              decoration: const BoxDecoration(color: Colors.white),
              children: [
                _bodyCell(m.memberName),
                _checkCell(
                  memberId: m.memberId,
                  noticeId: 'd1',
                  checked: _isNoticePaid(m, 'd1'),
                ),
                _checkCell(
                  memberId: m.memberId,
                  noticeId: 'd2',
                  checked: _isNoticePaid(m, 'd2'),
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
          }).toList(),
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
