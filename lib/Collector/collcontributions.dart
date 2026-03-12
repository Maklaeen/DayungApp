import 'package:capstone_app/Collector/collector_payment_page.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CollectorContributionsPage extends StatefulWidget {
  final int dayungUnitId;
  const CollectorContributionsPage({super.key, required this.dayungUnitId});

  @override
  State<CollectorContributionsPage> createState() =>
      _CollectorContributionsPageState();
}

class _CollectorContributionsPageState
    extends State<CollectorContributionsPage> {
  final sb = Supabase.instance.client;
  bool _loading = true;
  double _total = 0;
  List<Map<String, dynamic>> _rows = [];

  double _myTotal = 0;
  int _myCount = 0;
  List<Map<String, dynamic>> _myRows = [];

  int _totalPaymentNumbers = 0; // <-- Add this

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = sb.auth.currentUser?.id;
      if (uid == null) {
        setState(() {
          _rows = [];
          _total = 0;
          _loading = false;
        });
        return;
      }
      final res = await sb
          .from('payments')
          .select(
            'id, amount, status, paid_at, created_at, user_id, dayung_unit_id, collected_by, death_notice_id',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'paid')
          .eq('collected_by', uid)
          .order('paid_at', ascending: false)
          .limit(100);

      final myRes = await sb
          .from('payments')
          .select('id, amount, status, created_at, dayung_unit_id')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'paid')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(100);

      final myRows = List<Map<String, dynamic>>.from(myRes);
      double myTotal = 0;
      for (final r in myRows) {
        final a = r['amount'];
        myTotal += a is num ? a.toDouble() : double.tryParse('$a') ?? 0.0;
      }
      setState(() {
        _myRows = myRows;
        _myTotal = myTotal;
        _myCount = myRows.length;
        // keep existing _rows/_total for "Collected by Me"
      });

      final rows = List<Map<String, dynamic>>.from(res);
      double total = 0;
      for (final r in rows) {
        final a = r['amount'];
        total += a is num ? a.toDouble() : double.tryParse('$a') ?? 0.0;
      }
      int totalPaymentNumbers = 0;
      for (final r in rows) {
        final pn = r['payment_number'];
        if (pn is int) {
          totalPaymentNumbers += pn;
        } else if (pn != null) {
          totalPaymentNumbers += int.tryParse('$pn') ?? 0;
        }
      }
      setState(() {
        _rows = rows;
        _total = total;
        _loading = false;
        _totalPaymentNumbers = totalPaymentNumbers; // <-- Add this
      });
    } catch (_) {
      setState(() {
        _rows = [];
        _total = 0;
        _loading = false;
      });
    }
  }

  double _amountOf(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0.0;
  }

  String _dateOf(Map<String, dynamic> row) {
    final raw = (row['paid_at'] ?? row['created_at'] ?? '').toString();
    if (raw.isEmpty) return 'No date';
    return raw.split('T').first;
  }

  Widget _shortcutCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF083366), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Need to settle your own contribution?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Open your payment page to review your pending records and choose cash or GCash.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CollectorPaymentPage(dayungUnitId: widget.dayungUnitId),
                ),
              ).then((_) => _load());
            },
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Open Payment Page'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0D47A1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4B5563),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentTile(Map<String, dynamic> row, {required bool mine}) {
    final amount = _amountOf(row['amount']);
    final label = mine ? 'Your paid contribution' : 'Collected by you';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '₱${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0D47A1),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _dateOf(row),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4B5563),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const DayungPageSkeleton(
              layout: DayungSkeletonLayout.dashboard,
              itemCount: 4,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _shortcutCard(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          'My Paid Total',
                          '₱${_myTotal.toStringAsFixed(2)}',
                          Icons.person_rounded,
                          const Color(0xFF0D47A1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _statCard(
                          'Collected Total',
                          '₱${_total.toStringAsFixed(2)}',
                          Icons.payments_rounded,
                          const Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          'My Paid Count',
                          '$_myCount',
                          Icons.check_circle_rounded,
                          const Color(0xFFF57C00),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _statCard(
                          'Payment Numbers',
                          '$_totalPaymentNumbers',
                          Icons.confirmation_number_rounded,
                          const Color(0xFF7C3AED),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'My Contributions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_myRows.isEmpty)
                    const Text(
                      'No personal paid contributions yet.',
                      style: TextStyle(color: Color(0xFF4B5563)),
                    )
                  else
                    ..._myRows.map((row) => _paymentTile(row, mine: true)),
                  const SizedBox(height: 12),
                  const Text(
                    'Collected By Me',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_rows.isEmpty)
                    const Text(
                      'No collected payments yet.',
                      style: TextStyle(color: Color(0xFF4B5563)),
                    )
                  else
                    ..._rows.map((row) => _paymentTile(row, mine: false)),
                ],
              ),
            ),
    );
  }
}
