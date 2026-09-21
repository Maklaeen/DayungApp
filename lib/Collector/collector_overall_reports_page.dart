import 'package:capstone_app/shared/treasurer_report_header.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _ReportMember {
  final String name;
  final double amount;
  final String? proofUrl;
  final double advanceAmount;
  final int advanceDeathCount;
  final String status;

  const _ReportMember({
    required this.name,
    required this.amount,
    this.proofUrl,
    required this.advanceAmount,
    this.advanceDeathCount = 0,
    this.status = '',
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
  bool _loadingCashMembers = false;
  String? _cashMembersError;
  bool _loadingNotPaidMembers = false;
  String? _notPaidMembersError;

  final _cashlessMembers = const [
    _ReportMember(
      name: 'Member 1',
      amount: 200,
      advanceAmount: 0,
      proofUrl: 'https://placeholder.com/r1.jpg',
    ),
    _ReportMember(
      name: 'Member 2',
      amount: 100,
      advanceAmount: 0,
      proofUrl: 'https://placeholder.com/r2.jpg',
    ),
    _ReportMember(
      name: 'Member 3',
      amount: 500,
      advanceAmount: 0,
      proofUrl: 'https://placeholder.com/r3.jpg',
    ),
  ];

  List<_ReportMember> _cashMembers = [];

  List<_ReportMember> _notPaidMembers = [];

  final _advanceMembers = const [
    _ReportMember(
      name: 'Member 1',
      amount: 100,
      advanceAmount: 100,
      advanceDeathCount: 1,
    ),
    _ReportMember(
      name: 'Member 2',
      amount: 300,
      advanceAmount: 300,
      advanceDeathCount: 3,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadCashMembers();
    _loadNotPaidMembers();
  }

  Future<List<String>> _assignedUserIdsForCurrentCollector() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) return [];

    final collectorRows = await Supabase.instance.client
        .from('dayung_collectors')
        .select('collectors_id')
        .eq('dayung_unit_id', widget.dayungUnitId)
        .eq('user_id', currentUserId)
        .limit(1);
    if (collectorRows.isEmpty) return [];

    final applicationRows = await Supabase.instance.client
        .from('applications')
        .select('user_id')
        .eq('dayung_unit_id', widget.dayungUnitId)
        .eq('assigned_collector', collectorRows.first['collectors_id'])
        .eq('status', 'approved');
    return applicationRows
        .map((row) => (row['user_id'] ?? '').toString())
        .where((userId) => userId.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> _loadCashMembers() async {
    setState(() {
      _loadingCashMembers = true;
      _cashMembersError = null;
    });

    try {
      final assignedUserIds = await _assignedUserIdsForCurrentCollector();

      if (assignedUserIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _cashMembers = [];
          _loadingCashMembers = false;
        });
        return;
      }

      final rows = await Supabase.instance.client
          .from('payments')
          .select(
            'amount, status, userdeceased, is_claimed, user_id, '
            'users!payments_user_id_fkey(full_name)',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('type', 'deceased_payment')
          .eq('status', 'paid')
          .inFilter('user_id', assignedUserIds)
          .order('created_at', ascending: false);

      final members = <_ReportMember>[];
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        if (_isTrueFlag(row['is_claimed'])) continue;

        final user = row['users'];
        final name = user is Map
            ? (user['full_name'] ?? 'Member').toString()
            : 'Member';
        members.add(
          _ReportMember(
            name: name,
            amount: _toDouble(row['amount']),
            advanceAmount: 0,
            status: (row['status'] ?? '').toString().toLowerCase(),
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _cashMembers = members;
        _loadingCashMembers = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cashMembers = [];
        _loadingCashMembers = false;
        _cashMembersError = 'Failed to load cash payments: $error';
      });
    }
  }

  Future<void> _loadNotPaidMembers() async {
    setState(() {
      _loadingNotPaidMembers = true;
      _notPaidMembersError = null;
    });

    try {
      final assignedUserIds = await _assignedUserIdsForCurrentCollector();
      if (assignedUserIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _notPaidMembers = [];
          _loadingNotPaidMembers = false;
        });
        return;
      }

      final rows = await Supabase.instance.client
          .from('payments')
          .select(
            'amount, status, user_id, is_claimed, '
            'users!payments_user_id_fkey(full_name)',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('type', 'deceased_payment')
          .eq('status', 'unpaid')
          .inFilter('user_id', assignedUserIds)
          .order('created_at', ascending: false);

      final membersByUserId = <String, _ReportMember>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        if (row['is_claimed'] != null && _isTrueFlag(row['is_claimed'])) {
          continue;
        }

        final userId = (row['user_id'] ?? '').toString();
        if (userId.isEmpty) continue;
        final user = row['users'];
        final name = user is Map
            ? (user['full_name'] ?? 'Member').toString()
            : 'Member';
        final existingMember = membersByUserId[userId];
        membersByUserId[userId] = _ReportMember(
          name: existingMember?.name ?? name,
          amount: (existingMember?.amount ?? 0) + _toDouble(row['amount']),
          advanceAmount: 0,
          status: 'unpaid',
        );
      }
      final members = membersByUserId.values.toList();

      if (!mounted) return;
      setState(() {
        _notPaidMembers = members;
        _loadingNotPaidMembers = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _notPaidMembers = [];
        _loadingNotPaidMembers = false;
        _notPaidMembersError = 'Failed to load unpaid payments: $error';
      });
    }
  }

  static bool _isTrueFlag(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = (value ?? '').toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

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

  double _currentTotal(List<_ReportMember> members) {
    if (_activeTab == 1) {
      return members
          .where((member) => member.status == 'paid')
          .fold<double>(0, (sum, member) => sum + member.amount);
    }
    return members.fold<double>(0, (sum, member) => sum + member.amount);
  }

  int _unpaidDeceasedCount(List<_ReportMember> members) {
    return members.fold<int>(
      0,
      (count, member) => count + (member.amount / 100).round(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = _currentMembers;
    final total = _currentTotal(members);

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
                              child:
                                  _activeTab == 1 && _loadingCashMembers ||
                                      _activeTab == 2 && _loadingNotPaidMembers
                                  ? const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  : _activeTab == 1 &&
                                            _cashMembersError != null ||
                                        _activeTab == 2 &&
                                            _notPaidMembersError != null
                                  ? Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Text(
                                        _activeTab == 1
                                            ? _cashMembersError!
                                            : _notPaidMembersError!,
                                      ),
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
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

    if (_activeTab == 1) {
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

    if (_activeTab == 2) {
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
              child: _HeaderCell('List of members who did not pay'),
            ),
            Expanded(flex: 2, child: _HeaderCell('Amount')),
            Expanded(
              flex: 3,
              child: _HeaderCell('Number of deceased that unpaid'),
            ),
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

    if (_activeTab == 1) {
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

    if (_activeTab == 2) {
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
              Expanded(
                flex: 3,
                child: _DataCell(
                  (member.amount / 100).round().toString(),
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
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 12,
                ),
                child: Text(
                  _unpaidDeceasedCount(_notPaidMembers).toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
            )
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

  const _HeaderCell(this.text);

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
