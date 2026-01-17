import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TreasurerContributionsPage extends StatefulWidget {
  final int dayungUnitId;
  const TreasurerContributionsPage({super.key, required this.dayungUnitId});

  @override
  State<TreasurerContributionsPage> createState() =>
      _TreasurerContributionsPageState();
}

class _TreasurerContributionsPageState
    extends State<TreasurerContributionsPage> {
  final sb = Supabase.instance.client;
  bool _loading = true;
  double _paidTotal = 0;
  double _pendingTotal = 0;
  int _paidCount = 0;
  int _pendingCount = 0;
  List<Map<String, dynamic>> _recent = [];
  double _myTotal = 0;
  int _myCount = 0;
  List<Map<String, dynamic>> _myRows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await sb
          .from('payments')
          .select(
            'id, amount, status, created_at, paid_at, dayung_unit_id, collected_by',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .order('created_at', ascending: false)
          .limit(200);

      final uid = sb.auth.currentUser?.id;
      final myRes = await sb
          .from('payments')
          .select('id, amount, status, created_at, dayung_unit_id')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'paid')
          .eq('user_id', uid as Object)
          .order('created_at', ascending: false);

      final myRows = List<Map<String, dynamic>>.from(myRes);
      double myTotal = 0;
      for (final r in myRows) {
        final a = r['amount'];
        myTotal += a is num ? a.toDouble() : double.tryParse('${a}') ?? 0.0;
      }
      setState(() {
        _myRows = myRows;
        _myTotal = myTotal;
        _myCount = myRows.length;
      });

      final rows = List<Map<String, dynamic>>.from(res);
      double paidTotal = 0, pendingTotal = 0;
      int paidCount = 0, pendingCount = 0;
      for (final r in rows) {
        final amt = r['amount'] is num
            ? (r['amount'] as num).toDouble()
            : double.tryParse('${r['amount']}') ?? 0.0;
        final st = (r['status'] ?? '').toString().toLowerCase();
        if (st == 'paid') {
          paidTotal += amt;
          paidCount++;
        } else {
          pendingTotal += amt;
          pendingCount++;
        }
      }
      setState(() {
        _paidTotal = paidTotal;
        _pendingTotal = pendingTotal;
        _paidCount = paidCount;
        _pendingCount = pendingCount;
        _recent = rows.take(20).toList();
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _paidTotal = 0;
        _pendingTotal = 0;
        _paidCount = 0;
        _pendingCount = 0;
        _recent = [];
        _loading = false;
      });
    }
  }

  Widget _summaryTile(String title, String value, {Color? color}) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: Text(value, style: TextStyle(color: color)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unit Contributions')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _summaryTile(
                    'My Paid Total',
                    '₱${_myTotal.toStringAsFixed(2)}',
                    color: const Color(0xFF3B82F6),
                  ),
                  _summaryTile('My Paid Count', '$_myCount'),
                  _summaryTile(
                    'Paid Total',
                    '₱${_paidTotal.toStringAsFixed(2)}',
                    color: const Color(0xFF2E7D32),
                  ),
                  _summaryTile(
                    'Pending Total',
                    '₱${_pendingTotal.toStringAsFixed(2)}',
                    color: const Color(0xFFF57C00),
                  ),
                  _summaryTile('Paid Count', '$_paidCount'),
                  _summaryTile('Pending Count', '$_pendingCount'),
                  const SizedBox(height: 12),
                  const Text(
                    'Recent Payments',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._recent.map((r) {
                    final amt = r['amount'] is num
                        ? (r['amount'] as num).toDouble()
                        : double.tryParse('${r['amount']}') ?? 0.0;
                    final st = (r['status'] ?? '').toString();
                    final dt = (r['paid_at'] ?? r['created_at'] ?? '')
                        .toString();
                    return Card(
                      child: ListTile(
                        title: Text('₱${amt.toStringAsFixed(2)}'),
                        subtitle: Text('Date: ${dt.split('T').first}'),
                        trailing: Text(st),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
