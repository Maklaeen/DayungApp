import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Placeholder models
// ---------------------------------------------------------------------------

enum _MemberChangeType { added, removed, deceased, beneficiaryAdded, beneficiaryRemoved }

class _MemberChange {
  final String memberName;
  final _MemberChangeType type;
  final String date;
  final String? note;

  const _MemberChange({
    required this.memberName,
    required this.type,
    required this.date,
    this.note,
  });
}

class _MemberPaymentRow {
  final String name;
  final Map<String, String> patayStatus; // noticeId -> 'paid' | 'unpaid'
  final double advanceAmount;
  final String dropStatus;

  const _MemberPaymentRow({
    required this.name,
    required this.patayStatus,
    required this.advanceAmount,
    required this.dropStatus,
  });
}

class _DeathNoticeRef {
  final String id;
  final String name;
  const _DeathNoticeRef({required this.id, required this.name});
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class PresSecMembersReportPage extends StatefulWidget {
  final int dayungUnitId;
  const PresSecMembersReportPage({super.key, required this.dayungUnitId});

  @override
  State<PresSecMembersReportPage> createState() =>
      _PresSecMembersReportPageState();
}

class _PresSecMembersReportPageState extends State<PresSecMembersReportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Placeholder data
  final _notices = const [
    _DeathNoticeRef(id: 'd1', name: 'Patay 1'),
    _DeathNoticeRef(id: 'd2', name: 'Patay 2'),
  ];

  final _changes = const [
    _MemberChange(
      memberName: 'Juan Dela Cruz',
      type: _MemberChangeType.added,
      date: '2024-06-01',
    ),
    _MemberChange(
      memberName: 'Maria Santos',
      type: _MemberChangeType.removed,
      date: '2024-06-03',
      note: 'Deceased member',
    ),
    _MemberChange(
      memberName: 'Pedro Reyes',
      type: _MemberChangeType.beneficiaryAdded,
      date: '2024-06-05',
      note: 'Added beneficiary: Ana Reyes',
    ),
    _MemberChange(
      memberName: 'Lola Nena',
      type: _MemberChangeType.deceased,
      date: '2024-06-10',
    ),
  ];

