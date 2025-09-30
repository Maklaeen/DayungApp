import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageRulesPagePres extends StatefulWidget {
  const ManageRulesPagePres({super.key});

  @override
  State<ManageRulesPagePres> createState() => _ManageRulesPagePresState();
}

class _ManageRulesPagePresState extends State<ManageRulesPagePres> {
  final sb = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _units = [];
  int? _unitId;

  final _contrib = TextEditingController();
  final _payout = TextEditingController();
  final _membership = TextEditingController();
  final _meeting = TextEditingController();
  final _service = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _contrib.dispose();
    _payout.dispose();
    _membership.dispose();
    _meeting.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    try {
      await _loadUnitsForPresident();
      if (_unitId != null) {
        await _loadRules(_unitId!);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadUnitsForPresident() async {
    final uid = sb.auth.currentUser?.id;
    final res = await sb
        .from('dayung_units')
        .select('id,name')
        .eq('president_id', uid as Object)
        .order('name');
    _units = List<Map<String, dynamic>>.from(res);
    if (_units.isNotEmpty) {
      _unitId = int.tryParse('${_units.first['id']}');
    }
  }

  Future<void> _loadRules(int unitId) async {
    final row = await sb
        .from('dayung_rules')
        .select('contribution_rules, payout_rules, membership_rules, meeting_rules, service_rules')
        .eq('dayung_unit_id', unitId)
        .maybeSingle();

    _contrib.text = (row?['contribution_rules'] ?? '').toString();
    _payout.text = (row?['payout_rules'] ?? '').toString();
    _membership.text = (row?['membership_rules'] ?? '').toString();
    _meeting.text = (row?['meeting_rules'] ?? '').toString();
    _service.text = (row?['service_rules'] ?? '').toString();
    setState(() {});
  }

  Future<void> _save() async {
    if (_unitId == null) return;
    setState(() => _loading = true);
    try {
      final payload = {
        'dayung_unit_id': _unitId,
        'contribution_rules': _contrib.text.trim(),
        'payout_rules': _payout.text.trim(),
        'membership_rules': _membership.text.trim(),
        'meeting_rules': _meeting.text.trim(),
        'service_rules': _service.text.trim(),
        'updated_by': sb.auth.currentUser?.id,
      };

      // Upsert single row per unit
      await sb.from('dayung_rules').upsert(payload, onConflict: 'dayung_unit_id');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rules saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Rules')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _units.isEmpty
              ? const Center(child: Text('No dayung units found for your account'))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text('Dayung Unit', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _unitId,
                              items: _units.map((u) {
                                return DropdownMenuItem<int>(
                                  value: int.tryParse('${u['id']}'),
                                  child: Text((u['name'] ?? 'Unit').toString(), overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: (v) async {
                                setState(() => _unitId = v);
                                if (v != null) {
                                  setState(() => _loading = true);
                                  try { await _loadRules(v); } finally { if (mounted) setState(() => _loading = false); }
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          children: [
                            _field('Contribution rules', _contrib),
                            _field('Payout rules', _payout),
                            _field('Membership rules', _membership),
                            _field('Meeting rules', _meeting),
                            _field('Service rules', _service),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _save,
                              icon: const Icon(Icons.save),
                              label: const Text('Save Rules'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _field(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        maxLines: null,
        minLines: 4,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}