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
  final String reference;
  final String receiptId;

  const _ReportMember({
    required this.name,
    required this.amount,
    this.proofUrl,
    required this.advanceAmount,
    this.advanceDeathCount = 0,
    this.status = '',
    this.reference = '',
    this.receiptId = 'N/A',
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
  bool _loadingAdvanceMembers = false;
  String? _advanceMembersError;

  List<_ReportMember> _cashlessMembers = [];
  bool _loadingCashlessMembers = false;
  String? _cashlessMembersError;

  List<_ReportMember> _cashMembers = [];

  List<_ReportMember> _notPaidMembers = [];

  List<_ReportMember> _advanceMembers = [];

  @override
  void initState() {
    super.initState();
    _loadCashlessMembers();
    _loadCashMembers();
    _loadNotPaidMembers();
    _loadAdvanceMembers();
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

  Future<void> _loadCashlessMembers() async {
    setState(() {
      _loadingCashlessMembers = true;
      _cashlessMembersError = null;
    });

    try {
      final assignedUserIds = await _assignedUserIdsForCurrentCollector();
      if (assignedUserIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _cashlessMembers = [];
          _loadingCashlessMembers = false;
        });
        return;
      }

      final paymentRows = await Supabase.instance.client
          .from('payments')
          .select(
            'amount, qr_id, user_id, users!payments_user_id_fkey(full_name)',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .inFilter('user_id', assignedUserIds)
          .not('qr_id', 'is', null)
          .order('created_at', ascending: false);

      final qrIds = List<Map<String, dynamic>>.from(paymentRows)
          .map((row) => (row['qr_id'] ?? '').toString())
          .where((qrId) => qrId.isNotEmpty)
          .toSet()
          .toList();
      if (qrIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _cashlessMembers = [];
          _loadingCashlessMembers = false;
        });
        return;
      }

      final qrRows = await Supabase.instance.client
          .from('gcash_qr_codes')
          .select('id, image_url, refno')
          .inFilter('id', qrIds);
      final qrById = {
        for (final row in List<Map<String, dynamic>>.from(qrRows))
          (row['id'] ?? '').toString(): row,
      };

      final members = <_ReportMember>[];
      for (final row in List<Map<String, dynamic>>.from(paymentRows)) {
        final qrId = (row['qr_id'] ?? '').toString();
        final qr = qrById[qrId];
        if (qr == null) continue;

        final user = row['users'];
        final name = user is Map
            ? (user['full_name'] ?? 'Member').toString()
            : 'Member';
        final proofUrl = (qr['image_url'] ?? '').toString();
        members.add(
          _ReportMember(
            name: name,
            amount: _toDouble(row['amount']),
            advanceAmount: 0,
            proofUrl: proofUrl.isEmpty ? null : proofUrl,
            status: (row['status'] ?? 'paid').toString().toLowerCase(),
            reference: (qr['refno'] ?? '').toString(),
            receiptId: qrId,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _cashlessMembers = members;
        _loadingCashlessMembers = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cashlessMembers = [];
        _loadingCashlessMembers = false;
        _cashlessMembersError = 'Failed to load cashless payments: $error';
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

  Future<void> _loadAdvanceMembers() async {
    setState(() {
      _loadingAdvanceMembers = true;
      _advanceMembersError = null;
    });

    try {
      final assignedUserIds = await _assignedUserIdsForCurrentCollector();
      if (assignedUserIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _advanceMembers = [];
          _loadingAdvanceMembers = false;
        });
        return;
      }

      final ruleRow = await Supabase.instance.client
          .from('dayung_rules')
          .select('exactamountforcollection')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .maybeSingle();
      final collectionAmount = _toDouble(ruleRow?['exactamountforcollection']);
      if (collectionAmount <= 0) {
        throw StateError('The collection amount is not configured.');
      }

      final rows = await Supabase.instance.client
          .from('advance_payments')
          .select(
            'user_id, amount, '
            'users!advance_payments_user_id_fkey(full_name)',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .inFilter('user_id', assignedUserIds)
          .order('created_at', ascending: false);

      final membersByUserId = <String, _ReportMember>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final userId = (row['user_id'] ?? '').toString();
        if (userId.isEmpty) continue;

        final user = row['users'];
        final name = user is Map
            ? (user['full_name'] ?? 'Member').toString()
            : 'Member';
        final existingMember = membersByUserId[userId];
        final amount = (existingMember?.amount ?? 0) + _toDouble(row['amount']);
        membersByUserId[userId] = _ReportMember(
          name: existingMember?.name ?? name,
          amount: amount,
          advanceAmount: amount,
          advanceDeathCount: (amount / collectionAmount).floor(),
        );
      }

      if (!mounted) return;
      setState(() {
        _advanceMembers = membersByUserId.values.toList();
        _loadingAdvanceMembers = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _advanceMembers = [];
        _loadingAdvanceMembers = false;
        _advanceMembersError = 'Failed to load advance payments: $error';
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
    'Paid via\nGCash',
    'Paid with\ncash',
    'Not yet\npaid',
    'Paid in\nadvance',
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
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 680) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _mobileTabSelector(constraints.maxWidth),
                              const SizedBox(height: 16),
                              if (_isActiveTabLoading)
                                const Padding(
                                  padding: EdgeInsets.all(32),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else if (_activeTabError != null)
                                _mobileErrorCard(_activeTabError!)
                              else ...[
                                _mobileSummary(members, total),
                                const SizedBox(height: 12),
                                if (members.isEmpty)
                                  _mobileEmptyState()
                                else
                                  ...members.map(_mobileMemberCard),
                                const SizedBox(height: 12),
                                _totalCard(total),
                                const SizedBox(height: 12),
                                _uploadButton(compact: true),
                              ],
                            ],
                          );
                        }

                        return SingleChildScrollView(
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
                                      left: BorderSide(
                                        color: Color(0xFF111827),
                                      ),
                                      right: BorderSide(
                                        color: Color(0xFF111827),
                                      ),
                                      bottom: BorderSide(
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                  ),
                                  child: _isActiveTabLoading
                                      ? const Padding(
                                          padding: EdgeInsets.all(24),
                                          child: Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                        )
                                      : _activeTabError != null
                                      ? Padding(
                                          padding: const EdgeInsets.all(24),
                                          child: Text(_activeTabError!),
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
                        );
                      },
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

  bool get _isActiveTabLoading {
    switch (_activeTab) {
      case 0:
        return _loadingCashlessMembers;
      case 1:
        return _loadingCashMembers;
      case 2:
        return _loadingNotPaidMembers;
      default:
        return _loadingAdvanceMembers;
    }
  }

  String? get _activeTabError {
    switch (_activeTab) {
      case 0:
        return _cashlessMembersError;
      case 1:
        return _cashMembersError;
      case 2:
        return _notPaidMembersError;
      default:
        return _advanceMembersError;
    }
  }

  Widget _mobileTabSelector(double width) {
    final columns = width < 360 ? 1 : 2;
    final gap = 10.0;
    final itemWidth = (width - gap * (columns - 1)) / columns;

    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: List.generate(_tabLabels.length, (index) {
        final selected = _activeTab == index;
        return SizedBox(
          width: itemWidth,
          child: Semantics(
            button: true,
            selected: selected,
            label: _tabLabels[index].replaceAll('\n', ' '),
            child: Material(
              color: selected ? const Color(0xFF0D47A1) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () => setState(() => _activeTab = index),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF0D47A1)
                          : const Color(0xFFD1D5DB),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _tabLabels[index].replaceAll('\n', ' '),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : const Color(0xFF111827),
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _mobileSummary(List<_ReportMember> members, double total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups_rounded, color: Color(0xFF0D47A1), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${members.length} ${members.length == 1 ? 'member' : 'members'}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Total reported amount',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4B5563),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '₱${total.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0D47A1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileMemberCard(_ReportMember member) {
    final isUnpaid = _activeTab == 2;
    final statusLabel = switch (_activeTab) {
      0 => 'Paid via GCash',
      1 => 'Paid with cash',
      2 => 'Not yet paid',
      _ => 'Paid in advance',
    };
    final statusColor = isUnpaid
        ? const Color(0xFFB91C1C)
        : const Color(0xFF166534);
    final statusBackground = isUnpaid
        ? const Color(0xFFFEE2E2)
        : const Color(0xFFDCFCE7);

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  member.name,
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: statusBackground,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
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
                    'Amount',
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
                      '₱${member.amount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 21,
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
          if (_activeTab == 0) ...[
            _mobileDetailRow('Payment method', 'GCash'),
            if (member.reference.isNotEmpty) ...[
              const SizedBox(height: 10),
              _mobileDetailRow('Reference number', member.reference),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showReceiptDetails(member),
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('View GCash transaction'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0D47A1),
                  minimumSize: const Size.fromHeight(52),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ] else if (_activeTab == 1) ...[
            _mobileDetailRow('Payment method', 'Cash'),
          ] else if (_activeTab == 2) ...[
            _mobileDetailRow(
              'Unpaid deceased payments',
              '${(member.amount / 100).round()}',
            ),
          ] else if (_activeTab == 3) ...[
            _mobileDetailRow(
              'Deceased payments covered',
              '${member.advanceDeathCount}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _mobileDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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

  Widget _totalCard(double total) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFE2F4DF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF9CCB94)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total amount',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '₱${total.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_activeTab == 2) ...[
            const Divider(height: 22),
            _mobileDetailRow(
              'Unpaid deceased payments',
              '${_unpaidDeceasedCount(_notPaidMembers)}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _mobileEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Column(
        children: [
          Icon(Icons.inbox_outlined, size: 40, color: Color(0xFF6B7280)),
          SizedBox(height: 10),
          Text(
            'No members to show',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileErrorCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 15,
          color: Color(0xFF991B1B),
          fontWeight: FontWeight.w600,
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
                  onTap: () => _showReceiptDetails(member),
                  child: _DataCell(
                    '(View Transaction)',
                    align: TextAlign.center,
                    color: const Color(0xFF111827),
                    isLink: true,
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

  Widget _uploadButton({bool compact = false}) {
    return Container(
      width: compact ? double.infinity : 460,
      height: compact ? 56 : 110,
      color: const Color(0xFFB9D9B4),
      alignment: Alignment.center,
      child: Text(
        'Upload report',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: compact ? 18 : 32,
          fontWeight: FontWeight.w800,
          color: Color(0xFF111827),
          height: 1.05,
        ),
      ),
    );
  }

  Future<void> _showReceiptDetails(_ReportMember member) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final hasProof = member.proofUrl != null;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Receipt Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1F2937),
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  member.name,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF1F2937),
                                    fontFamily: 'Montserrat',
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFF59E0B,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'GCash',
                                  style: TextStyle(
                                    color: Color(0xFFF59E0B),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    fontFamily: 'Montserrat',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'PHP ${member.amount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFF59E0B),
                              fontFamily: 'Montserrat',
                            ),
                          ),
                          const SizedBox(height: 16),
                          _receiptDetailRow('Member', member.name),
                          _receiptDetailRow(
                            'Amount',
                            'PHP ${member.amount.toStringAsFixed(2)}',
                          ),
                          _receiptDetailRow('Source', 'GCash'),
                          _receiptDetailRow(
                            'Status',
                            member.status.isEmpty ? 'paid' : member.status,
                          ),
                          _receiptDetailRow(
                            'Reference',
                            member.reference.isEmpty ? 'N/A' : member.reference,
                          ),
                        ],
                      ),
                    ),
                    if (hasProof) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _viewTransaction(member.proofUrl!),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Preview GCash proof'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _receiptDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF4B5563),
                fontFamily: 'Montserrat',
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
                fontFamily: 'OpenSans',
              ),
            ),
          ),
        ],
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
