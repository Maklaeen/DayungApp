import 'package:capstone_app/Treasurer/treasurer_payment_page.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:capstone_app/shared/treasurer_report_header.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _DeathNoticeReport {
  final String id;
  final String name;
  const _DeathNoticeReport({required this.id, required this.name});
}

class _MemberOverallRow {
  final String userId;
  final String name;
  final double amount;
  final Map<String, String> patayStatus;
  final double advanceAmount;
  final String dropStatus;

  const _MemberOverallRow({
    required this.userId,
    required this.name,
    required this.amount,
    required this.patayStatus,
    required this.advanceAmount,
    required this.dropStatus,
  });
}

class TreasurerOverallReportsMemberBuilder {
  static List<_MemberOverallRow> fromPaymentRows(
    List<Map<String, dynamic>> rows, [
    List<_DeathNoticeReport> notices = const [],
    Map<String, double> advanceTotals = const {},
  ]) {
    final latestByUser = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final rowType = (row['type'] ?? '').toString().trim();
      if (rowType.isNotEmpty && rowType != 'deceased_payment') {
        continue;
      }

      final userId = (row['user_id'] ?? '').toString().trim();
      if (userId.isEmpty) continue;

      final existing = latestByUser[userId];
      if (existing == null) {
        latestByUser[userId] = row;
        continue;
      }

      final currentDate = _parseDate(row['paid_at'] ?? row['created_at']);
      final existingDate = _parseDate(
        existing['paid_at'] ?? existing['created_at'],
      );
      if (currentDate != null &&
          (existingDate == null || currentDate.isAfter(existingDate))) {
        latestByUser[userId] = row;
      }
    }

    final members = latestByUser.values.map((row) {
      final fullName = ((row['users'] as Map?)?['full_name'] ?? '')
          .toString()
          .trim();

      final userId = (row['user_id'] ?? '').toString().trim();

      // Determine drop status based on the latest row for this user
      final latestStatus =
          ((row['status'] ?? 'unpaid').toString().toLowerCase() == 'paid')
              ? 'paid'
              : 'unpaid';
      final isUnpaid = latestStatus == 'unpaid';

      // Build patayStatus by checking all payment rows for this user
      final patayStatus = <String, String>{};
      final userPayments = _paymentsByUserAndDeceased(rows, userId);
      for (final notice in notices) {
        patayStatus[notice.id] = userPayments[notice.id] ?? 'unpaid';
      }

      return _MemberOverallRow(
        userId: userId,
        name: fullName.isEmpty ? 'Member' : fullName,
        amount: _toDouble(row['amount']),
        patayStatus: patayStatus,
        advanceAmount: advanceTotals[userId] ?? 0,
        dropStatus: isUnpaid ? 'Yes' : 'No',
      );
    }).toList();

    members.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return members;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  static Map<String, String> _paymentsByUserAndDeceased(
    List<Map<String, dynamic>> rows,
    String userId,
  ) {
    final map = <String, String>{};
    for (final row in rows) {
      final uid = (row['user_id'] ?? '').toString().trim();
      if (uid != userId) continue;
      final deceasedId = (row['userdeceased'] ?? '').toString().trim();
      if (deceasedId.isEmpty) continue;
      final status =
          ((row['status'] ?? 'unpaid').toString().toLowerCase() == 'paid')
              ? 'paid'
              : 'unpaid';
      // once paid for a given deceased, keep it as paid
      if (map[deceasedId] != 'paid') {
        map[deceasedId] = status;
      }
    }
    return map;
  }
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class TreasurerOverallReportsPage extends StatefulWidget {
  final int dayungUnitId;
  const TreasurerOverallReportsPage({super.key, required this.dayungUnitId});

  static int safeActiveTabIndex(int activeTab, int noticesLength) {
    if (noticesLength <= 0 || activeTab < 0) {
      return 0;
    }
    return activeTab >= noticesLength ? noticesLength - 1 : activeTab;
  }

  static void openAdvancePayment(BuildContext context, int dayungUnitId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TreasurerPaymentPage(dayungUnitId: dayungUnitId),
      ),
    );
  }

  @override
  State<TreasurerOverallReportsPage> createState() =>
      _TreasurerOverallReportsPageState();
}

