import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);

class CollectCashPage extends StatefulWidget {
  final int dayungUnitId;
  const CollectCashPage({super.key, required this.dayungUnitId});

  @override
  State<CollectCashPage> createState() => _CollectCashPageState();
}

class _CollectCashPageState extends State<CollectCashPage> {
  final sb = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _pendingPayments = [];
  Map<String, Map<String, dynamic>> _members = {}; // user_id -> user info
  Map<int, String> _deceasedNames = {}; // death_notice_id -> name

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 1. Get all pending payments for this dayung
      final paymentsRes = await sb
          .from('payments')
          .select('id, user_id, amount, death_notice_id, status')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'pending');
      final payments = List<Map<String, dynamic>>.from(paymentsRes);

      // 2. Get all user_ids and death_notice_ids
      final userIds = payments.map((p) => p['user_id']).toSet().toList();
      final noticeIds = payments
          .map((p) => p['death_notice_id'])
          .toSet()
          .toList();

      // 3. Fetch member info
      Map<String, Map<String, dynamic>> members = {};
      if (userIds.isNotEmpty) {
        final usersRes = await sb
            .from('users')
            .select('id, full_name')
            .inFilter('id', userIds);
        for (final u in usersRes) {
          members[u['id']] = u;
        }
      }

      // 4. Fetch deceased names
      Map<int, String> deceasedNames = {};
      if (noticeIds.isNotEmpty) {
        final noticesRes = await sb
            .from('death_notices')
            .select('id, name')
            .inFilter('id', noticeIds);
        for (final n in noticesRes) {
          deceasedNames[n['id'] as int] = n['name']?.toString() ?? '';
        }
      }

      setState(() {
        _pendingPayments = payments;
        _members = members;
        _deceasedNames = deceasedNames;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: kAccent),
        title: const Text(
          'Collect Cash Payments',
          style: TextStyle(
            color: kAccent,
            fontWeight: FontWeight.w800,
            fontFamily: 'Montserrat',
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 18),
              ),
            )
          : _pendingPayments.isEmpty
          ? const Center(
              child: Text(
                'All members are paid up!',
                style: TextStyle(
                  fontSize: 22,
                  color: kSubText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(18),
              itemCount: _pendingPayments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, i) {
                final row = _pendingPayments[i];
                final userId = row['user_id'];
                final member = _members[userId];
                final memberName = member?['full_name'] ?? 'Member';
                final deceasedName =
                    _deceasedNames[row['death_notice_id']] ?? 'Deceased';
                final amount = (row['amount'] is num)
                    ? (row['amount'] as num).toDouble()
                    : double.tryParse('${row['amount']}') ?? 0.0;

                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kAccent.withOpacity(0.10)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        memberName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: kText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Para kay $deceasedName',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: kSubText,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Halaga: ₱ ${amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: kAccent,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.payments, size: 22),
                          label: const Text(
                            'Record Cash Payment',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => _confirmCashPayment(row),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _confirmCashPayment(Map<String, dynamic> paymentRow) async {
    final amount = (paymentRow['amount'] is num)
        ? (paymentRow['amount'] as num).toDouble()
        : double.tryParse('${paymentRow['amount']}') ?? 0.0;
    final memberName =
        _members[paymentRow['user_id']]?['full_name'] ?? 'Member';
    final deceasedName =
        _deceasedNames[paymentRow['death_notice_id']] ?? 'Deceased';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Cash Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tanggap mo na ba ang bayad ni\n'
              '$memberName\n'
              'para kay $deceasedName\n'
              'na ₱ ${amount.toStringAsFixed(2)}?',
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          ElevatedButton(
            child: const Text('Yes, Record Payment'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _recordPayment(paymentRow['id']);
    }
  }

  Future<void> _recordPayment(dynamic paymentId) async {
    try {
      final collectorId = sb.auth.currentUser?.id;
      if (collectorId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not logged in as collector.')),
        );
        return;
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final res = await sb
          .from('payments')
          .update({
            'status': 'paid',
            'paid_at': now,
            'collected_by': collectorId,
          })
          .eq('id', paymentId)
          .select();

      if (res == null || res.isEmpty) {
        throw Exception('Update failed or not permitted.');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cash payment recorded!')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to record payment: $e')));
    }
  }
}
