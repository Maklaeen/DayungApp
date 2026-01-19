// filepath: lib/Collector/collect_cash.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'set_amounts_tab.dart';

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
    _loadPayments();
  }

  Future<void> _loadSetAmounts() async {
    try {
      final res = await sb
          .from('set_amount')
          .select('id, userdeceased, amount')
          .eq('dayung_unit_id', widget.dayungUnitId);
      setState(() {
        _setAmounts = List<Map<String, dynamic>>.from(res);
      });
    } catch (e) {}
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
    } catch (e) {}
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
    final width = MediaQuery.of(context).size.width;
    final bool isMobile = width < 600;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Curved Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 36, 20, 28),
              decoration: const BoxDecoration(
                color: kAccent,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: kAccent,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.chevron_left,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Icon(
                    Icons.payments_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Collect Cash Payments',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFamily: 'Montserrat',
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: kAccent),
                    )
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 18),
                      ),
                    )
                  : _selectedMember == null
                  ? _approvedMembers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: kSubText,
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'No approved members assigned.',
                                  style: TextStyle(
                                    fontSize: 22,
                                    color: kSubText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(18),
                            child: ListView(
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(
                                    bottom: 12.0,
                                    left: 4.0,
                                  ),
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
                                ..._approvedMembers.map((member) {
                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    elevation: 2,
                                    color: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(
                                        color: kAccent.withOpacity(0.10),
                                      ),
                                    ),
                                    child: ListTile(
                                      title: Text(
                                        member['full_name'] ?? 'Member',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: kText,
                                        ),
                                      ),
                                      trailing: const Icon(
                                        Icons.arrow_forward_ios,
                                        color: kAccent,
                                      ),
                                      onTap: () {
                                        final userId =
                                            member['id'] ?? member['user_id'];
                                        setState(() {
                                          _selectedMember = member;
                                          _selectedSetAmountIndex = null;
                                        });
                                      },
                                    ),
                                  );
                                }),
                              ],
                            ),
                          )
                  : Card(
                      margin: const EdgeInsets.all(18),
                      elevation: 3,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SetAmountsTab(
                          setAmounts: _setAmounts,
                          selectedMember: _selectedMember,
                          selectedSetAmountIndex: _selectedSetAmountIndex,
                          onSetAmount: (index, amount, setAmountId) async {
                            final userId =
                                _selectedMember?['id'] ??
                                _selectedMember?['user_id'];
                            if (userId != null) {
                              await _savePayment(userId, amount, setAmountId);
                            }
                            setState(() {
                              _selectedMember = null;
                              _selectedSetAmountIndex = null;
                            });
                          },
                          onSavePayment: (user) async {
                            final userId = user['id'] ?? user['user_id'];
                            if (userId != null) {
                              await _savePayment(userId.toString(), 0.0, '');
                            }
                          },
                          users: _approvedMembers,
                          payments: _payments
                              .where(
                                (p) => p['user_id'] == _selectedMember?['id'],
                              )
                              .toList(),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
