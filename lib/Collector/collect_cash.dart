import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'set_amounts_tab.dart'; // <-- Add this import

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
  List<Map<String, dynamic>> _approvedMembers = [];
  List<Map<String, dynamic>> _setAmounts = [];
  List<Map<String, dynamic>> _payments = [];
  Map<String, dynamic>? _selectedMember;
  int? _selectedSetAmountIndex;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSetAmounts();
    _loadPayments(); // <-- Add this
  }

  Future<void> _loadSetAmounts() async {
    try {
      final res = await sb
          .from('set_amount')
          .select('id, userdeceased, amount') // <-- include id
          .eq('dayung_unit_id', widget.dayungUnitId);
      setState(() {
        _setAmounts = List<Map<String, dynamic>>.from(res);
      });
    } catch (e) {
      // Optionally handle error
    }
  }

  Future<void> _loadPayments() async {
    try {
      final res = await sb
          .from('payments')
          .select('*')
          .eq('dayung_unit_id', widget.dayungUnitId);
      setState(() {
        _payments = List<Map<String, dynamic>>.from(res);
      });
    } catch (e) {
      // Optionally handle error
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final appsRes = await sb
          .from('applications')
          .select('user_id')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'approved');
      final userIds = List<Map<String, dynamic>>.from(
        appsRes,
      ).map((a) => a['user_id']).toList();

      List<Map<String, dynamic>> members = [];
      if (userIds.isNotEmpty) {
        final usersRes = await sb
            .from('users')
            .select('id, full_name')
            .inFilter('id', userIds);
        members = List<Map<String, dynamic>>.from(usersRes);
      }

      setState(() {
        _approvedMembers = members;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load: $e';
      });
    }
  }

  // Update _savePayment to accept setAmountId
  Future<void> _savePayment(
    String userId,
    double amount,
    String setAmountId,
  ) async {
    try {
      final collectorId = sb.auth.currentUser?.id;
      if (collectorId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not logged in as collector.')),
        );
        return;
      }

      // Get set_amount row for userdeceased
      final setAmount = _setAmounts.firstWhere(
        (a) => a['id'].toString() == setAmountId,
        orElse: () => <String, dynamic>{},
      );

      final now = DateTime.now().toUtc().toIso8601String();
      final paymentData = {
        'userdeceased': setAmount['userdeceased'],
        'user_id': userId,
        'amount': amount,
        'datepaidamount': now,
        'dayung_unit_id': widget.dayungUnitId,
        'status': 'paid',
        'paid_at': now,
        'collected_by': collectorId,
      };

      await sb.from('payments').insert(paymentData);

      // Reload payments so isPaid will be true in debug
      await _loadPayments();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment saved successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save payment: $e')));
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
          : _selectedMember == null
          ? _approvedMembers.isEmpty
                ? const Center(
                    child: Text(
                      'No approved members assigned.',
                      style: TextStyle(
                        fontSize: 22,
                        color: kSubText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12.0, left: 4.0),
                          child: Text(
                            'MEMBERS',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: kAccent,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            itemCount: _approvedMembers.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 14),
                            itemBuilder: (context, i) {
                              final member = _approvedMembers[i];
                              return ListTile(
                                title: Text(
                                  member['full_name'] ?? 'Member',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: kText,
                                  ),
                                ),
                                tileColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                    color: kAccent.withOpacity(0.10),
                                  ),
                                ),
                                onTap: () {
                                  final userId =
                                      member['id'] ?? member['user_id'];
                                  debugPrint('MEMBERS TAPPED: $userId');
                                  setState(() {
                                    _selectedMember = member;
                                    _selectedSetAmountIndex = null;
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  )
          : SetAmountsTab(
              setAmounts: _setAmounts,
              selectedMember: _selectedMember,
              selectedSetAmountIndex: _selectedSetAmountIndex,
              onSetAmount: (index, amount, setAmountId) async {
                final userId =
                    _selectedMember?['id'] ?? _selectedMember?['user_id'];
                if (userId != null) {
                  await _savePayment(userId, amount, setAmountId);
                }
                setState(() {
                  _selectedMember = null;
                  _selectedSetAmountIndex = null;
                });
              },
              onSavePayment: (userId, amount) async {
                await _savePayment(userId, amount, '');
              },
              users: _approvedMembers,
              paymentList: _payments
                  .where((p) => p['user_id'] == _selectedMember?['id'])
                  .toList(), // <-- Use correct parameter name
            ),
    );
  }
}
