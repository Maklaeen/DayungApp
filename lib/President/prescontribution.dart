import 'package:capstone_app/utils/theme_surface.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/widgets/record_data_table.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimary = Color(0xFF0D47A1);
const kPrimaryDark = Color(0xFF083366);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);
const kDanger = Color(0xFFEF4444);
const kPaid = Color(0xFF2E7D32);
const kPending = Color(0xFFF57C00);

class PresidentContributionsPage extends StatefulWidget {
  final int dayungUnitId;

  const PresidentContributionsPage({super.key, required this.dayungUnitId});

  @override
  State<PresidentContributionsPage> createState() =>
      _PresidentContributionsPageState();
}

class _PresidentContributionsPageState
    extends State<PresidentContributionsPage> {
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
    final dt = DateTime.tryParse(s)?.toLocal();
    if (dt == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _formatAmount(dynamic amount) {
    if (amount is num) {
      return amount.toStringAsFixed(2);
    }
    final parsed = double.tryParse(amount.toString());
    if (parsed != null) {
      return parsed.toStringAsFixed(2);
    }
    return amount?.toString() ?? '0.00';
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
          .where((value) => value != null && value.toString().isNotEmpty)
          .map((value) => value.toString())
          .toSet()
          .toList();

      final usersRes = deceasedIds.isEmpty
          ? <dynamic>[]
          : await sb
                .from('users')
                .select('id, full_name')
                .inFilter('id', deceasedIds);

      final usersMap = <String, dynamic>{
        for (final user in usersRes)
          user['id'].toString(): user['full_name'] ?? 'Unknown',
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
    return _payments.where((payment) {
      final value = payment['status']?.toString().toLowerCase() ?? '';
      if (status.toLowerCase() == 'pending') {
        return value == 'pending' || value == 'unpaid';
      }
      return value == status.toLowerCase();
    }).length;
  }

  Widget _summaryCard({
    required String label,
    required int count,
    required IconData icon,
    required Color accent,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: dayungSectionCardDecoration(context, radius: 16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: accent, size: 21),
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
                const SizedBox(height: 3),
                Text(
                  _loading ? '—' : '$count',
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

  Widget _summaryCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final paidCard = _summaryCard(
          label: 'Paid',
          count: _countByStatus('paid'),
          icon: Icons.check_circle_rounded,
          accent: kPaid,
        );
        final pendingCard = _summaryCard(
          label: 'Pending',
          count: _countByStatus('pending'),
          icon: Icons.schedule_rounded,
          accent: kPending,
        );

        if (constraints.maxWidth < 520) {
          return Column(
            children: [paidCard, const SizedBox(height: 12), pendingCard],
          );
        }

        return Row(
          children: [
            Expanded(child: paidCard),
            const SizedBox(width: 12),
            Expanded(child: pendingCard),
          ],
        );
      },
    );
  }

  Widget _emptyState() {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(24),
          decoration: dayungSectionCardDecoration(context, radius: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  size: 30,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No contributions yet',
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
                'Paid and pending contribution records will appear here.',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.onSurfaceVariant,
                  fontFamily: 'OpenSans',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _fetchContributions,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contributionsTable() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: RefreshIndicator(
        onRefresh: _fetchContributions,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          children: [
            RecordDataTable(
              minWidth: 620,
              columnSpacing: 20,
              horizontalMargin: 16,
              headingRowHeight: 50,
              dataRowMinHeight: 58,
              dataRowMaxHeight: 76,
              showCheckboxColumn: false,
              headingTextStyle: TextStyle(
                color: colors.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'Montserrat',
              ),
              dataTextStyle: TextStyle(
                color: colors.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                fontFamily: 'OpenSans',
              ),
              columns: const [
                DataColumn(label: Text('Contribution')),
                DataColumn(label: Text('Amount')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Paid at')),
              ],
              rows: _payments.map((payment) {
                final userDeceasedId = (payment['userdeceased'] ?? '')
                    .toString();
                final userDeceased =
                    (payment['deceased_name']?.toString().isNotEmpty == true)
                    ? payment['deceased_name'].toString()
                    : (userDeceasedId.isNotEmpty
                          ? _users[userDeceasedId] ?? userDeceasedId
                          : 'Membership Payment');
                final paidAtStr = _fmtDateTime(payment['paid_at']);
                final paid =
                    payment['status']?.toString().toLowerCase() == 'paid';
                final statusColor = paid ? kPaid : kPending;

                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        userDeceased.toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DataCell(
                      Text(
                        '₱${_formatAmount(payment['amount'])}',
                        style: TextStyle(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          paid ? 'Paid' : 'Pending',
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    DataCell(Text(paidAtStr.isEmpty ? '—' : paidAtStr)),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
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
  //                     PresidentPaymentPage(dayungUnitId: widget.dayungUnitId),
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
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contribution History',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Montserrat',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Review paid and pending contributions',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 13,
                            fontFamily: 'OpenSans',
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh contributions',
                    onPressed: _loading ? null : _fetchContributions,
                    icon: const Icon(Icons.refresh_rounded),
                    style: IconButton.styleFrom(
                      fixedSize: const Size(52, 52),
                      backgroundColor: dayungSurface(context),
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      side: BorderSide(color: dayungBorder(context)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: _summaryCards(),
            ),
            Expanded(
              child: _loading
                  ? const DayungPageSkeleton(
                      layout: DayungSkeletonLayout.list,
                      padding: EdgeInsets.all(16),
                      itemCount: 3,
                    )
                  : (_payments.isEmpty ? _emptyState() : _contributionsTable()),
            ),
          ],
        ),
      ),
    );
  }
}
