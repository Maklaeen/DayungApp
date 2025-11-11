import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

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
  final List<String> _paymentMethods = [
    'GCash',
    'Paymaya',
    'Bank Transfer',
    'Cash',
  ];
  List<String> _selectedMethods = [];

  bool _loading = true;
  List<Map<String, dynamic>> _units = [];
  int? _unitId;

  final _contrib = TextEditingController();
  final _mempayment = TextEditingController();
  final _penaltypayment = TextEditingController();
  final _paymentmethod = TextEditingController();

  // New service rules list
  List<Map<String, dynamic>> _serviceRules = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _contrib.dispose();
    _mempayment.dispose();
    _penaltypayment.dispose();
    _paymentmethod.dispose();
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
          'contribution_amount, membership_payment, penalty_payment, payment_method, service_rules',
        )
        .eq('dayung_unit_id', unitId)
        .maybeSingle();

    _contrib.text = (row?['contribution_amount'] ?? '').toString();
    _mempayment.text = (row?['membership_payment'] ?? '').toString();
    _penaltypayment.text = (row?['penalty_payment'] ?? '').toString();
    _paymentmethod.text = (row?['payment_method'] ?? '').toString();

    _selectedMethods = _paymentmethod.text.isNotEmpty
        ? _paymentmethod.text.split(',').map((e) => e.trim()).toList()
        : [];

    // Robustly parse service_rules as jsonb or text
    final sr = row?['service_rules'];
    try {
      if (sr is String) {
        _serviceRules = List<Map<String, dynamic>>.from(jsonDecode(sr));
      } else if (sr is List) {
        _serviceRules = List<Map<String, dynamic>>.from(sr);
      } else {
        _serviceRules = [];
      }
    } catch (_) {
      _serviceRules = [];
    }

    setState(() {});
  }

  Future<void> _save() async {
    if (_unitId == null) return;
    setState(() => _loading = true);
    try {
      final selectedUnit = _units.firstWhere(
        (u) => int.tryParse('${u['id']}') == _unitId,
        orElse: () => {},
      );
      final unitName = selectedUnit['name'] ?? '';

      final payload = {
        'dayung_unit_id': _unitId,
        'dayung_unit_name': unitName, // requires column (see SQL)
        'contribution_amount': _contrib.text.trim(),
        'membership_payment': _mempayment.text.trim(),
        'penalty_payment': _penaltypayment.text.trim(),
        'payment_method': _selectedMethods.join(', '),
        'service_rules': _serviceRules, // send JSON, not jsonEncode
        'updated_by': sb.auth.currentUser?.id,
      };

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
                          _unitPicker(),
                          const SizedBox(height: 20),
                          Expanded(
                            child: ListView(
                              children: [
                                _field(
                                  'Contribution Amount',
                                  _contrib,
                                  numbersOnly: true,
                                ),
                                _field(
                                  'Membership Payment',
                                  _mempayment,
                                  numbersOnly: true,
                                ),
                                _field(
                                  'Penalty Payment',
                                  _penaltypayment,
                                  numbersOnly: true,
                                ),
                                _paymentMethodSelector(),
                                _serviceRulesSection(),
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

  Widget _unitPicker() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorderColor.withOpacity(0.3), width: 1),
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
              initialValue: _unitId,
              isExpanded: true,
              decoration: InputDecoration(
                filled: true,
                fillColor: kCardBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: kBorderColor, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: kBorderColor, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: kPrimary, width: 2),
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
                    if (mounted) setState(() => _loading = false);
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentMethodSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Methods',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: kText,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _paymentMethods.map((method) {
              final selected = _selectedMethods.contains(method);
              return FilterChip(
                label: Text(
                  method,
                  style: TextStyle(
                    fontFamily: 'OpenSans',
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : kText,
                  ),
                ),
                selected: selected,
                selectedColor: kPrimary,
                backgroundColor: kCardBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: selected ? kPrimary : kBorderColor),
                ),
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      _selectedMethods.add(method);
                    } else {
                      _selectedMethods.remove(method);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _serviceRulesSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Service Rules',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: kText,
            ),
          ),
          const SizedBox(height: 8),
          Column(
            children: [
              for (int i = 0; i < _serviceRules.length; i++)
                _serviceRuleItem(i),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _serviceRules.add({'rule': '', 'required': false});
                  });
                },
                icon: const Icon(Icons.add_circle, color: kPrimary),
                label: const Text(
                  'Add Rule',
                  style: TextStyle(
                    fontFamily: 'OpenSans',
                    fontWeight: FontWeight.w600,
                    color: kPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _serviceRuleItem(int index) {
    final rule = _serviceRules[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: kCardBg,
        border: Border.all(color: kBorderColor),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              initialValue: rule['rule'],
              onChanged: (v) => _serviceRules[index]['rule'] = v,
              decoration: const InputDecoration(
                labelText: 'Rule',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              const Text(
                'Required',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'OpenSans',
                ),
              ),
              Checkbox(
                value: rule['required'],
                onChanged: (v) {
                  setState(() {
                    _serviceRules[index]['required'] = v ?? false;
                  });
                },
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: kDanger),
            onPressed: () {
              setState(() {
                _serviceRules.removeAt(index);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController c, {
    bool numbersOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: numbersOnly
            ? TextInputType.number
            : TextInputType.multiline,
        inputFormatters: numbersOnly
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
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