class _TreasurerOverallReportsPageState
    extends State<TreasurerOverallReportsPage> {
  int _activeTab = 0;
  bool _loadingMembers = true;
  String? _membersError;

  List<_DeathNoticeReport> _notices = [];
  Map<String, double> _totalCashPerNotice = {};
  Map<String, double> _totalCashlessPerNotice = {};
  Map<String, double> _neededPerNotice = {};

  List<_MemberOverallRow> _memberRows = [];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loadingMembers = true;
      _membersError = null;
    });

    try {
      final rows = await Supabase.instance.client
          .from('payments')
          .select(
            'user_id, amount, status, paid_at, created_at, type, userdeceased, '
            'users!payments_user_id_fkey(full_name)',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('type', 'deceased_payment')
          .order('paid_at', ascending: false)
          .order('created_at', ascending: false);

      // Extract distinct deceased user IDs and fetch their names
      final deceasedIds = <String>{};
      for (final row in rows) {
        final userDeceasedId = (row['userdeceased'] ?? '').toString().trim();
        if (userDeceasedId.isNotEmpty) {
          deceasedIds.add(userDeceasedId);
        }
      }

      List<_DeathNoticeReport> notices = [];
      Map<String, double> totalCash = {};
      Map<String, double> totalCashless = {};
      Map<String, double> needed = {};

      if (deceasedIds.isNotEmpty) {
        // Fetch deceased user details
        final deceasedUsers = await Supabase.instance.client
            .from('users')
            .select('id, full_name')
            .inFilter('id', deceasedIds.toList());

        // Build notices from deceased users
        for (final deceasedUser in deceasedUsers) {
          final id = (deceasedUser['id'] ?? '').toString();
          final name = (deceasedUser['full_name'] ?? '').toString().trim();
          notices.add(_DeathNoticeReport(id: id, name: name));

          // Initialize totals for each deceased
          totalCash[id] = 0.0;
          totalCashless[id] = 0.0;
          needed[id] = 1200.0; // Default needed amount
        }

        // Sort notices by name
        notices.sort((a, b) => a.name.compareTo(b.name));
      }

      // Calculate totals from payment rows
      for (final row in rows) {
        final userDeceasedId = (row['userdeceased'] ?? '').toString().trim();
        final amount = _toDouble(row['amount']);
        final status = (row['status'] ?? 'unpaid').toString().toLowerCase();

        if (userDeceasedId.isNotEmpty) {
          if (status == 'paid') {
            totalCash[userDeceasedId] =
                (totalCash[userDeceasedId] ?? 0) + amount;
          } else {
            totalCashless[userDeceasedId] =
                (totalCashless[userDeceasedId] ?? 0) + amount;
          }
        }
      }

      final advanceRows = await Supabase.instance.client
          .from('advance_payments')
          .select('user_id, amount');

      final advanceTotals = <String, double>{};
      for (final row in advanceRows) {
        final userId = (row['user_id'] ?? '').toString().trim();
        if (userId.isEmpty) continue;
        advanceTotals[userId] =
            (advanceTotals[userId] ?? 0) + _toDouble(row['amount']);
      }

      final members = TreasurerOverallReportsMemberBuilder.fromPaymentRows(
        List<Map<String, dynamic>>.from(rows),
        notices,
        advanceTotals,
      );

      if (!mounted) return;
      setState(() {
        _notices = notices;
        _totalCashPerNotice = totalCash;
        _totalCashlessPerNotice = totalCashless;
        _neededPerNotice = needed;
        _memberRows = members;
        _loadingMembers = false;
        _activeTab = TreasurerOverallReportsPage.safeActiveTabIndex(
          _activeTab,
          _notices.length,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notices = [];
        _totalCashPerNotice = {};
        _totalCashlessPerNotice = {};
        _neededPerNotice = {};
        _memberRows = [];
        _loadingMembers = false;
        _membersError = 'Failed to load members: $e';
      });
    }
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

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
    if (_notices.isEmpty) {
      return Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: const Center(
          child: Text(
            'No death notice data available yet.',
            style: TextStyle(
              fontFamily: 'OpenSans',
              fontSize: 12,
              color: Color(0xFF4B5563),
            ),
          ),
        ),
      );
    }

    final noticeIndex = TreasurerOverallReportsPage.safeActiveTabIndex(
      _activeTab,
      _notices.length,
    );
    final notice = _notices[noticeIndex];
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
    if (_loadingMembers) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF9CA3AF)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_membersError != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF9CA3AF)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _membersError!,
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final members = _memberRows.isEmpty
        ? const <_MemberOverallRow>[]
        : _memberRows;

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
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () => TreasurerOverallReportsPage.openAdvancePayment(
                      context,
                      widget.dayungUnitId,
                    ),
                    child: _hCell('Advance\nPayment'),
                  ),
                ),
                Expanded(flex: 2, child: _hCell('Suggest\nto drop\nstatus')),
              ],
            ),
          ),
          if (members.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'No members found for this dayung unit.',
                style: TextStyle(
                  fontFamily: 'OpenSans',
                  fontSize: 12,
                  color: Color(0xFF4B5563),
                ),
              ),
            )
          else
            ...members.asMap().entries.map((e) {
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
                    Expanded(
                      flex: 2,
                      child: _dCell(m.amount.toStringAsFixed(0)),
                    ),
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
