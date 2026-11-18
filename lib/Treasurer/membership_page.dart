import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/widgets/record_data_table.dart';

const Color _kPageBg = Color(0xFFF8FAFC);
const Color _kHeaderGradientEnd = Color(0xFF0D47A1);
const Color _kCard = Colors.white;
const Color _kBorder = Color(0xFFE5E7EB);
const Color _kTextSub = Color(0xFF6B7280);

class MembershipPage extends StatefulWidget {
  final int dayungUnitId;

  const MembershipPage({super.key, required this.dayungUnitId});

  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  final sb = Supabase.instance.client;
  bool _loading = true;
  String? _loadError;
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _filteredPayments = [];
  bool _updating = false;
  String _statusFilter = 'all';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchPayments();
    _searchController.addListener(_filterPayments);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterPayments);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchPayments() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rows = await sb
          .from('payments')
          .select(
            'id, user_id, amount, status, created_at, dayung_unit_id, type, users!payments_user_id_fkey(full_name)',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('type', 'membership_payment')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _payments = List<Map<String, dynamic>>.from(rows as List);
        });
        _filterPayments();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
      case 'approved':
        return const Color(0xFF10B981);
      case 'unpaid':
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'rejected':
      case 'failed':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) {
      return 'No date';
    }
    try {
      // Parse the incoming timestamp and normalize to UTC, then convert to
      // Philippines Time (UTC+8) for display.
      final parsed = DateTime.parse(value).toUtc();
      final ph = parsed.add(const Duration(hours: 8));
      final formatter = DateFormat('MMM d, yyyy • h:mm a');
      return formatter.format(ph);
    } catch (e) {
      // If parsing fails, just return the original value.
      return value;
    }
  }

  String _formatAmount(dynamic value) {
    final amount = double.tryParse(value?.toString() ?? '') ?? 0;
    return NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    ).format(amount);
  }

  Future<void> _updatePaymentStatus(Map<String, dynamic> payment) async {
    final currentUserId = sb.auth.currentUser?.id;
    if (currentUserId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No logged-in user found')),
        );
      }
      return;
    }

    final paymentId = payment['id']?.toString();
    final recipientId = payment['user_id']?.toString();
    if (paymentId == null ||
        paymentId.isEmpty ||
        recipientId == null ||
        recipientId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment or member information is missing.'),
          ),
        );
      }
      return;
    }

    setState(() => _updating = true);
    var paymentUpdated = false;
    try {
      final unitRow = await sb
          .from('dayung_units')
          .select('name')
          .eq('id', widget.dayungUnitId)
          .maybeSingle();
      final dayungName = unitRow?['name']?.toString().trim();
      if (dayungName == null || dayungName.isEmpty) {
        throw StateError('The dayung name could not be found.');
      }

      final paidAt = DateTime.now().toUtc().toIso8601String();
      await sb
          .from('payments')
          .update({
            'status': 'paid',
            'collected_by': currentUserId,
            'paid_at': paidAt,
            'iscollectedbytreasurer': true,
            'iscollectedbytreasurer_date': paidAt,
          })
          .eq('id', paymentId);
      paymentUpdated = true;

      await sb.from('notifications').insert({
        'recipient_id': recipientId,
        'sender_id': currentUserId,
        'dayung_unit_id': widget.dayungUnitId,
        'type': 'announcement',
        'title': 'Membership Application Approved',
        'body':
            'You are now officially a member of $dayungName, and your membership fee payment has been confirmed.',
        'announcement_id': null,
        'read_at': null,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (mounted) {
        await _fetchPayments();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              paymentUpdated
                  ? 'Payment was marked as paid, but the notification could not be saved: $e'
                  : 'Could not mark payment as paid: $e',
            ),
          ),
        );
        if (paymentUpdated) {
          await _fetchPayments();
        }
      }
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  Future<void> _confirmMarkPaid(Map<String, dynamic> payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Payment'),
          content: const Text(
            'Are you sure you want to mark this payment as paid?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _updatePaymentStatus(payment);
    }
  }

  void _filterPayments() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredPayments = _payments.where((payment) {
        final status = payment['status']?.toString().toLowerCase() ?? '';
        final matchesStatus = switch (_statusFilter) {
          'paid' => status == 'paid' || status == 'approved',
          'unpaid' => status != 'paid' && status != 'approved',
          _ => true,
        };

        if (!matchesStatus) {
          return false;
        }

        if (query.isEmpty) {
          return true;
        }

        final userData = payment['users'] as Map<String, dynamic>?;
        final fullName = userData?['full_name']?.toString().toLowerCase() ?? '';
        return fullName.contains(query);
      }).toList();
    });
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _statusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _statusFilter = value);
        _filterPayments();
      },
      selectedColor: const Color(0xFF0D47A1).withValues(alpha: 0.12),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF0D47A1) : const Color(0xFF475569),
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(
        color: isSelected ? const Color(0xFF0D47A1) : const Color(0xFFE2E8F0),
      ),
      backgroundColor: Colors.white,
    );
  }

  Widget _buildFiltersAndSearch() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final searchField = TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search members',
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Color(0xFF64748B),
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.clear_rounded),
                    ),
              filled: true,
              fillColor: const Color(0xFFF6F7FB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          );
          final filters = Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _buildFilterChip('All', 'all'),
              _buildFilterChip('Paid', 'paid'),
              _buildFilterChip('Unpaid', 'unpaid'),
            ],
          );
          final count = Text(
            _loading ? 'Loading' : '${_filteredPayments.length} shown',
            style: const TextStyle(
              color: _kTextSub,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          );

          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                searchField,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: filters),
                    count,
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 12),
              filters,
              const SizedBox(width: 10),
              count,
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPageBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: _kHeaderGradientEnd,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF1E40AF),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        child: IconButton(
                          tooltip: 'Back',
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 21,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Membership Payments',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  children: [
                    _buildFiltersAndSearch(),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _loading
                          ? const DayungPageSkeleton(
                              layout: DayungSkeletonLayout.list,
                              padding: EdgeInsets.all(16),
                            )
                          : _buildPaymentList(),
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

  Widget _buildPaymentList() {
    return RefreshIndicator(
      onRefresh: _fetchPayments,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          if (_loadError != null)
            _buildPaymentError()
          else if (_payments.isEmpty)
            _buildEmptyState('No membership payments yet')
          else if (_filteredPayments.isEmpty)
            _buildEmptyState('No matching payments', showClearAction: true)
          else
            RecordDataTable(
              minWidth: 700,
              columnSpacing: 20,
              horizontalMargin: 16,
              headingRowHeight: 48,
              dataRowMinHeight: 56,
              dataRowMaxHeight: 72,
              showCheckboxColumn: false,
              columns: const [
                DataColumn(label: Text('Member')),
                DataColumn(label: Text('Amount')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Action')),
              ],
              rows: _filteredPayments.map((payment) {
                final userData = payment['users'] as Map<String, dynamic>?;
                final fullName =
                    userData?['full_name']?.toString() ?? 'Unknown user';
                final status = payment['status']?.toString() ?? 'unknown';
                final isPaid = [
                  'paid',
                  'approved',
                ].contains(status.toLowerCase());
                final createdAt = payment['created_at']?.toString();
                final statusColor = _getStatusColor(status);
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        fullName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(
                      Text(
                        _formatAmount(payment['amount']),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    DataCell(Text(_formatDate(createdAt))),
                    DataCell(
                      isPaid
                          ? const Tooltip(
                              message: 'Payment received',
                              child: Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF10B981),
                              ),
                            )
                          : FilledButton.icon(
                              onPressed: _updating
                                  ? null
                                  : () => _confirmMarkPaid(payment),
                              icon: const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 18,
                              ),
                              label: const Text('Mark paid'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                minimumSize: const Size(0, 40),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                    ),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message, {bool showClearAction = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 36, color: _kTextSub),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              color: _kTextSub,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (showClearAction)
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() => _statusFilter = 'all');
                _filterPayments();
              },
              icon: const Icon(Icons.clear_rounded),
              label: const Text('Clear filters'),
            ),
        ],
      ),
    );
  }

  Widget _buildPaymentError() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Could not load membership payments',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Error details'),
            children: [SelectableText(_loadError ?? '')],
          ),
          OutlinedButton.icon(
            onPressed: _fetchPayments,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
