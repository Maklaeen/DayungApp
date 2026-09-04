import 'package:capstone_app/shared/treasurer_report_header.dart';
import 'package:flutter/material.dart';

class _ReportMember {
  final String name;
  final double amount;
  final String? proofUrl;
  final double advanceAmount;
  final int advanceDeathCount;

  const _ReportMember({
    required this.name,
    required this.amount,
    this.proofUrl,
    this.advanceAmount = 0,
    this.advanceDeathCount = 0,
  });
}

class CollectorOverallReportsPage extends StatefulWidget {
  final int dayungUnitId;

  const CollectorOverallReportsPage({super.key, required this.dayungUnitId});

  @override
  State<CollectorOverallReportsPage> createState() =>
      _CollectorOverallReportsPageState();
}

class _CollectorOverallReportsPageState
    extends State<CollectorOverallReportsPage> {
  int _activeTab = 3;

  final _cashlessMembers = const [
    _ReportMember(
      name: 'Member 1',
      amount: 200,
      proofUrl: 'https://placeholder.com/r1.jpg',
    ),
    _ReportMember(
      name: 'Member 2',
      amount: 100,
      proofUrl: 'https://placeholder.com/r2.jpg',
    ),
    _ReportMember(
      name: 'Member 3',
      amount: 500,
      proofUrl: 'https://placeholder.com/r3.jpg',
    ),
  ];

  final _cashMembers = const [
    _ReportMember(name: 'Member 1', amount: 300),
    _ReportMember(name: 'Member 2', amount: 100),
  ];

  final _notPaidMembers = const [_ReportMember(name: 'Member 1', amount: 200)];

  final _advanceMembers = const [
    _ReportMember(name: 'Member 1', amount: 100, advanceDeathCount: 1),
    _ReportMember(name: 'Member 2', amount: 300, advanceDeathCount: 3),
  ];

  static const _tabLabels = [
    'Who pay\ncashless',
    'Who pay\ncash',
    'Who did\nnot pay',
    'Who paid\nin\nadvance',
  ];

  List<_ReportMember> get _currentMembers {
    switch (_activeTab) {
      case 0:
        return _cashlessMembers;
      case 1:
        return _cashMembers;
      case 2:
        return _notPaidMembers;
      default:
        return _advanceMembers;
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = _currentMembers;
    final total = members.fold<double>(0, (sum, m) => sum + m.amount);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            TreasurerReportHeader(title: 'Collector Overall Reports'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: 1000,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _tabHeaderRow(),
                            Container(
                              decoration: const BoxDecoration(
                                border: Border(
                                  left: BorderSide(color: Color(0xFF111827)),
                                  right: BorderSide(color: Color(0xFF111827)),
                                  bottom: BorderSide(color: Color(0xFF111827)),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _contentHeader(),
                                  ..._rowsForActiveTab(members),
                                  _totalRow(total),
                                  _uploadButton(),
                                ],
                              ),
                            ),
                          ],
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
    );
  }

  Widget _tabHeaderRow() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Color(0xFF111827)),
          top: BorderSide(color: Color(0xFF111827)),
          right: BorderSide(color: Color(0xFF111827)),
        ),
      ),
      child: Row(
        children: List.generate(_tabLabels.length, (index) {
          final selected = _activeTab == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = index),
              child: Container(
                height: 160,
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFB9D9B4) : Colors.white,
                  border: Border(
                    right: index < _tabLabels.length - 1
                        ? const BorderSide(color: Color(0xFF111827))
                        : BorderSide.none,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _tabLabels[index],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                    height: 1.05,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _contentHeader() {
    if (_activeTab == 0) {
      return Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFF111827)),
            bottom: BorderSide(color: Color(0xFF111827)),
          ),
        ),
        child: Row(
          children: const [
            Expanded(flex: 3, child: _HeaderCell('List of members')),
            Expanded(flex: 3, child: _HeaderCell('Transaction uploaded')),
            Expanded(flex: 2, child: _HeaderCell('amount')),
          ],
        ),
      );
    }

    if (_activeTab == 1 || _activeTab == 2) {
      return Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFF111827)),
            bottom: BorderSide(color: Color(0xFF111827)),
          ),
        ),
        child: Row(
          children: const [
            Expanded(
              flex: 5,
              child: _HeaderCell('List of members who pay cash'),
            ),
            Expanded(flex: 2, child: _HeaderCell('Amount')),
          ],
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFF111827)),
          bottom: BorderSide(color: Color(0xFF111827)),
        ),
      ),
      child: Row(
        children: const [
          Expanded(
            flex: 4,
            child: _HeaderCell('List of members who paid in advance'),
          ),
          Expanded(flex: 2, child: _HeaderCell('Amount')),
          Expanded(flex: 3, child: _HeaderCell('Total deaths paid in advance')),
        ],
      ),
    );
  }

  List<Widget> _rowsForActiveTab(List<_ReportMember> members) {
    if (_activeTab == 0) {
      return members.map((member) {
        return Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF111827))),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: _DataCell(member.name, align: TextAlign.left),
              ),
              Expanded(
                flex: 3,
                child: GestureDetector(
                  onTap: () => member.proofUrl != null
                      ? _viewTransaction(member.proofUrl!)
                      : null,
                  child: _DataCell(
                    member.proofUrl != null ? '(View Transaction)' : '',
                    align: TextAlign.center,
                    color: const Color(0xFF111827),
                    isLink: member.proofUrl != null,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: _DataCell(
                  member.amount.toStringAsFixed(0),
                  align: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      }).toList();
    }

    if (_activeTab == 1 || _activeTab == 2) {
      return members.map((member) {
        return Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF111827))),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: _DataCell(member.name, align: TextAlign.left),
              ),
              Expanded(
                flex: 2,
                child: _DataCell(
                  member.amount.toStringAsFixed(0),
                  align: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      }).toList();
    }

    return members.map((member) {
      return Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF111827))),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: _DataCell(member.name, align: TextAlign.left),
            ),
            Expanded(
              flex: 2,
              child: _DataCell(
                member.amount.toStringAsFixed(0),
                align: TextAlign.center,
              ),
            ),
            Expanded(
              flex: 3,
              child: _DataCell(
                member.advanceDeathCount > 0
                    ? member.advanceDeathCount.toString()
                    : '',
                align: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _totalRow(double total) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFF111827)),
          bottom: BorderSide(color: Color(0xFF111827)),
        ),
        color: Color(0xFFB9D9B4),
      ),
      child: Row(
        children: [
          Expanded(
            flex: _activeTab == 0
                ? 3
                : (_activeTab == 1 || _activeTab == 2 ? 5 : 4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              child: Text(
                'Total amount:',
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ),
          Expanded(
            flex: _activeTab == 0
                ? 2
                : (_activeTab == 1 || _activeTab == 2 ? 2 : 2),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              child: Text(
                total.toStringAsFixed(0),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ),
          if (_activeTab == 2)
            const Expanded(flex: 0, child: SizedBox())
          else if (_activeTab == 0)
            const Expanded(flex: 0, child: SizedBox())
          else
            const Expanded(flex: 3, child: SizedBox()),
        ],
      ),
    );
  }

  Widget _uploadButton() {
    return Container(
      width: 460,
      height: 110,
      color: const Color(0xFFB9D9B4),
      alignment: Alignment.center,
      child: const Text(
        'Upload report',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: Color(0xFF111827),
          height: 1.05,
        ),
      ),
    );
  }

  void _viewTransaction(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;

  const _HeaderCell(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFF111827))),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: Color(0xFF111827),
          height: 1.1,
        ),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;
  final TextAlign align;
  final Color color;
  final bool isLink;

  const _DataCell(
    this.text, {
    super.key,
    this.align = TextAlign.left,
    this.color = const Color(0xFF111827),
    this.isLink = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: color,
          decoration: isLink ? TextDecoration.underline : null,
          height: 1.1,
        ),
      ),
    );
  }
}
