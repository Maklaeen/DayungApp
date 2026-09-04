import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:capstone_app/shared/treasurer_report_header.dart';
import 'package:flutter/material.dart';

class _DeathNoticeReport {
  final String id;
  final String name;
  const _DeathNoticeReport({required this.id, required this.name});
}

class _MemberOverallRow {
  final String name;
  final double amount;
  final Map<String, String> patayStatus;
  final double advanceAmount;
  final String dropStatus;

  const _MemberOverallRow({
    required this.name,
    required this.amount,
    required this.patayStatus,
    required this.advanceAmount,
    required this.dropStatus,
  });
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class TreasurerOverallReportsPage extends StatefulWidget {
  final int dayungUnitId;
  const TreasurerOverallReportsPage({super.key, required this.dayungUnitId});

  @override
  State<TreasurerOverallReportsPage> createState() =>
      _TreasurerOverallReportsPageState();
}

class _TreasurerOverallReportsPageState
    extends State<TreasurerOverallReportsPage> {
  int _activeTab = 0;

  final _notices = const [
    _DeathNoticeReport(id: 'd1', name: 'Deceased 1'),
    _DeathNoticeReport(id: 'd2', name: 'Deceased 2'),
  ];

  final _totalCashPerNotice = const {'d1': 400.0, 'd2': 0.0};
  final _totalCashlessPerNotice = const {'d1': 800.0, 'd2': 0.0};
  final _neededPerNotice = const {'d1': 1200.0, 'd2': 1200.0};

  final _memberRows = const [
    _MemberOverallRow(
      name: 'Member 1',
      amount: 300,
      patayStatus: {'d1': 'paid', 'd2': 'paid'},
      advanceAmount: 100,
      dropStatus: 'No',
    ),
    _MemberOverallRow(
      name: 'Member 2',
      amount: 500,
      patayStatus: {'d1': 'paid', 'd2': 'paid'},
      advanceAmount: 300,
      dropStatus: 'No',
    ),
    _MemberOverallRow(
      name: 'Member 3',
      amount: 100,
      patayStatus: {'d1': 'paid', 'd2': 'unpaid'},
      advanceAmount: 0,
      dropStatus: 'warning',
    ),
    _MemberOverallRow(
      name: 'Member 4',
      amount: 0,
      patayStatus: {'d1': 'unpaid', 'd2': 'unpaid'},
      advanceAmount: 0,
      dropStatus: 'yes',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            const TreasurerReportHeader(title: 'Overall Reports'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(width: 760, child: _summaryTable()),
                    ),
                    const SizedBox(height: 24),

                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(width: 760, child: _membersTable()),
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

  // ---------------------------------------------------------------------------
  // Summary table with Patay tabs
  // ---------------------------------------------------------------------------

  Widget _summaryTable() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF9CA3AF)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tab header row
          Row(
            children: _notices.asMap().entries.map((e) {
              final i = e.key;
              final n = e.value;
              final selected = _activeTab == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _activeTab = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 4,
                    ),
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
                      n.name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: selected ? kPrimary : const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          // Column headers
          Container(
            color: const Color(0xFFF3F4F6),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _hCell(
                    'Total cash\namount\ncollected\nfrom\nCollectors',
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _hCell('Total\ncashless\namount\ncollected'),
                ),
                Expanded(flex: 2, child: _hCell('Overall\namount\ncollected')),
                Expanded(
                  flex: 2,
                  child: _hCell('Overall\namount needed\nto collect'),
                ),
                Expanded(
                  flex: 2,
                  child: _hCell('Amount\nthat must\ncollected'),
                ),
              ],
            ),
          ),
          // Data row
          _summaryDataRow(),
          // Submit button
          _submitButton(),
        ],
      ),
    );
  }

  Widget _summaryDataRow() {
    final notice = _notices[_activeTab];
    final cash = _totalCashPerNotice[notice.id] ?? 0;
    final cashless = _totalCashlessPerNotice[notice.id] ?? 0;
    final needed = _neededPerNotice[notice.id] ?? 0;
    final overall = cash + cashless;
    final lacking = (needed - overall).clamp(0.0, double.infinity);

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _dCell(
              '(₱${cash.toStringAsFixed(0)})',
              color: const Color(0xFF059669),
            ),
          ),
          Expanded(
            flex: 2,
            child: _dCell(
              '(₱${cashless.toStringAsFixed(0)})',
              color: const Color(0xFF2563EB),
            ),
          ),
          Expanded(
            flex: 2,
            child: _dCell(
              '₱${overall.toStringAsFixed(0)}',
              bold: true,
              color: kPrimary,
            ),
          ),
          Expanded(
            flex: 2,
            child: _dCell(
              '₱${lacking.toStringAsFixed(0)}',
              color: const Color(0xFFF59E0B),
            ),
          ),
          Expanded(
            flex: 2,
            child: _dCell(
              '₱${needed.toStringAsFixed(0)}',
              color: const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Members table
  // ---------------------------------------------------------------------------

  Widget _membersTable() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF9CA3AF)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            color: const Color(0xFFD1FAE5),
            child: Row(
              children: [
                Expanded(flex: 3, child: _hCell('Members')),
                Expanded(flex: 2, child: _hCell('Amount')),
                ..._notices.map(
                  (n) => Expanded(flex: 2, child: _hCell(n.name)),
                ),
                Expanded(flex: 2, child: _hCell('Advance\nPayment')),
                Expanded(flex: 2, child: _hCell('Suggest\nto drop\nstatus')),
              ],
            ),
          ),
          ..._memberRows.asMap().entries.map((e) {
            final i = e.key;
            final m = e.value;
            return Container(
              decoration: BoxDecoration(
                color: i % 2 == 0
                    ? Colors.transparent
                    : kPrimary.withValues(alpha: 0.025),
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                children: [
                  Expanded(flex: 3, child: _dCell(m.name)),
                  Expanded(flex: 2, child: _dCell(m.amount.toStringAsFixed(0))),
                  ..._notices.map((n) {
                    final status = m.patayStatus[n.id] ?? 'unpaid';
                    return Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        child: _statusChip(status),
                      ),
                    );
                  }),
                  Expanded(
                    flex: 2,
                    child: _dCell(
                      m.advanceAmount > 0
                          ? m.advanceAmount.toStringAsFixed(0)
                          : '0',
                      color: m.advanceAmount > 0
                          ? const Color(0xFFF59E0B)
                          : null,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      child: _dropChip(m.dropStatus),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  Widget _hCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Montserrat',
          fontWeight: FontWeight.w800,
          fontSize: 11,
          color: Color(0xFF111827),
        ),
      ),
    );
  }

  Widget _dCell(String text, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'OpenSans',
          fontSize: 12,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          color: color ?? dayungTextColor(context),
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final isPaid = status == 'paid';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isPaid ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isPaid ? 'paid' : 'unpaid',
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: isPaid ? const Color(0xFF065F46) : const Color(0xFF991B1B),
        ),
      ),
    );
  }

  Widget _dropChip(String status) {
    Color bg;
    Color fg;
    switch (status.toLowerCase()) {
      case 'no':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        break;
      case 'warning':
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

  Widget _submitButton() {
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submit report — backend pending')),
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFD1FAE5),
          border: Border(top: BorderSide(color: Color(0xFF9CA3AF))),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: const Center(
          child: Text(
            'SUBMIT REPORT',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w800,
              fontSize: 12,
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
        fontWeight: FontWeight.w800,
        fontSize: 12,
        color: kPrimary,
      ),
    );
  }
}
