import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PresidentContributionsPage extends StatefulWidget {
  final int dayungUnitId;
  const PresidentContributionsPage({super.key, required this.dayungUnitId});

  @override
  State<PresidentContributionsPage> createState() =>
      _PresidentContributionsPageState();
}

class _PresidentContributionsPageState
    extends State<PresidentContributionsPage> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _contributions = [];

  @override
  void initState() {
    super.initState();
    _loadContributions();
  }

  Future<void> _loadContributions() async {
    setState(() => _loading = true);
    final rows = await _sb
        .from('payments')
        .select()
        .eq('dayung_unit_id', widget.dayungUnitId)
        .order('paid_at', ascending: false);
    setState(() {
      _contributions = List<Map<String, dynamic>>.from(rows);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_contributions.isEmpty) {
      return const Center(child: Text('No contributions found.'));
    }
    return ListView.builder(
      itemCount: _contributions.length,
      itemBuilder: (context, idx) {
        final contrib = _contributions[idx];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Text('₱${contrib['amount']}'),
            subtitle: Text(
              'By: ${contrib['user_id']}\nStatus: ${contrib['status']}',
            ),
            trailing: Text(
              contrib['paid_at']?.toString().split('T').first ?? '',
            ),
          ),
        );
      },
    );
  }
}
