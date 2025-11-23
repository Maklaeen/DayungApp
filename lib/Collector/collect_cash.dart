import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      // 1. Get all approved applications for this dayung
      final appsRes = await sb
          .from('applications')
          .select('user_id')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'approved');
      final userIds = List<Map<String, dynamic>>.from(appsRes)
          .map((a) => a['user_id'])
          .toList();

      // 2. Fetch user info
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

  void _showInputDialog(Map<String, dynamic> member) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Enter Payment for ${member['full_name']}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          decoration: const InputDecoration(
            labelText: 'Amount (₱)',
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          ElevatedButton(
            child: const Text('Save Payment'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final amount = double.tryParse(controller.text);
      if (amount == null || amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid amount.')),
        );
        return;
      }
      await _savePayment(member['id'], amount);
    }
  }

  Future<void> _savePayment(String userId, double amount) async {
    try {
      final collectorId = sb.auth.currentUser?.id;
      if (collectorId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not logged in as collector.')),
        );
        return;
      }
      final now = DateTime.now().toUtc().toIso8601String();
      await sb.from('payments').insert({
        'user_id': userId,
        'amount': amount,
        'dayung_unit_id': widget.dayungUnitId,
        'status': 'paid',
        'paid_at': now,
        'collected_by': collectorId,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment recorded!')),
      );
      _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save payment: $e')),
      );
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
              : _approvedMembers.isEmpty
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
                  : ListView.separated(
                      padding: const EdgeInsets.all(18),
                      itemCount: _approvedMembers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
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
                            side: BorderSide(color: kAccent.withOpacity(0.10)),
                          ),
                          onTap: () => _showInputDialog(member),
                        );
                      },
                    ),
    );
  }
}
