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
  int _count = 0;
  List<Map<String, dynamic>> _rows = [];
  
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
      final uid = sb.auth.currentUser?.id;
      if (uid == null) {
        setState(() {
          _rows = [];
          _total = 0;
          _count = 0;
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
  myTotal += a is num ? a.toDouble() : double.tryParse('${a}') ?? 0.0;
}
setState(() {
  _myRows = myRows;
  _myTotal = myTotal;
  _myCount = myRows.length;
  // keep existing _rows/_total/_count for "Collected by Me"
});

      final rows = List<Map<String, dynamic>>.from(res);
      double total = 0;
      for (final r in rows) {
        final a = r['amount'];
        total += a is num ? a.toDouble() : double.tryParse('${a}') ?? 0.0;
      }
      setState(() {
        _rows = rows;
        _total = total;
        _count = rows.length;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _rows = [];
        _total = 0;
        _count = 0;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Collected Contributions')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
  child: ListTile(
    title: const Text('My Paid Contributions'),
    subtitle: Text('Count: $_myCount'),
    trailing: Text('₱${_myTotal.toStringAsFixed(2)}'),
  ),
),
const SizedBox(height: 8),
Card(
  child: ListTile(
    title: const Text('Collected by Me'),
    subtitle: Text('Count: $_count'),
    trailing: Text('₱${_total.toStringAsFixed(2)}'),
  ),
),
                  Card(
                    child: ListTile(
                      title: const Text('Total Collected'),
                      subtitle: Text('Count: $_count'),
                      trailing: Text('₱${_total.toStringAsFixed(2)}'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._rows.map((r) {
                    final amt = r['amount'] is num
                        ? (r['amount'] as num).toDouble()
                        : double.tryParse('${r['amount']}') ?? 0.0;
                    final dt = (r['paid_at'] ?? r['created_at'] ?? '')
                        .toString();
                    return Card(
                      child: ListTile(
                        title: Text('₱${amt.toStringAsFixed(2)}'),
                        subtitle: Text('Paid: ${dt.split('T').first}'),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
