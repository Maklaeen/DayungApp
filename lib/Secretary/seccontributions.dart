import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:capstone_app/widgets/record_data_table.dart';

// Additional colors for secretary contributions specific styling (new UI)
const kSuccess = Color(0xFF10B981);
const kDanger = Color(0xFFEF4444);
const kPaid = Color(0xFF2E7D32);
const kPending = Color(0xFFF57C00);
const double kEdge = 16;

class SecretaryContributionsPage extends StatefulWidget {
  final int dayungUnitId;
  const SecretaryContributionsPage({super.key, required this.dayungUnitId});

  @override
  State<SecretaryContributionsPage> createState() =>
      _SecretaryContributionsPageState();
}

class _SecretaryContributionsPageState
    extends State<SecretaryContributionsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _payments = [];
  Map<String, dynamic> _users = {};

  @override
  void initState() {
    super.initState();
    _fetchContributions();
  }

  String _fmtDateTime(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    DateTime? dt = DateTime.tryParse(s);
    if (dt == null) return '';
    dt = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<void> _fetchContributions() async {
    if (mounted) setState(() => _loading = true);
    final sb = Supabase.instance.client;
    try {
      final currentUser = sb.auth.currentUser;
      if (currentUser == null) {
        if (!mounted) return;
        setState(() {
          _payments = [];
          _users = {};
          _loading = false;
        });
        return;
      }

      final payments = await sb
          .from('payments')
          .select(
            'id, user_id, amount, status, paid_at, collected_by, userdeceased, deceased_name, '
            'collector:users!payments_collected_by_fkey(full_name)',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('user_id', currentUser.id)
          .order('paid_at', ascending: false);

      final deceasedIds = payments
          .map((p) => p['userdeceased'])
          .where((v) => v != null && v.toString().isNotEmpty)
          .map((v) => v.toString())
          .toSet()
          .toList();

      final usersRes = deceasedIds.isEmpty
          ? <dynamic>[]
          : await sb
                .from('users')
                .select('id, full_name')
                .inFilter('id', deceasedIds);

      final usersMap = <String, dynamic>{
        for (var u in usersRes) u['id'].toString(): u['full_name'] ?? 'Unknown',
      };

      if (!mounted) return;
      setState(() {
        _payments = List<Map<String, dynamic>>.from(payments);
        _users = usersMap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading contributions: $e')),
      );
    }
  }

  int _countByStatus(String status) {
    return _payments.where((p) {
      final value = p['status']?.toString().toLowerCase() ?? '';
      if (status.toLowerCase() == 'pending') {
        return value == 'pending' || value == 'unpaid';
      }
      return value == status.toLowerCase();
    }).length;
  }

  Widget _buildStatusSummaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: dayungSectionCardDecoration(context, radius: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'OpenSans',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Widget _paymentShortcutCard() {
  //   return Container(
  //     margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
  //     padding: const EdgeInsets.all(18),
  //     decoration: BoxDecoration(
  //       gradient: const LinearGradient(
  //         colors: [Color(0xFF083366), Color(0xFF0D47A1)],
  //         begin: Alignment.topLeft,
  //         end: Alignment.bottomRight,
  //       ),
  //       borderRadius: BorderRadius.circular(18),
  //     ),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         const SizedBox(height: 8),
  //         const Text(
  //           'Open your payment page to review your pending records and choose cash or GCash.',
  //           style: TextStyle(
  //             color: Colors.white70,
  //             fontSize: 14,
  //             fontWeight: FontWeight.w600,
  //           ),
  //         ),
  //         const SizedBox(height: 14),
  //         ElevatedButton.icon(
  //           onPressed: () {
  //             Navigator.push(
  //               context,
  //               MaterialPageRoute(
  //                 builder: (_) =>
  //                     SecretaryPaymentPage(dayungUnitId: widget.dayungUnitId),
  //               ),
  //             ).then((_) => _fetchContributions());
  //           },
  //           icon: const Icon(Icons.arrow_forward_rounded),
  //           label: const Text('Open Payment Page'),
  //           style: ElevatedButton.styleFrom(
  //             backgroundColor: Colors.white,
  //             foregroundColor: kPrimary,
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: dayungPageBackground(context),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [dayungPageBackground(context), dayungSoftSurface(context)],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contribution history',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Review your payments and their status.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh contributions',
                    onPressed: _fetchContributions,
                    icon: const Icon(Icons.refresh_rounded),
                    color: colors.primary,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatusSummaryCard(
                      label: 'Paid',
                      value: _loading ? '—' : '${_countByStatus('paid')}',
                      icon: Icons.check_circle_rounded,
                      accent: kSuccess,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatusSummaryCard(
                      label: 'Pending',
                      value: _loading ? '—' : '${_countByStatus('pending')}',
                      icon: Icons.schedule_rounded,
                      accent: kPending,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Content
            Expanded(
              child: _loading
                  ? const DayungPageSkeleton(
                      layout: DayungSkeletonLayout.list,
                      padding: EdgeInsets.all(16),
                      itemCount: 3,
                    )
                  : (_payments.isEmpty
                        ? Center(
                            child: Container(
                              margin: const EdgeInsets.all(20),
                              padding: const EdgeInsets.all(24),
                              decoration: dayungSectionCardDecoration(context),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.account_balance_wallet_rounded,
                                    size: 48,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No contributions found',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: colors.onSurface,
                                      fontFamily: 'Montserrat',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Payments recorded for your account will appear here.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: colors.onSurfaceVariant,
                                      fontFamily: 'OpenSans',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  OutlinedButton.icon(
                                    onPressed: _fetchContributions,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Refresh'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(16),
                            child: RefreshIndicator(
                              onRefresh: _fetchContributions,
                              child: ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  RecordDataTable(
                                    minWidth: 640,
                                    headingRowHeight: 52,
                                    dataRowMinHeight: 56,
                                    dataRowMaxHeight: 78,
                                    columnSpacing: 24,
                                    horizontalMargin: 20,
                                    columns: const [
                                      DataColumn(label: Text('Contribution')),
                                      DataColumn(label: Text('Amount')),
                                      DataColumn(label: Text('Status')),
                                      DataColumn(label: Text('Paid at')),
                                    ],
                                    rows: _payments.map((p) {
                                      final userDeceasedId =
                                          (p['userdeceased'] ?? '').toString();
                                      final userDeceased =
                                          (p['deceased_name']
                                                  ?.toString()
                                                  .isNotEmpty ==
                                              true)
                                          ? p['deceased_name'].toString()
                                          : (userDeceasedId.isNotEmpty
                                                ? _users[userDeceasedId] ??
                                                      userDeceasedId
                                                : 'Membership Payment');
                                      final paidAtStr = _fmtDateTime(
                                        p['paid_at'],
                                      );
                                      final paid =
                                          p['status']
                                              ?.toString()
                                              .toLowerCase() ==
                                          'paid';
                                      final statusColor = paid
                                          ? kPaid
                                          : kPending;
                                      return DataRow(
                                        cells: [
                                          DataCell(
                                            Text(
                                              userDeceased,
                                              style: TextStyle(
                                                color: colors.onSurface,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              '₱${p['amount']}',
                                              style: TextStyle(
                                                color: colors.onSurface,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: statusColor.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    paid
                                                        ? Icons
                                                              .check_circle_rounded
                                                        : Icons
                                                              .schedule_rounded,
                                                    color: statusColor,
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    paid ? 'Paid' : 'Pending',
                                                    style: TextStyle(
                                                      color: statusColor,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              paidAtStr.isEmpty
                                                  ? '—'
                                                  : paidAtStr,
                                            ),
                                          ),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          )),
            ),
          ],
        ),
      ),
    );
  }
}
