import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);

class PaymentMethodPage extends StatefulWidget {
  final int? dayungUnitId; // selected dayung
  const PaymentMethodPage({super.key, this.dayungUnitId});

  @override
  State<PaymentMethodPage> createState() => _PaymentMethodPageState();
}

class _PaymentMethodPageState extends State<PaymentMethodPage> {
  final sb = Supabase.instance.client;
  Map<int, String> _deceasedNames = {};
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
        (sum, r) =>
            sum +
            ((r['amount'] is num) ? (r['amount'] as num).toDouble() : 0.0),
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

      // 3) Fetch deceased names for all death_notice_id in rows
      final noticeIds = rows.map((r) => r['death_notice_id']).toSet().toList();
      Map<int, String> deceasedNames = {};
      if (noticeIds.isNotEmpty) {
        final notices = await sb
            .from('death_notices')
            .select('id, name')
            .inFilter('id', noticeIds);
        for (final n in notices) {
          deceasedNames[n['id'] as int] = n['name']?.toString() ?? '';
        }
      }

      setState(() {
        _pendingRows = rows;
        _totalPending = total;
        _collectors = collectors;
        _selectedCollectorId = collectors.isNotEmpty
            ? (collectors.first['id']?.toString())
            : null;
        _deceasedNames = deceasedNames; // <-- add this
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
    final amountCtrl = TextEditingController(
      text: _totalPending.toStringAsFixed(2),
    );
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
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
                    final entered =
                        double.tryParse(amountCtrl.text.replaceAll(',', '')) ??
                        0;
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
                          content: Text(
                            'Amount must equal total due (₱ ${due.toStringAsFixed(2)}).',
                          ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update payments: $e')));
    }
  }

  Future<void> _openCashModalForPayment(Map<String, dynamic> paymentRow) async {
    final amount = (paymentRow['amount'] is num)
        ? (paymentRow['amount'] as num).toDouble()
        : double.tryParse('${paymentRow['amount']}') ?? 0.0;
    final amountCtrl = TextEditingController(text: amount.toStringAsFixed(2));
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
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
                    final entered =
                        double.tryParse(amountCtrl.text.replaceAll(',', '')) ??
                        0;
                    if ((entered - amount).abs() > 0.009) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Amount must equal ₱ ${amount.toStringAsFixed(2)}.',
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.of(context).pop(); // close sheet
                    await _markPaymentAsPaid(paymentRow['id']);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _markPaymentAsPaid(dynamic paymentId) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await sb
          .from('payments')
          .update({'status': 'paid', 'paid_at': now})
          .eq('id', paymentId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment recorded. Thank you!')),
      );
      _load(); // reload payments
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update payment: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update payment: $e')));
    }
  }

  Future<void> _openGCashModalForPayment(
    Map<String, dynamic> paymentRow,
  ) async {
    final amount = (paymentRow['amount'] is num)
        ? (paymentRow['amount'] as num).toDouble()
        : double.tryParse('${paymentRow['amount']}') ?? 0.0;
    final receiptCtrl = TextEditingController();

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
                'GCash Payment',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text('Amount: ₱ ${amount.toStringAsFixed(2)}'),
              const SizedBox(height: 12),
              // Show GCash QR or instructions here
              const Text('Send payment to GCash number: 09XXXXXXXXX'),
              const SizedBox(height: 12),
              TextFormField(
                controller: receiptCtrl,
                decoration: const InputDecoration(
                  labelText: 'GCash Reference No. or Upload Screenshot',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.upload),
                  label: const Text('Submit Proof'),
                  onPressed: () async {
                    // Save as pending_verification
                    Navigator.of(context).pop();
                    await _markPaymentAsGCashPending(
                      paymentRow['id'],
                      receiptCtrl.text,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _markPaymentAsGCashPending(dynamic paymentId, String ref) async {
    try {
      await sb
          .from('payments')
          .update({'status': 'pending_verification', 'gcash_ref': ref})
          .eq('id', paymentId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GCash payment submitted for verification.'),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit GCash payment: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Dayung',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      fontFamily: 'Montserrat',
                      color: kAccent,
                    ),
                  ),
                  Row(
                    children: const [
                      Icon(
                        Icons.notifications_none,
                        color: Colors.orange,
                        size: 36,
                      ),
                      SizedBox(width: 20),
                      CircleAvatar(
                        backgroundColor: kAccent,
                        radius: 20,
                        child: Icon(
                          Icons.account_circle,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(thickness: 1.5, color: Colors.grey),
            // Back + Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      size: 36,
                      color: kAccent,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Payment Method',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Montserrat',
                      color: kText,
                    ),
                  ),
                ],
              ),
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 20),
                  ),
                ),
              )
            else
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      // Amount due summary
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: kAccent.withOpacity(0.15)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total Due',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 20,
                                fontFamily: 'Montserrat',
                                color: kSubText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '₱ ${_totalPending.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 36,
                                fontFamily: 'Montserrat',
                                color: kAccent,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _pendingRows.isEmpty
                            ? Center(
                                child: Text(
                                  'Wala kang dapat bayaran ngayon.',
                                  style: TextStyle(
                                    fontSize: 22,
                                    color: kSubText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _pendingRows.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 16),
                                itemBuilder: (context, i) {
                                  final row = _pendingRows[i];
                                  final amount = (row['amount'] is num)
                                      ? (row['amount'] as num).toDouble()
                                      : double.tryParse('${row['amount']}') ??
                                            0.0;
                                  final deathNoticeId = row['death_notice_id'];
                                  final deceasedLabel =
                                      _deceasedNames[deathNoticeId] != null &&
                                          _deceasedNames[deathNoticeId]!
                                              .isNotEmpty
                                      ? 'Para kay ${_deceasedNames[deathNoticeId]}'
                                      : 'Para kay Deceased #$deathNoticeId'; // Replace with actual name if available

                                  return Container(
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: kAccent.withOpacity(0.10),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(.03),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          deceasedLabel,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: kText,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Halaga: ₱ ${amount.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            color: kAccent,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            ElevatedButton.icon(
                                              icon: const Icon(
                                                Icons.payments,
                                                size: 22,
                                              ),
                                              label: const Text(
                                                'Bayad Cash',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: kAccent,
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 18,
                                                      vertical: 12,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                              onPressed: () =>
                                                  _openCashModalForPayment(row),
                                            ),
                                            const SizedBox(width: 12),
                                            ElevatedButton.icon(
                                              icon: const Icon(
                                                Icons.qr_code,
                                                size: 22,
                                              ),
                                              label: const Text(
                                                'Bayad GCash',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.purple,
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 18,
                                                      vertical: 12,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                              onPressed: () =>
                                                  _openGCashModalForPayment(
                                                    row,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
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
