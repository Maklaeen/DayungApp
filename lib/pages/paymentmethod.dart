import 'package:capstone_app/ui/theme/branding.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);

class PaymentMethodPage extends StatefulWidget {
  final int dayungUnitId;
  const PaymentMethodPage({super.key, required this.dayungUnitId});

  @override
  State<PaymentMethodPage> createState() => _PaymentMethodPageState();
}

class _PaymentMethodPageState extends State<PaymentMethodPage> {
  final sb = Supabase.instance.client;
  Map<int, String> _deceasedNames = {};
  Map<int, Map<String, dynamic>> _noticeMeta = {};
  Map<String, String> _memberNames = {};
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
      if (uid == null) {
        setState(() {
          _loading = false;
          _error = 'Missing user or dayung selection.';
        });
        return;
      }

      // 1) Pending payments for this user and dayung
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

      // 2) Collectors for this dayung (via dayung_collectors, not users.role)
      List<Map<String, dynamic>> collectors = [];
      try {
        final dc = await sb
            .from('dayung_collectors')
            .select('user_id')
            .eq('dayung_unit_id', dId);
        final dcRows = List<Map<String, dynamic>>.from(dc);
        final ids = dcRows
            .map((r) => r['user_id'])
            .where((v) => v != null)
            .toSet()
            .toList();
        if (ids.isNotEmpty) {
          final usersRes = await sb
              .from('users')
              .select('id, full_name')
              .inFilter('id', ids);
          collectors = List<Map<String, dynamic>>.from(usersRes);
        }
      } catch (_) {
        collectors = [];
      }

      // 3) Death notice meta (name, deceased_type, user_id)
      final noticeIds = rows.map((r) => r['death_notice_id']).toSet().toList();
      Map<int, String> deceasedNames = {};
      Map<int, Map<String, dynamic>> noticeMeta = {};
      Map<String, String> memberNames = {};
      if (noticeIds.isNotEmpty) {
        final notices = await sb
            .from('death_notices')
            .select('id, name, deceased_type, user_id')
            .inFilter('id', noticeIds);

        final noticeList = List<Map<String, dynamic>>.from(notices);
        final memberIds = <String>{
          for (final n in noticeList)
            if (n['user_id'] != null) n['user_id'].toString(),
        }.toList();

        for (final n in noticeList) {
          final id = int.parse(n['id'].toString());
          deceasedNames[id] = (n['name'] ?? '').toString();
          noticeMeta[id] = {
            'name': (n['name'] ?? '').toString(),
            'deceased_type': (n['deceased_type'] ?? '').toString(),
            'user_id': n['user_id']?.toString(),
          };
        }

        if (memberIds.isNotEmpty) {
          final usersRes = await sb
              .from('users')
              .select('id, full_name')
              .inFilter('id', memberIds);
          for (final u in List<Map<String, dynamic>>.from(usersRes)) {
            memberNames[u['id'].toString()] = (u['full_name'] ?? '').toString();
          }
        }
      }

      setState(() {
        _pendingRows = rows;
        _totalPending = total;
        _collectors = collectors;
        _selectedCollectorId = collectors.isNotEmpty
            ? (collectors.first['id']?.toString())
            : null;
        _deceasedNames = deceasedNames;
        _noticeMeta = noticeMeta;
        _memberNames = memberNames;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load payments: $e';
      });
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
                initialValue: collectorId,
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
                    if (collectorId == null || collectorId!.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a collector.'),
                        ),
                      );
                      return;
                    }
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
                    Navigator.of(context).pop();
                    await _markPaymentAsPaid(paymentRow['id'], collectorId);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _markPaymentAsPaid(
    dynamic paymentId, [
    String? collectorId,
  ]) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final update = <String, dynamic>{
        'status': 'paid',
        'paid_at': now,
        if (collectorId != null && collectorId.isNotEmpty)
          'collected_by': collectorId,
      };

      await sb.from('payments').update(update).eq('id', paymentId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment recorded. Thank you!')),
      );
      _load();
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
            // Curved Header (copied from deathnotice.dart)
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
                      'Payment Method',
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
            // (Optional) Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: kAccent, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search payment',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 16, color: kText),
                        // onChanged: (q) => setState(() => _search = q),
                      ),
                    ),
                  ],
                ),
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
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red, fontSize: 20),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _pendingRows.isEmpty
                          ? ListView(
                              children: [
                                const SizedBox(height: 120),
                                Center(
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        color: kSubText,
                                        size: 48,
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        "No pending payments.",
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: kSubtleText,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              itemCount: _pendingRows.length,
                              itemBuilder: (_, i) {
                                final row = _pendingRows[i];
                                final amount = (row['amount'] is num)
                                    ? (row['amount'] as num).toDouble()
                                    : double.tryParse('${row['amount']}') ??
                                          0.0;
                                final deathNoticeId = row['death_notice_id'];
                                String deceasedLabel;
                                final meta = _noticeMeta[deathNoticeId];
                                if (meta != null &&
                                    (meta['deceased_type'] == 'beneficiary')) {
                                  final ben = (meta['name'] ?? '').toString();
                                  final mid = (meta['user_id'] ?? '')
                                      .toString();
                                  final memberName =
                                      _memberNames[mid] ?? 'Member';
                                  deceasedLabel =
                                      'For $ben, beneficiary of $memberName';
                                } else {
                                  final name =
                                      _deceasedNames[deathNoticeId] ?? '';
                                  deceasedLabel = name.isNotEmpty
                                      ? 'For $name'
                                      : 'For Deceased #$deathNoticeId';
                                }

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  elevation: 3,
                                  color: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                      horizontal: 18,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              backgroundColor:
                                                  Colors.blue.shade100,
                                              child: const Icon(
                                                Icons.payments_rounded,
                                                color: kAccent,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                deceasedLabel,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18,
                                                  color: kAccent,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Amount: ₱ ${amount.toStringAsFixed(2)}',
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
                                                'Pay Cash',
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
                                                'Pay GCash',
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
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
