import 'package:capstone_app/utils/dayung_service_tags.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Collor palette
const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);
const kPrimary = Color(0xFF0D47A1);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);

class ManageRulesPagePres extends StatefulWidget {
  const ManageRulesPagePres({super.key});

  @override
  State<ManageRulesPagePres> createState() => _ManageRulesPagePresState();
}

class _ManageRulesPagePresState extends State<ManageRulesPagePres> {
  final sb = Supabase.instance.client;

  // Only the required dropdowns and switch
  final List<String> _meetingFrequencies = ['Weekly', 'Monthly', 'Needed'];
  final List<String> _feeRanges = [
    '50-100',
    '100-150',
    '150-200',
    '200-250',
    '250-300',
    '300-350',
    '400 plus',
  ];
  final List<String> _paymentMethodsDropdown = ['Cash', 'GCash', 'Both'];

  String? _selectedMeetingFrequency;
  String? _selectedRegistrationFeeRange;
  String? _selectedMembershipPayment;
  String? _selectedPenaltyPayment;
  String? _selectedPaymentMethodDropdown;
  String? _exactAmountForMembership;
  String? _exactAmountForCollection;
  bool _openForAll = false;
  bool _hasService = false;
  final Map<String, bool> _selectedServiceTags = {};

  bool _loading = true;
  List<Map<String, dynamic>> _units = [];
  int? _unitId;
  late TextEditingController _exactAmountController;
  late TextEditingController _exactCollectionAmountController;

  @override
  void initState() {
    super.initState();
    _exactAmountController = TextEditingController(text: _exactAmountForMembership ?? '');
    _exactCollectionAmountController = TextEditingController(text: _exactAmountForCollection ?? '');
    _init();
  }

