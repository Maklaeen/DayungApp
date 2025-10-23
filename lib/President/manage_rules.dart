import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Modern UI colors
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimary = Color(0xFF3B82F6);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kDanger = Color(0xFFEF4444);

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
        .select(
          'contribution_rules, payout_rules, membership_rules, meeting_rules, service_rules',
        )
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
      await sb
          .from('dayung_rules')
          .upsert(payload, onConflict: 'dayung_unit_id');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Rules saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Custom App Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: kPrimary,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: kPrimary.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_rounded,
                      size: 24,
                      color: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Back',
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Manage Rules',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontFamily: 'Montserrat',
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _units.isEmpty
                  ? Center(
                      child: Container(
                        margin: const EdgeInsets.all(20),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: kCardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: kBorderColor.withOpacity(0.3),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 15,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.rule_rounded, size: 48, color: kSubText),
                            const SizedBox(height: 16),
                            Text(
                              'No dayung units found',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: kText,
                                fontFamily: 'Montserrat',
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No dayung units found for your account',
                              style: TextStyle(
                                fontSize: 14,
                                color: kSubText,
                                fontFamily: 'OpenSans',
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          // Unit picker
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: kCardBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: kBorderColor.withOpacity(0.3),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 15,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: kPrimary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.location_on_rounded,
                                    color: kPrimary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Dayung Unit:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: kText,
                                    fontFamily: 'Montserrat',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    value: _unitId,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: kCardBg,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: kBorderColor,
                                          width: 1,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: kBorderColor,
                                          width: 1,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: kPrimary,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    items: _units
                                        .map(
                                          (u) => DropdownMenuItem<int>(
                                            value: int.tryParse('${u['id']}'),
                                            child: Text(
                                              (u['name'] ?? 'Unit').toString(),
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontFamily: 'OpenSans',
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) async {
                                      setState(() => _unitId = v);
                                      if (v != null) {
                                        setState(() => _loading = true);
                                        try {
                                          await _loadRules(v);
                                        } finally {
                                          if (mounted)
                                            setState(() => _loading = false);
                                        }
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
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
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kPrimary,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ],
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

  Widget _field(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        maxLines: null,
        minLines: 4,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: kText,
            fontWeight: FontWeight.w700,
            fontFamily: 'Montserrat',
          ),
          filled: true,
          fillColor: kCardBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorderColor, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorderColor, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kPrimary, width: 2),
          ),
        ),
        style: const TextStyle(
          fontFamily: 'OpenSans',
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: kText,
        ),
      ),
    );
  }
}
