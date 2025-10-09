import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kAccent = Color(0xFF3E8E7E);
const Color kPaid = Color(0xFF2E7D32);
const Color kPending = Color(0xFFF57C00);
const Color kCardBg = Color(0xFFF5F8FA);
const Color kText = Color(0xFF1F2937);
const Color kSubtle = Color(0xFF4B5563);

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
  Map<int, dynamic> _deathNotices = {};

  @override
  void initState() {
    super.initState();
    _fetchContributions();
  }

  Future<void> _fetchContributions() async {
    setState(() => _loading = true);
    final sb = Supabase.instance.client;
    try {
      // Fetch all payments for this dayung unit
      final payments = await sb
          .from('payments')
          .select('id, user_id, amount, status, death_notice_id, paid_at')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .order('paid_at', ascending: false);

      // Fetch users
      final userIds = payments.map((p) => p['user_id']).toSet().toList();
      final usersRes = await sb
          .from('users')
          .select('id, full_name')
          .inFilter('id', userIds);
      final usersMap = <String, dynamic>{
        for (var u in usersRes) u['id'].toString(): u['full_name'] ?? 'Unknown',
      };

      // Fetch death notices
      final noticeIds = payments
          .map((p) => p['death_notice_id'])
          .toSet()
          .toList();
      final noticesRes = await sb
          .from('death_notices')
          .select('id, name, date_of_death')
          .inFilter('id', noticeIds);
      final noticesMap = <int, dynamic>{
        for (var n in noticesRes) int.parse(n['id'].toString()): n,
      };

      setState(() {
        _payments = List<Map<String, dynamic>>.from(payments);
        _users = usersMap;
        _deathNotices = noticesMap;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading contributions: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kPrimary,
        title: const Text(
          'Contributions Monitor',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_payments.isEmpty
                ? const Center(
                    child: Text(
                      'No contributions found.',
                      style: TextStyle(fontSize: 18, color: kSubtle),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(18),
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemCount: _payments.length,
                    itemBuilder: (context, i) {
                      final p = _payments[i];
                      final userName = _users[p['user_id']] ?? 'Unknown';
                      final notice = _deathNotices[p['death_notice_id']];
                      final deceased = notice?['name'] ?? 'Unknown';
                      final date = notice?['date_of_death'] ?? '';
                      final paid =
                          (p['status']?.toString().toLowerCase() == 'paid');
                      return Container(
                        decoration: BoxDecoration(
                          color: kCardBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: paid
                                ? kPaid.withOpacity(.25)
                                : kPending.withOpacity(.18),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(.04),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 18,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: paid
                                ? kPaid.withOpacity(.15)
                                : kPending.withOpacity(.15),
                            child: Icon(
                              paid
                                  ? Icons.check_circle
                                  : Icons.hourglass_bottom,
                              color: paid ? kPaid : kPending,
                              size: 30,
                            ),
                            radius: 28,
                          ),
                          title: Text(
                            userName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: kText,
                              fontFamily: 'Montserrat',
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'For: $deceased',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: kSubtle,
                                    fontFamily: 'OpenSans',
                                  ),
                                ),
                                if (date != null && date.toString().isNotEmpty)
                                  Text(
                                    'Date of Death: $date',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: kSubtle,
                                    ),
                                  ),
                                Text(
                                  'Amount: ₱${p['amount']}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: paid ? kPaid : kPending,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: paid
                                  ? kPaid.withOpacity(.13)
                                  : kPending.withOpacity(.13),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              paid ? 'PAID' : 'PENDING',
                              style: TextStyle(
                                color: paid ? kPaid : kPending,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  )),
    );
  }
}