  @override
  void dispose() {
    _exactAmountController.dispose();
    _exactCollectionAmountController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    try {
      await _loadUnitsForPresident();
      if (_unitId != null) {
        await _loadRules(_unitId!);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadUnitsForPresident() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) {
      _units = [];
      return;
    }
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
    try {
      final row = await sb
          .from('dayung_rules')
          .select('''
            meeting_frequency, collection_fee_range, membership_payment, penalty_payment, payment_method, open_for_all, has_service, exactamountformembership, exactamountforcollection, ${dayungServiceTagLabels.map((label) => dayungServiceTagColumns[label]!).join(', ')}
            ''')
          .eq('dayung_unit_id', unitId)
          .maybeSingle();

      _selectedMeetingFrequency = row?['meeting_frequency'];
      _selectedRegistrationFeeRange = row?['collection_fee_range'];
      _selectedMembershipPayment = row?['membership_payment'];
      _selectedPenaltyPayment = row?['penalty_payment'];
      _selectedPaymentMethodDropdown = row?['payment_method'];
      _openForAll = row?['open_for_all'] == true;
      _hasService = row?['has_service'] == true;
      for (final label in dayungServiceTagLabels) {
        final column = dayungServiceTagColumns[label]!;
        _selectedServiceTags[label] = row?[column] == true;
      }
      _exactAmountForMembership = row?['exactamountformembership'];
      _exactAmountForCollection = row?['exactamountforcollection'];
      _exactAmountController.text = _exactAmountForMembership ?? '';
      _exactCollectionAmountController.text = _exactAmountForCollection ?? '';

      setState(() {});
    } catch (_) {}
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
      final uid = sb.auth.currentUser?.id;

      final payload = {
        'dayung_unit_id': _unitId,
        'dayung_unit_name': unitName,
        'meeting_frequency': _selectedMeetingFrequency,
        'collection_fee_range': _selectedRegistrationFeeRange,
        'membership_payment': _selectedMembershipPayment,
        'penalty_payment': _selectedPenaltyPayment,
        'payment_method': _selectedPaymentMethodDropdown,
        'open_for_all': _openForAll,
        'has_service': _hasService,
        'exactamountformembership': _exactAmountForMembership,
        'exactamountforcollection': _exactAmountForCollection,
        for (final label in dayungServiceTagLabels)
          dayungServiceTagColumns[label]!: _selectedServiceTags[label] ?? false,
        'updated_by': uid,
      };

      await sb
          .from('dayung_rules')
          .upsert(payload, onConflict: 'dayung_unit_id');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text(
                  'Rules saved',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            backgroundColor: kAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
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
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Curved Header
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
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'User Preferences',
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
            const SizedBox(height: 24),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: kAccent),
                    )
                  : _units.isEmpty
                  ? Center(
                      child: Container(
                        margin: const EdgeInsets.all(20),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: kCardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: kBorderColor.withValues(alpha: 0.3),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ListView(
                        children: [
                          const SizedBox(height: 8),
                          // Card for unit picker and rules
                          Card(
                            elevation: 3,
                            color: kCardBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                children: [
                                  _unitPicker(),
                                  const SizedBox(height: 20),
                                  _dropdownField(
                                    'Meeting Frequency',
                                    _meetingFrequencies,
                                    _selectedMeetingFrequency,
                                    (v) => setState(
                                      () => _selectedMeetingFrequency = v,
                                    ),
                                  ),
                                  _dropdownField(
                                    'Collection Fee Range',
                                    _feeRanges,
                                    _selectedRegistrationFeeRange,
                                    (v) => setState(
                                      () => _selectedRegistrationFeeRange = v,
                                    ),
                                  ),
                                  _exactAmountCollectionTextField(),
                                  _dropdownField(
                                    'Membership Payment',
                                    _feeRanges,
                                    _selectedMembershipPayment,
                                    (v) => setState(
                                      () => _selectedMembershipPayment = v,
                                    ),
                                  ),
                                  _exactAmountTextField(),
                                  const SizedBox(height: 8),
                                  _dropdownField(
                                    'Penalty Payment',
                                    _feeRanges,
                                    _selectedPenaltyPayment,
                                    (v) => setState(
                                      () => _selectedPenaltyPayment = v,
                                    ),
                                  ),
                                  _dropdownField(
                                    'Payment Method',
                                    _paymentMethodsDropdown,
                                    _selectedPaymentMethodDropdown,
                                    (v) => setState(
                                      () => _selectedPaymentMethodDropdown = v,
                                    ),
                                  ),
                                  _openForAllSwitch(),
                                  _hasServiceSwitch(),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Service Tags',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: kPrimary,
                                        fontFamily: 'Montserrat',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: dayungServiceTagLabels.map((label) {
                                      return FilterChip(
                                        label: Text(label),
                                        selected: _selectedServiceTags[label] ?? false,
                                        onSelected: (value) {
                                          setState(() {
                                            _selectedServiceTags[label] = value;
                                          });
                                        },
                                        side: const BorderSide(color: kBorderColor),
                                        selectedColor: kPrimary.withValues(alpha: 0.16),
                                        checkmarkColor: kPrimary,
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: _save,
                                      icon: const Icon(Icons.save),
                                      label: const Text('Save Rules'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: kAccent,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
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
        border: Border.all(
          color: kBorderColor.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
              color: kPrimary.withValues(alpha: 0.1),
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

  Widget _dropdownField(
    String label,
    List<String> options,
    String? selectedValue,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: selectedValue,
        isExpanded: true,
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
        items: options
            .map(
              (o) => DropdownMenuItem<String>(
                value: o,
                child: Text(
                  o,
                  style: const TextStyle(
                    fontFamily: 'OpenSans',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _openForAllSwitch() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Text(
            'Open for all?',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: kText,
            ),
          ),
          const SizedBox(width: 16),
          RadioGroup<bool>(
            groupValue: _openForAll,
            onChanged: (value) => setState(() => _openForAll = value ?? false),
            child: Row(
              children: const [
                Radio<bool>(value: true),
                Text('Yes'),
                Radio<bool>(value: false),
                Text('No'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hasServiceSwitch() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Text(
            'Has Service?',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: kText,
            ),
          ),
          const SizedBox(width: 16),
          RadioGroup<bool>(
            groupValue: _hasService,
            onChanged: (value) => setState(() => _hasService = value ?? false),
            child: Row(
              children: const [
                Radio<bool>(value: true),
                Text('Yes'),
                Radio<bool>(value: false),
                Text('No'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _exactAmountTextField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _exactAmountController,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Exact Amount for Membership',
          labelStyle: const TextStyle(
            color: kText,
            fontWeight: FontWeight.w700,
            fontFamily: 'Montserrat',
          ),
          hintText: 'Enter exact amount',
          hintStyle: TextStyle(
            color: kSubText.withValues(alpha: 0.5),
            fontFamily: 'OpenSans',
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
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Text(
              '₱',
              style: TextStyle(
                fontSize: 18,
                color: kPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        ),
        onChanged: (value) => setState(() => _exactAmountForMembership = value),
        style: const TextStyle(
          fontFamily: 'OpenSans',
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _exactAmountCollectionTextField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _exactCollectionAmountController,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Exact Amount for Collection',
          labelStyle: const TextStyle(
            color: kText,
            fontWeight: FontWeight.w700,
            fontFamily: 'Montserrat',
          ),
          hintText: 'Enter exact amount',
          hintStyle: TextStyle(
            color: kSubText.withValues(alpha: 0.5),
            fontFamily: 'OpenSans',
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
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Text(
              '₱',
              style: TextStyle(
                fontSize: 18,
                color: kPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        ),
        onChanged: (value) => setState(() => _exactAmountForCollection = value),
        style: const TextStyle(
          fontFamily: 'OpenSans',
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
