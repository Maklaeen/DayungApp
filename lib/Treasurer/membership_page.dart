import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MembershipPage extends StatefulWidget {
  final int dayungUnitId;

  const MembershipPage({
    super.key,
    required this.dayungUnitId,
  });

  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  final sb = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _filteredPayments = [];
  bool _updating = false;
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
    setState(() => _loading = true);
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
          _filteredPayments = List<Map<String, dynamic>>.from(_payments);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
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
    return value;
  }

  Future<void> _updatePaymentStatus(String paymentId) async {
    final currentUserId = sb.auth.currentUser?.id;
    if (currentUserId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No logged-in user found')),
        );
      }
      return;
    }

    setState(() => _updating = true);
    try {
      final paidAt = DateTime.now().toUtc().toIso8601String();
      await sb.from('payments').update({
        'status': 'paid',
        'collected_by': currentUserId,
        'paid_at': paidAt,
      }).eq('id', paymentId);

      if (mounted) {
        await _fetchPayments();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment marked as paid')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  void _filterPayments() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredPayments = List<Map<String, dynamic>>.from(_payments);
      } else {
        _filteredPayments = _payments.where((payment) {
          final userData = payment['users'] as Map<String, dynamic>?;
          final fullName = userData?['full_name']?.toString().toLowerCase() ?? '';
          return fullName.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Membership Payments',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            fontFamily: 'Montserrat',
          ),
        ),
        centerTitle: false,
        backgroundColor: const Color(0xFF1E40AF),
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())  
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by name',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                Expanded(
                  child: _payments.isEmpty
                      ? const Center(
                          child: Text(
                            'No membership payments found',
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        )
                      : _filteredPayments.isEmpty
                          ? const Center(
                              child: Text(
                                'No results found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchPayments,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                itemCount: _filteredPayments.length,
                                itemBuilder: (context, index) {
                                  final payment = _filteredPayments[index];
                      final userData = payment['users'] as Map<String, dynamic>?;
                      final fullName = userData?['full_name']?.toString() ?? 'Unknown user';
                      final amount = payment['amount']?.toString() ?? '0';
                      final status = payment['status']?.toString() ?? 'unknown';
                      final createdAt = payment['created_at']?.toString() ?? 'No date';
                      final statusColor = _getStatusColor(status);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: statusColor.withOpacity(0.15),
                                    child: Icon(
                                      Icons.account_balance_wallet,
                                      color: statusColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          fullName,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: statusColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Divider(height: 1, color: Colors.grey[200]),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _infoRow(
                                      label: 'Amount',
                                      value: '₱$amount',
                                    ),
                                  ),
                                  Expanded(
                                    child: _infoRow(
                                      label: 'Created',
                                      value: _formatDate(createdAt),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _updating || status.toLowerCase() == 'paid'
                                      ? null
                                      : () => _updatePaymentStatus(payment['id'].toString()),
                                  icon: Icon(
                                    status.toLowerCase() == 'paid'
                                        ? Icons.check_circle
                                        : Icons.check_circle_outline,
                                  ),
                                  label: Text(
                                    status.toLowerCase() == 'paid' ? 'Paid' : 'Mark as Paid',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1E40AF),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                                },
                              ),
                            ),
                ),
              ],
            ),
    );
  }

  Widget _infoRow({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
