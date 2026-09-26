import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:capstone_app/shared/treasurer_report_header.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class CollectorSummary {
  final String id;
  final String name;
  final int dayungUnitId;
  const CollectorSummary({
    required this.id,
    required this.name,
    required this.dayungUnitId,
  });
}

class _CollectorMemberRow {
  final String memberName;
  final String paymentMethod;
  final double amountPaid;
  final double amountNeeded;
  final double advanceAmount;
  final String? proofUrl;
  final String dropStatus;

  const _CollectorMemberRow({
    required this.memberName,
    required this.paymentMethod,
    required this.amountPaid,
    required this.amountNeeded,
    this.advanceAmount = 0,
    this.proofUrl,
    required this.dropStatus,
  });

  String get suggestedDropStatus {
    final coveredAmount = amountPaid + advanceAmount;
    if (coveredAmount <= 0) return 'YES';
    if (coveredAmount < amountNeeded) return 'WARNING';
    return 'NO';
  }
}

// ---------------------------------------------------------------------------
// Collector list page
// ---------------------------------------------------------------------------

class TreasurerCollectorListPage extends StatefulWidget {
  final int dayungUnitId;
  const TreasurerCollectorListPage({super.key, required this.dayungUnitId});

  @override
  State<TreasurerCollectorListPage> createState() =>
      _TreasurerCollectorListPageState();
}

class _TreasurerCollectorListPageState
    extends State<TreasurerCollectorListPage> {
  final _sb = Supabase.instance.client;
  List<CollectorSummary> _collectors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCollectors();
  }

  Future<void> _loadCollectors() async {
    try {
      setState(() {
        _loading = true;
      });

      final collectorRows = List<Map<String, dynamic>>.from(
        await _sb
            .from('dayung_collectors')
            .select('collectors_id, user_id')
            .eq('dayung_unit_id', widget.dayungUnitId),
      );

      final userIds = <String>{};
      for (final row in collectorRows) {
        final userId = (row['user_id'] ?? '').toString();
        if (userId.isNotEmpty) userIds.add(userId);
      }

      final users = userIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _sb
                  .from('users')
                  .select('id, full_name')
                  .inFilter('id', userIds.toList()),
            );

      final userMap = {for (final u in users) (u['id'] ?? '').toString(): u};

      _collectors = collectorRows
          .map((row) {
            final userId = (row['user_id'] ?? '').toString();
            final collectorId = (row['collectors_id'] ?? '').toString();
            final user = userMap[userId] ?? <String, dynamic>{};
            final name = (user['full_name'] ?? 'Collector').toString();
            return CollectorSummary(
              id: collectorId,
              name: name,
              dayungUnitId: widget.dayungUnitId,
            );
          })
          .where((c) => c.id.isNotEmpty)
          .toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load collectors: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            const TreasurerReportHeader(title: 'Collectors'),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _collectors.isEmpty
                  ? const Center(child: Text('No collectors found.'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                      itemCount: _collectors.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final c = _collectors[i];
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    TreasurerCollectorDetailPage(collector: c),
                              ),
                            ),
                            child: Ink(
                              decoration: dayungSectionCardDecoration(context),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: kPrimary.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.person_rounded,
                                        color: kPrimary,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        c.name,
                                        style: TextStyle(
                                          fontFamily: 'Montserrat',
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          color: dayungTextColor(context),
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 16,
                                      color: kPrimary,
                                    ),
                                  ],
                                ),
                              ),
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
  }
}

// ---------------------------------------------------------------------------
// Collector detail page — tabs as table header
// ---------------------------------------------------------------------------

class TreasurerCollectorDetailPage extends StatefulWidget {
  final CollectorSummary collector;
  const TreasurerCollectorDetailPage({super.key, required this.collector});

  @override
  State<TreasurerCollectorDetailPage> createState() =>
      _TreasurerCollectorDetailPageState();
}

