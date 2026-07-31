import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _kPageBg = Color(0xFFF8FAFC);
const Color _kHeaderGradientStart = Color(0xFF083366);
const Color _kHeaderGradientEnd = Color(0xFF0D47A1);
const Color _kCard = Colors.white;
const Color _kBorder = Color(0xFFE5E7EB);

class PaymentMember {
  final String id;
  final String userId;
  final String fullName;
  final String status;
  final double amount;
  final String? date;

  const PaymentMember({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.status,
    required this.amount,
    this.date,
  });
}

typedef PaymentMemberLoader =
    Future<List<PaymentMember>> Function(String status);

class PaidUnpaidMembersPage extends StatefulWidget {
  final int dayungUnitId;
  final int initialTab;
  final PaymentMemberLoader? memberLoader;

  const PaidUnpaidMembersPage({
    super.key,
    required this.dayungUnitId,
    this.initialTab = 0,
    this.memberLoader,
  });

  @override
  State<PaidUnpaidMembersPage> createState() => _PaidUnpaidMembersPageState();
}

class _PaidUnpaidMembersPageState extends State<PaidUnpaidMembersPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  String? _error;
  List<PaymentMember> _paidMembers = [];
  List<PaymentMember> _unpaidMembers = [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _loadMembers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  SupabaseClient? _getClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (widget.memberLoader != null) {
        final paid = await widget.memberLoader!('paid');
        final unpaid = await widget.memberLoader!('pending');
        if (!mounted) return;
        setState(() {
          _paidMembers = paid;
          _unpaidMembers = unpaid;
          _loading = false;
        });
        return;
      }

      final client = _getClient();
      if (client == null) {
        if (!mounted) return;
        setState(() {
          _error = 'Supabase is not initialized.';
          _loading = false;
        });
        return;
      }

      final rows = await client
          .from('payments')
          .select(
            'id, user_id, amount, status, paid_at, created_at, users!payments_user_id_fkey(full_name)',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .inFilter('status', ['paid', 'pending', 'unpaid'])
          .order('created_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(rows);
      final paid = <PaymentMember>[];
      final unpaid = <PaymentMember>[];

      for (final row in list) {
        final status = (row['status'] ?? '').toString();
        final userName =
            ((row['users'] as Map?)?['full_name']?.toString() ?? 'Member')
                .trim();
        final member = PaymentMember(
          id: (row['id'] ?? '').toString(),
          userId: (row['user_id'] ?? '').toString(),
          fullName: userName.isEmpty ? 'Member' : userName,
          status: status,
          amount: (row['amount'] is num)
              ? (row['amount'] as num).toDouble()
              : double.tryParse('${row['amount']}') ?? 0,
          date: (row['paid_at'] ?? row['created_at'])?.toString(),
        );

        if (status == 'paid') {
          paid.add(member);
        } else {
          unpaid.add(member);
        }
      }

      if (!mounted) return;
      setState(() {
        _paidMembers = paid;
        _unpaidMembers = unpaid;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load members: $e';
        _loading = false;
      });
    }
  }

  List<PaymentMember> _filteredMembers(List<PaymentMember> members) {
    if (_search.trim().isEmpty) return members;
    final query = _search.trim().toLowerCase();
    return members.where((member) {
      return member.fullName.toLowerCase().contains(query) ||
          member.userId.toLowerCase().contains(query) ||
          member.status.toLowerCase().contains(query);
    }).toList();
  }

  Widget _buildMemberList(List<PaymentMember> members) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      );
    }

    final filtered = _filteredMembers(members);
    if (filtered.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_off_rounded, size: 44, color: Color(0xFF94A3B8)),
            SizedBox(height: 8),
            Text(
              'No members found.',
              style: TextStyle(color: Color(0xFF4B5563), fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final member = filtered[index];
        final isPaid = member.status.toLowerCase() == 'paid';
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor:
                    (isPaid ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                        .withValues(alpha: 0.12),
                child: Icon(
                  Icons.person_rounded,
                  color: isPaid
                      ? const Color(0xFF10B981)
                      : const Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${member.userId}',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                      ),
                    ),
                    if (member.date != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Date: ${member.date}',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (isPaid
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFF59E0B))
                              .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '₱${member.amount.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: isPaid
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    member.status.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: TextField(
        decoration: const InputDecoration(
          hintText: 'Search members',
          border: InputBorder.none,
          prefixIcon: Icon(Icons.search_rounded, color: Color(0xFF64748B)),
        ),
        onChanged: (value) {
          setState(() {
            _search = value;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paidCount = _paidMembers.length;
    final unpaidCount = _unpaidMembers.length;

    return Scaffold(
      backgroundColor: _kPageBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_kHeaderGradientStart, _kHeaderGradientEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x22083366),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_left_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            // Text(
                            //   'Payments',
                            //   style: TextStyle(
                            //     color: Colors.white70,
                            //     fontSize: 13,
                            //     fontWeight: FontWeight.w700,
                            //   ),
                            // ),
                            // SizedBox(height: 6),
                            Text(
                              'Paid & Unpaid Members',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // IconButton(
                      //   icon: const Icon(Icons.close, color: Colors.white),
                      //   onPressed: () => Navigator.of(context).maybePop(),
                      // ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _buildSummaryCard(
                        title: 'Paid',
                        value: '$paidCount',
                        color: const Color(0xFF10B981),
                      ),
                      const SizedBox(width: 10),
                      _buildSummaryCard(
                        title: 'Unpaid',
                        value: '$unpaidCount',
                        color: const Color(0xFFF59E0B),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: _kPageBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _kBorder),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              labelColor: const Color(0xFF0D47A1),
                              unselectedLabelColor: const Color(0xFF64748B),
                              indicator: BoxDecoration(
                                color: const Color(
                                  0xFF0D47A1,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              tabs: const [
                                Tab(text: 'Paid'),
                                Tab(text: 'Unpaid'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildSearchField(),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildMemberList(_paidMembers),
                          _buildMemberList(_unpaidMembers),
                        ],
                      ),
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
}
