import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PresidentClaimsPage extends StatefulWidget {
  final int dayungUnitId;
  const PresidentClaimsPage({super.key, required this.dayungUnitId});

  @override
  State<PresidentClaimsPage> createState() => _PresidentClaimsPageState();
}

class _PresidentClaimsPageState extends State<PresidentClaimsPage> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _claims = [];

  @override
  void initState() {
    super.initState();
    _loadClaims();
  }

  Future<void> _loadClaims() async {
    setState(() => _loading = true);
    final rows = await _sb
        .from('claims')
        .select()
        .eq('dayung_unit_id', widget.dayungUnitId);
    setState(() {
      _claims = List<Map<String, dynamic>>.from(rows);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_claims.isEmpty) {
      return const Center(child: Text('No claims found.'));
    }
    return ListView.builder(
      itemCount: _claims.length,
      itemBuilder: (context, idx) {
        final claim = _claims[idx];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Text(claim['claim_type'] ?? 'Claim'),
            subtitle: Text(
              'By: ${claim['user_id']}\nStatus: ${claim['status']}',
            ),
            trailing: Text(
              claim['created_at']?.toString().split('T').first ?? '',
            ),
            onTap: () {
              // Optionally show claim details or approve/reject actions
            },
          ),
        );
      },
    );
  }
}