class _TreasurerCollectorDetailPageState
    extends State<TreasurerCollectorDetailPage> {
  int _activeTab = 0; // 0=Cash 1=NotPaid 2=Cashless 3=Totals
  final Set<int> _recordedTabs = <int>{};
  bool _loading = true;

  List<_CollectorMemberRow> _allRows = [];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      final applicationRows = List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('applications')
            .select('user_id')
            .eq('dayung_unit_id', widget.collector.dayungUnitId)
            .eq('status', 'approved')
            .eq('assigned_collector', widget.collector.id),
      );
      final memberIds = applicationRows
          .map((row) => (row['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();

      if (memberIds.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final userRows = List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('users')
            .select('id, full_name')
            .inFilter('id', memberIds.toList()),
      );
      final names = {
        for (final row in userRows)
          (row['id'] ?? '').toString(): (row['full_name'] ?? 'Member')
              .toString(),
      };

      final paymentRows = List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('payments')
            .select('user_id, amount, status, type, paid_at, created_at')
            .eq('dayung_unit_id', widget.collector.dayungUnitId)
            .eq('type', 'deceased_payment')
            .eq('status', 'paid')
            .inFilter('user_id', memberIds.toList()),
      );

      final unclaimedDeceasedRows = List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('payments')
            .select('userdeceased, is_claimed')
            .eq('dayung_unit_id', widget.collector.dayungUnitId)
            .eq('type', 'deceased_payment'),
      );
      final unclaimedDeceasedIds = unclaimedDeceasedRows
          .where(
            (row) => row['is_claimed'] == null || row['is_claimed'] == false,
          )
          .map((row) => (row['userdeceased'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      final claimRows = unclaimedDeceasedIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await Supabase.instance.client
                  .from('claims')
                  .select('user_id, amount')
                  .eq('dayung_unit_id', widget.collector.dayungUnitId)
                  .inFilter('user_id', unclaimedDeceasedIds.toList()),
            );
      final amountNeeded = claimRows.fold<double>(
        0,
        (total, row) => total + _toDouble(row['amount']),
      );

      List<Map<String, dynamic>> gcashRows = [];
      try {
        gcashRows = List<Map<String, dynamic>>.from(
          await Supabase.instance.client
              .from('gcash_payments')
              .select('user_id, uploaded_by, amount, status, created_at')
              .eq('dayung_unit_id', widget.collector.dayungUnitId)
              .inFilter('user_id', memberIds.toList()),
        );
      } catch (_) {
        // Older projects may not have the optional GCash table.
      }

      final advanceRows = List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('advance_payments')
            .select('user_id, amount')
            .inFilter('user_id', memberIds.toList()),
      );
      final cashTotals = <String, double>{};
      final gcashTotals = <String, double>{};
      final advanceTotals = <String, double>{};
      for (final row in paymentRows) {
        final userId = (row['user_id'] ?? '').toString();
        cashTotals[userId] =
            (cashTotals[userId] ?? 0) + _toDouble(row['amount']);
      }
      for (final row in gcashRows) {
        final userId = (row['user_id'] ?? row['uploaded_by'] ?? '').toString();
        if ((row['status'] ?? 'paid').toString().toLowerCase() != 'paid') {
          continue;
        }
        gcashTotals[userId] =
            (gcashTotals[userId] ?? 0) + _toDouble(row['amount']);
      }
      for (final row in advanceRows) {
        final userId = (row['user_id'] ?? '').toString();
        advanceTotals[userId] =
            (advanceTotals[userId] ?? 0) + _toDouble(row['amount']);
      }

      final rows = memberIds.map((userId) {
        final cash = cashTotals[userId] ?? 0;
        final gcash = gcashTotals[userId] ?? 0;
        final method = cash > 0
            ? 'Cash'
            : gcash > 0
            ? 'GCash'
            : 'N/Y';
        return _CollectorMemberRow(
          memberName: names[userId] ?? 'Member',
          paymentMethod: method,
          amountPaid: cash + gcash,
          amountNeeded: amountNeeded,
          advanceAmount: advanceTotals[userId] ?? 0,
          dropStatus: '',
        );
      }).toList()..sort((a, b) => a.memberName.compareTo(b.memberName));

      if (mounted) {
        setState(() {
          _allRows = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load assigned members: $e')),
        );
      }
    }
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  List<_CollectorMemberRow> get _cashRows =>
      _allRows.where((r) => r.paymentMethod == 'Cash').toList();
  List<_CollectorMemberRow> get _notPaidRows =>
      _allRows.where((r) => r.paymentMethod == 'N/Y').toList();
  List<_CollectorMemberRow> get _cashlessRows =>
      _allRows.where((r) => r.paymentMethod == 'GCash').toList();

  double get _totalCash => _cashRows.fold(0, (s, r) => s + r.amountPaid);
  double get _totalCashless =>
      _cashlessRows.fold(0, (s, r) => s + r.amountPaid);
  double get _totalAdvance => _allRows.fold(0, (s, r) => s + r.advanceAmount);
  double get _totalNeeded => _allRows.fold(0, (s, r) => s + r.amountNeeded);
  double get _overallWithout => _totalCash + _totalCashless;
  double get _overallWith => _overallWithout + _totalAdvance;

  static const _tabLabels = [
    'COLLECTOR\n1 RECORD\nCASH',
    'RECORD NI\nCOLLECTOR\n1 SA WALA\nNAKA BAYAD',
    'COLLECTOR\n1 RECORD\nCASHLESS',
    'COLLECTOR\n1 TOTAL\nAMOUNTS\nCOLLECTED',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            TreasurerReportHeader(title: widget.collector.name),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: _sectionLabel(widget.collector.name),
                          ),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: 820,
                              child: _tableWithTabs(),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tableWithTabs() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFF111827)),
          left: BorderSide(color: Color(0xFF111827)),
          right: BorderSide(color: Color(0xFF111827)),
          bottom: BorderSide(color: Color(0xFF111827)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_tabHeaderRow(), _tabContent()],
      ),
    );
  }

  Widget _tabHeaderRow() {
    return Row(
      children: List.generate(_tabLabels.length, (i) {
        final selected = _activeTab == i;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _activeTab = i),
            child: Container(
              height: 123,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFD1FAE5)
                    : const Color(0xFFF9FAFB),
                border: Border(
                  left: i > 0
                      ? const BorderSide(color: Color(0xFF9CA3AF))
                      : BorderSide.none,
                  bottom: BorderSide(
                    color: selected ? kPrimary : const Color(0xFF9CA3AF),
                    width: selected ? 2 : 1,
                  ),
                ),
              ),
              child: Text(
                _tabLabels[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  color: selected ? kPrimary : const Color(0xFF6B7280),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _tabContent() {
    switch (_activeTab) {
      case 0:
        return _recordTab(_cashRows, showProof: false);
      case 1:
        return _recordTab(_notPaidRows, showProof: false);
      case 2:
        return _recordTab(_cashlessRows, showProof: true);
      default:
        return _totalsTab();
    }
  }

  // ---------------------------------------------------------------------------
  // Record tab (Cash / Not Paid / Cashless)
  // ---------------------------------------------------------------------------

  Widget _recordTab(List<_CollectorMemberRow> rows, {required bool showProof}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Column header
        Container(
          color: const Color(0xFFF3F4F6),
          child: Row(
            children: [
              Expanded(flex: 3, child: _hCell('MEMBERS')),
              Expanded(flex: 2, child: _hCell('PAYMENT\nMETHOD')),
              if (showProof)
                Expanded(flex: 2, child: _hCell('PROOF OF\nTRANSACTION')),
              Expanded(flex: 2, child: _hCell('AMOUNT')),
              Expanded(flex: 2, child: _hCell('ADVANCE')),
              Expanded(flex: 2, child: _hCell('SUGGEST\nTO DROP')),
            ],
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No records.',
              style: TextStyle(
                fontFamily: 'OpenSans',
                color: dayungSubtextColor(context),
              ),
            ),
          )
        else
          ...rows.asMap().entries.map((e) {
            final r = e.value;
            return Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                children: [
                  Expanded(flex: 3, child: _dCell(r.memberName)),
                  Expanded(
                    flex: 2,
                    child: _dCell(
                      r.paymentMethod,
                      color: _methodColor(r.paymentMethod),
                    ),
                  ),
                  if (showProof)
                    Expanded(
                      flex: 2,
                      child: r.proofUrl != null
                          ? _viewTxCell(r.proofUrl!)
                          : _dCell('—'),
                    ),
                  Expanded(
                    flex: 2,
                    child: _dCell(
                      '${r.amountPaid.toStringAsFixed(0)}/${r.amountNeeded.toStringAsFixed(0)}',
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _dCell(
                      r.advanceAmount > 0
                          ? r.advanceAmount.toStringAsFixed(0)
                          : '0',
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      child: _dropChip(r.suggestedDropStatus),
                    ),
                  ),
                ],
              ),
            );
          }),
        _uploadToRecordButton(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Totals tab
  // ---------------------------------------------------------------------------

  Widget _totalsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: const Color(0xFFF3F4F6),
          child: Row(
            children: [
              Expanded(flex: 2, child: _hCell('TOTAL SA\nCASH\nRECEIVED')),
              Expanded(flex: 2, child: _hCell('TOTAL SA\nCASHLESS\nRECEIVED')),
              Expanded(flex: 2, child: _hCell('TOTAL SA\nADVANCE\nPAYMENT')),
              Expanded(
                flex: 3,
                child: _hCell('OVERALL\nTOTAL\nWITHOUT\nADVANCE\nRECEIVED'),
              ),
              Expanded(
                flex: 3,
                child: _hCell('OVERALL\nTOTAL\nWITH\nADVANCE\nRECEIVED'),
              ),
            ],
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: _dCell(
                  _totalCash.toStringAsFixed(0),
                  bold: true,
                  color: kPrimary,
                ),
              ),
              Expanded(
                flex: 2,
                child: _dCell(
                  _totalCashless.toStringAsFixed(0),
                  bold: true,
                  color: kPrimary,
                ),
              ),
              Expanded(
                flex: 2,
                child: _dCell(
                  _totalAdvance.toStringAsFixed(0),
                  bold: true,
                  color: const Color(0xFFF59E0B),
                ),
              ),
              Expanded(
                flex: 3,
                child: _dCell(
                  '${_overallWithout.toStringAsFixed(0)}/${_totalNeeded.toStringAsFixed(0)}',
                  bold: true,
                  color: kPrimary,
                ),
              ),
              Expanded(
                flex: 3,
                child: _dCell(
                  '${_overallWith.toStringAsFixed(0)}/${_totalNeeded.toStringAsFixed(0)}',
                  bold: true,
                  color: kPrimary,
                ),
              ),
            ],
          ),
        ),
        _uploadToRecordButton(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  Widget _hCell(String text) {
    return Container(
      constraints: const BoxConstraints(minHeight: 100),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFF111827))),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'Montserrat',
          fontWeight: FontWeight.w800,
          fontSize: 10,
          color: Color(0xFF111827),
          height: 1.15,
        ),
      ),
    );
  }

  Widget _dCell(String text, {bool bold = false, Color? color}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFF111827))),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'OpenSans',
          fontSize: 11,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          color: color ?? dayungTextColor(context),
        ),
      ),
    );
  }

  Widget _viewTxCell(String url) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: GestureDetector(
        onTap: () => _viewTransaction(url),
        child: const Text(
          '(View Transaction)',
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w700,
            fontSize: 10,
            color: Color(0xFF2563EB),
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }

  Widget _dropChip(String status) {
    Color bg;
    Color fg;
    switch (status) {
      case 'NO':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        break;
      case 'WARNING':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFF92400E);
        break;
      default:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFF991B1B);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  Color _methodColor(String method) {
    switch (method) {
      case 'Cash':
        return const Color(0xFF059669);
      case 'GCash':
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  Widget _uploadToRecordButton() {
    final recorded = _recordedTabs.contains(_activeTab);
    return GestureDetector(
      onTap: () {
        setState(() => _recordedTabs.add(_activeTab));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              recorded
                  ? 'This report is already recorded.'
                  : 'Collector report recorded in Overall Reports.',
            ),
          ),
        );
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFD1FAE5),
          border: Border(top: BorderSide(color: Color(0xFF9CA3AF))),
        ),
        width: 128,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Text(
            recorded ? 'RECORDED' : 'UPLOAD TO RECORD',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: kPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Montserrat',
        fontWeight: FontWeight.w700,
        fontSize: 11,
        fontStyle: FontStyle.italic,
        color: Color(0xFF374151),
      ),
    );
  }

  void _viewTransaction(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: Image.network(
                url,
                errorBuilder: (_, __, ___) => Container(
                  height: 200,
                  color: const Color(0xFFF3F4F6),
                  child: const Center(
                    child: Icon(
                      Icons.broken_image_rounded,
                      size: 48,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
