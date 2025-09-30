import 'package:capstone_app/Members/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentMethodPage extends StatefulWidget {
  final int? dayungUnitId; // selected dayung
  const PaymentMethodPage({super.key, this.dayungUnitId});

  @override
  State<PaymentMethodPage> createState() => _PaymentMethodPageState();
}

class _PaymentMethodPageState extends State<PaymentMethodPage> {
  final sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  double _totalPending = 0;
  List<Map<String, dynamic>> _pendingRows = [];
  List<Map<String, dynamic>> _collectors = [];
  String? _selectedCollectorId;

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
      final uid = sb.auth.currentUser?.id;
      final dId = widget.dayungUnitId;
      if (uid == null || dId == null) {
        setState(() {
          _loading = false;
          _error = 'Missing user or dayung selection.';
        });
        return;
      }

      // 1) Fetch pending payments for this user in this dayung
      final res = await sb
          .from('payments')
          .select('id, amount, death_notice_id, status')
          .eq('user_id', uid)
          .eq('dayung_unit_id', dId)
          .eq('status', 'pending');

      final rows = List<Map<String, dynamic>>.from(res);
      final total = rows.fold<double>(
        0,
        (sum, r) => sum + ((r['amount'] is num) ? (r['amount'] as num).toDouble() : 0.0),
      );

      // 2) Fetch collectors in this dayung (role = 'collector')
      List<Map<String, dynamic>> collectors = [];
      try {
        final coll = await sb
            .from('users')
            .select('id, full_name, role')
            .eq('dayung_unit_id', dId)
            .eq('role', 'collector');
        collectors = List<Map<String, dynamic>>.from(coll);
      } catch (_) {
        collectors = [];
      }

      setState(() {
        _pendingRows = rows;
        _totalPending = total;
        _collectors = collectors;
        _selectedCollectorId = collectors.isNotEmpty ? (collectors.first['id']?.toString()) : null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load payments: $e';
      });
    }
  }

  Future<void> _openCashModal() async {
    if (_pendingRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pending payments to pay.')),
      );
      return;
    }
    final amountCtrl = TextEditingController(text: _totalPending.toStringAsFixed(2));
    String? collectorId = _selectedCollectorId;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        final viewInsets = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, viewInsets + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Cash Payment',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: collectorId,
                items: _collectors
                    .map(
                      (c) => DropdownMenuItem<String>(
                        value: (c['id'] ?? '').toString(),
                        child: Text(
                          (c['full_name'] ?? 'Collector').toString(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => collectorId = v,
                decoration: const InputDecoration(
                  labelText: 'Collector',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  hintText: 'Enter amount received',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Confirm Cash Payment'),
                  onPressed: () async {
                    final entered = double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
                    final due = _totalPending;

                    if (entered <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter a valid amount.')),
                      );
                      return;
                    }
                    // For now, require full payment of pending balance
                    if ((entered - due).abs() > 0.009) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Amount must equal total due (₱ ${due.toStringAsFixed(2)}).'),
                        ),
                      );
                      return;
                    }

                    Navigator.of(context).pop(); // close sheet
                    await _markAllPendingAsPaid();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _markAllPendingAsPaid() async {
    final ids = _pendingRows.map<String>((r) => (r['id']).toString()).toList();
    if (ids.isEmpty) return;

    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await sb
          .from('payments')
          .update({'status': 'paid', 'paid_at': now})
          .inFilter('id', ids);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment recorded. Thank you!')),
      );
      Navigator.pop(context); // back to Member Dashboard
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update payments: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update payments: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFEFFFF),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Dayung',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      fontFamily: 'Montserrat',
                      color: Colors.black,
                    ),
                  ),
                  Row(
                    children: const [
                      Icon(Icons.notifications_none, color: Colors.orange, size: 32),
                      SizedBox(width: 16),
                      CircleAvatar(
                        backgroundColor: Colors.blue,
                        radius: 16,
                        child: Icon(Icons.account_circle, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(thickness: 1.5, color: Colors.grey),
            // Back + Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 32),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Payment Method',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ],
              ),
            ),

            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              )
            else
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // Amount due summary
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F7FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total Due',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                fontFamily: 'Montserrat',
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '₱ ${_totalPending.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 26,
                                fontFamily: 'Montserrat',
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Cash
                      GestureDetector(
                        onTap: _openCashModal,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5EEDC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.brown.shade300),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.money, color: Colors.brown, size: 36),
                              SizedBox(width: 16),
                              Text(
                                'Cash',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Montserrat',
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // GCash placeholder
                      GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('GCash integration coming soon')),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3F3FF),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.blue.shade300),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.account_balance_wallet, color: Colors.blue, size: 36),
                              SizedBox(width: 16),
                              Text(
                                'GCash',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Montserrat',
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
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