  final _memberRows = const [
    _MemberPaymentRow(
      name: 'Fakyu nnyung tulo',
      patayStatus: {'d1': 'paid', 'd2': 'paid'},
      advanceAmount: 100,
      dropStatus: 'No',
    ),
    _MemberPaymentRow(
      name: 'Yawa',
      patayStatus: {'d1': 'paid', 'd2': 'paid'},
      advanceAmount: 300,
      dropStatus: 'No',
    ),
    _MemberPaymentRow(
      name: 'Bogoy na tomboy',
      patayStatus: {'d1': 'paid', 'd2': 'unpaid'},
      advanceAmount: 0,
      dropStatus: 'Warning',
    ),
    _MemberPaymentRow(
      name: 'Nardave Gwapo',
      patayStatus: {'d1': 'unpaid', 'd2': 'unpaid'},
      advanceAmount: 0,
      dropStatus: 'Yes',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dayungSurface(context),
      appBar: AppBar(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Members Report',
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          tabs: const [
            Tab(text: 'Updates'),
            Tab(text: 'Payment Status'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _updatesTab(),
          _paymentStatusTab(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 0 — Member Updates (added / removed / deceased / beneficiary changes)
  // ---------------------------------------------------------------------------

  Widget _updatesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summaryChips(),
          const SizedBox(height: 16),
          const Text(
            'Recent Changes',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: kPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ..._changes.map(_changeCard),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _summaryChips() {
    final added =
        _changes.where((c) => c.type == _MemberChangeType.added).length;
    final removed =
        _changes.where((c) => c.type == _MemberChangeType.removed).length;
    final deceased =
        _changes.where((c) => c.type == _MemberChangeType.deceased).length;
    final beneficiary = _changes
        .where((c) =>
            c.type == _MemberChangeType.beneficiaryAdded ||
            c.type == _MemberChangeType.beneficiaryRemoved)
        .length;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _summaryChip(
          label: 'Added',
          count: added,
          color: const Color(0xFF10B981),
          icon: Icons.person_add_rounded,
        ),
        _summaryChip(
          label: 'Removed',
          count: removed,
          color: const Color(0xFFEF4444),
          icon: Icons.person_remove_rounded,
        ),
        _summaryChip(
          label: 'Deceased',
          count: deceased,
          color: const Color(0xFF8B5CF6),
          icon: Icons.sentiment_very_dissatisfied_rounded,
        ),
        _summaryChip(
          label: 'Beneficiary',
          count: beneficiary,
          color: const Color(0xFFF59E0B),
          icon: Icons.family_restroom_rounded,
        ),
      ],
    );
  }

  Widget _summaryChip({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            '$count $label',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _changeCard(_MemberChange change) {
    final color = _changeColor(change.type);
    final icon = _changeIcon(change.type);
    final label = _changeLabel(change.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: dayungSectionCardDecoration(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        change.memberName,
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: dayungTextColor(context),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  change.date,
                  style: TextStyle(
                    fontFamily: 'OpenSans',
                    fontSize: 11,
                    color: dayungSubtextColor(context),
                  ),
                ),
                if (change.note != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    change.note!,
                    style: TextStyle(
                      fontFamily: 'OpenSans',
                      fontSize: 12,
                      color: dayungSubtextColor(context),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _changeColor(_MemberChangeType type) {
    switch (type) {
      case _MemberChangeType.added:
        return const Color(0xFF10B981);
      case _MemberChangeType.removed:
        return const Color(0xFFEF4444);
      case _MemberChangeType.deceased:
        return const Color(0xFF8B5CF6);
      case _MemberChangeType.beneficiaryAdded:
        return const Color(0xFFF59E0B);
      case _MemberChangeType.beneficiaryRemoved:
        return const Color(0xFFEC4899);
    }
  }

  IconData _changeIcon(_MemberChangeType type) {
    switch (type) {
      case _MemberChangeType.added:
        return Icons.person_add_rounded;
      case _MemberChangeType.removed:
        return Icons.person_remove_rounded;
      case _MemberChangeType.deceased:
        return Icons.sentiment_very_dissatisfied_rounded;
      case _MemberChangeType.beneficiaryAdded:
        return Icons.family_restroom_rounded;
      case _MemberChangeType.beneficiaryRemoved:
        return Icons.family_restroom_rounded;
    }
  }

  String _changeLabel(_MemberChangeType type) {
    switch (type) {
      case _MemberChangeType.added:
        return 'Added';
      case _MemberChangeType.removed:
        return 'Removed';
      case _MemberChangeType.deceased:
        return 'Deceased';
      case _MemberChangeType.beneficiaryAdded:
        return 'Beneficiary +';
      case _MemberChangeType.beneficiaryRemoved:
        return 'Beneficiary −';
    }
  }

  // ---------------------------------------------------------------------------
  // Tab 1 — Payment Status (all members across all death notices)
  // ---------------------------------------------------------------------------

  Widget _paymentStatusTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _paymentSummaryRow(),
          const SizedBox(height: 16),
          Container(
            decoration: dayungSectionCardDecoration(context),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.06),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        flex: 3,
                        child: Text(
                          'Member',
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            color: kPrimary,
                          ),
                        ),
                      ),
                      ..._notices.map(
                        (n) => Expanded(
                          flex: 2,
                          child: Text(
                            n.name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Montserrat',
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              color: kPrimary,
                            ),
                          ),
                        ),
                      ),
                      const Expanded(
                        flex: 2,
                        child: Text(
                          'Advance',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            color: kPrimary,
                          ),
                        ),
                      ),
                      const Expanded(
                        flex: 2,
                        child: Text(
                          'Drop?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            color: kPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ...List.generate(_memberRows.length, (i) {
                  final m = _memberRows[i];
                  return Container(
                    color: i % 2 == 0
                        ? Colors.transparent
                        : kPrimary.withValues(alpha: 0.025),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            m.name,
                            style: TextStyle(
                              fontFamily: 'OpenSans',
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                              color: dayungTextColor(context),
                            ),
                          ),
                        ),
                        ..._notices.map((n) {
                          final status = m.patayStatus[n.id] ?? 'unpaid';
                          return Expanded(
                            flex: 2,
                            child: Center(child: _statusChip(status)),
                          );
                        }),
                        Expanded(
                          flex: 2,
                          child: Center(
                            child: Text(
                              m.advanceAmount > 0
                                  ? '₱${m.advanceAmount.toStringAsFixed(0)}'
                                  : '—',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                color: m.advanceAmount > 0
                                    ? const Color(0xFFF59E0B)
                                    : dayungSubtextColor(context),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Center(child: _dropChip(m.dropStatus)),
                        ),
                      ],
                    ),
                  );
                }),
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.03),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(20)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _paymentSummaryRow() {
    final fullyPaid = _memberRows
        .where((m) => m.dropStatus.toLowerCase() == 'no')
        .length;
    final warning = _memberRows
        .where((m) => m.dropStatus.toLowerCase() == 'warning')
        .length;
    final notPaid = _memberRows
        .where((m) => m.dropStatus.toLowerCase() == 'yes')
        .length;

    return Row(
      children: [
        Expanded(
          child: _miniStatCard(
            label: 'Fully Paid',
            count: fullyPaid,
            color: const Color(0xFF10B981),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _miniStatCard(
            label: 'Partial',
            count: warning,
            color: const Color(0xFFF59E0B),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _miniStatCard(
            label: 'Not Paid',
            count: notPaid,
            color: const Color(0xFFEF4444),
          ),
        ),
      ],
    );
  }

  Widget _miniStatCard({
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'OpenSans',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared chips
  // ---------------------------------------------------------------------------

  Widget _statusChip(String status) {
    final isPaid = status == 'paid';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isPaid
            ? const Color(0xFFD1FAE5)
            : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isPaid ? 'Paid' : 'Unpaid',
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: isPaid
              ? const Color(0xFF065F46)
              : const Color(0xFF991B1B),
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
}
