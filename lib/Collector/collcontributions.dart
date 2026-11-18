import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:capstone_app/widgets/record_data_table.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kPaid = Color(0xFF2E7D32);
const kPending = Color(0xFFF57C00);

class CollectorContributionsPage extends StatefulWidget {
  final int dayungUnitId;
  const CollectorContributionsPage({super.key, required this.dayungUnitId});

  @override
  State<CollectorContributionsPage> createState() =>
      _CollectorContributionsPageState();
}

class _CollectorContributionsPageState
    extends State<CollectorContributionsPage> {
  final sb = Supabase.instance.client;
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

  double _amountOf(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0.0;
  }

  Future<void> _fetchContributions() async {
    if (mounted) setState(() => _loading = true);
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
            'id, user_id, amount, status, paid_at, created_at, collected_by, userdeceased, deceased_name, dayung_unit_id',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('user_id', currentUser.id)
          .order('paid_at', ascending: false)
          .limit(200);

      final deceasedIds = (payments as List)
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

      final sortedPayments = List<Map<String, dynamic>>.from(payments)
        ..sort((a, b) {
          const statusOrder = {'pending': 0, 'unpaid': 0, 'paid': 1};
          final statusA = (a['status'] ?? '').toString().toLowerCase();
          final statusB = (b['status'] ?? '').toString().toLowerCase();
          final orderA = statusOrder[statusA] ?? 2;
          final orderB = statusOrder[statusB] ?? 2;
          if (orderA != orderB) return orderA.compareTo(orderB);
          return 0;
        });

      if (!mounted) return;
      setState(() {
        _payments = sortedPayments;
        _users = usersMap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _payments = [];
        _users = {};
        _loading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading payments: $e')));
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

  Widget _summaryCard({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
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
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 21),
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
        final pending = _summaryCard(
          label: 'Pending',
          count: _countByStatus('pending'),
          color: kPending,
          icon: Icons.schedule_rounded,
        );
        final paid = _summaryCard(
          label: 'Paid',
          count: _countByStatus('paid'),
          color: kPaid,
          icon: Icons.check_circle_rounded,
        );

        if (constraints.maxWidth < 520) {
          return Column(children: [pending, const SizedBox(height: 12), paid]);
        }

        return Row(
          children: [
            Expanded(child: pending),
            const SizedBox(width: 12),
            Expanded(child: paid),
          ],
        );
      },
    );
  }

  DataRow _paymentRow(Map<String, dynamic> p) {
    final paid = (p['status']?.toString().toLowerCase() == 'paid');
    final colors = Theme.of(context).colorScheme;
    final paidAtStr = _fmtDateTime(p['paid_at']);
    final userDeceasedId = (p['userdeceased'] ?? '').toString();
    final userDeceased = (p['deceased_name']?.toString().isNotEmpty == true)
        ? p['deceased_name'].toString()
        : (userDeceasedId.isNotEmpty
              ? _users[userDeceasedId] ?? userDeceasedId
              : 'Membership Payment');
    final amount = _amountOf(p['amount']);

    return DataRow(
      cells: [
        DataCell(
          Text(userDeceased, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        DataCell(
          Text(
            '₱${amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (paid ? kPaid : kPending).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              paid ? 'Paid' : 'Pending',
              style: TextStyle(
                color: paid ? kPaid : kPending,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        DataCell(Text(paidAtStr.isEmpty ? '—' : paidAtStr)),
      ],
    );
  }

  Widget _paymentTable() {
    final colors = Theme.of(context).colorScheme;
    return RecordDataTable(
      minWidth: 620,
      columnSpacing: 18,
      horizontalMargin: 16,
      headingRowHeight: 50,
      dataRowMinHeight: 56,
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
      rows: _payments.map(_paymentRow).toList(),
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
          decoration: dayungSectionCardDecoration(context, radius: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  size: 28,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'No contributions yet',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                  fontFamily: 'Montserrat',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

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
        child: RefreshIndicator(
          color: colors.primary,
          onRefresh: _fetchContributions,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'My contributions',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh contributions',
                    onPressed: _loading ? null : _fetchContributions,
                    icon: const Icon(Icons.refresh_rounded),
                    style: IconButton.styleFrom(
                      fixedSize: const Size(48, 48),
                      backgroundColor: dayungSurface(context),
                      foregroundColor: colors.primary,
                      side: BorderSide(color: dayungBorder(context)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _summaryCards(),
              const SizedBox(height: 16),
              if (_loading)
                const DayungPageSkeleton(
                  layout: DayungSkeletonLayout.list,
                  padding: EdgeInsets.all(8),
                  itemCount: 3,
                )
              else if (_payments.isEmpty)
                _emptyState()
              else
                _paymentTable(),
            ],
          ),
        ),
      ),
    );
  }
}
