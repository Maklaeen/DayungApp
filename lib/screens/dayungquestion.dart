import 'package:capstone_app/Members/dashboard.dart';
import 'package:capstone_app/screens/dayung_suggestions.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QuestionnaireScreen extends StatefulWidget {
  final String userId;
  final String role;

  const QuestionnaireScreen({
    super.key,
    required this.userId,
    required this.role,
  });

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  final _formKey = GlobalKey<FormState>();

  String? feeRange;
  String? paymentMethod;
  String? openForAll;
  String? fundSupportRange;

  List<dynamic> suggestedUnits = [];

  bool isLoading = false;
  bool isSubmitting = false;

  // Normalize helpers
  String _digits(String? s) => (s ?? '').replaceAll(RegExp(r'[^\d]'), '');
  String _trimLower(String? s) => (s ?? '').trim().toLowerCase();

  Future<void> applyToDayungUnit(String userId, int dayungUnitId) async {
    await Supabase.instance.client.from('applications').insert({
      'user_id': userId,
      'dayung_unit_id': dayungUnitId,
      'status': 'pending',
    });
  }

  Future<void> _fetchSuggestions() async {
    setState(() => isLoading = true);
    try {
      var qb = Supabase.instance.client.from('dayung_units').select();

      // Debug: show chosen filters
      // ignore: avoid_print
      print(
        'Filters -> fee:$feeRange, pay:$paymentMethod, open:$openForAll, fund:$fundSupportRange',
      );

      // Make filters tolerant:
      // - For fee/fund, match by digits (so "100" matches "₱100", "₱0 - ₱100")
      // - For text, use ilike with wildcards
      final feeDigits = _digits(feeRange);
      if (feeRange != null && feeRange != 'Any' && feeDigits.isNotEmpty) {
        qb = qb.ilike('fee_range', '%$feeDigits%');
      }

      if (paymentMethod != null && paymentMethod != 'Any') {
        qb = qb.ilike('payment_method', '%${_trimLower(paymentMethod)}%');
      }

      if (openForAll != null) {
        qb = qb.eq('open_for_all', openForAll == 'Yes');
      }

      final fundDigits = _digits(fundSupportRange);
      if (fundSupportRange != null &&
          fundSupportRange != 'Any' &&
          fundDigits.isNotEmpty) {
        qb = qb.ilike('fund_support_range', '%$fundDigits%');
      }

      final rows = await qb.limit(20);

      // Debug
      // ignore: avoid_print
      print('Suggestions found: ${rows.length}');
      setState(() {
        suggestedUnits = rows as List<dynamic>;
      });

      // Optional: fallback to show all if nothing matched (helps debug)
      if (suggestedUnits.isEmpty) {
        final all = await Supabase.instance.client
            .from('dayung_units')
            .select()
            .limit(10);
        // ignore: avoid_print
        print('All units sample (no filters matched): ${all.length}');
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error fetching suggestions: $e')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _savePreferences({String? selectedUnitId}) async {
    await Supabase.instance.client.from('user_preferences').insert({
      'user_id': widget.userId,
      'fee_range': feeRange,
      'payment_method': paymentMethod,
      'open_for_all': openForAll == 'Yes',
      'fund_support_range': fundSupportRange,
      // Removed: 'location': location,
      'selected_unit_id': selectedUnitId,
    });
  }

  Future<void> _completeRegistration({String? selectedUnitId}) async {
    setState(() => isSubmitting = true);

    try {
      // Save preferences
      await _savePreferences(selectedUnitId: selectedUnitId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logging in'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(top: 16, left: 16, right: 16),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.blue,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 800));
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MemberDashboardPage()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error completing registration: $e')),
      );
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dayung Preferences')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildDropdown(
                        label: 'Registration Fee Range',
                        value: feeRange,
                        // Ensure options are consistent; include "Any"
                        items: [
                          'Any',
                          'Free',
                          '₱1 - ₱100',
                          '₱101 - ₱500',
                          '₱501+',
                          '₱100',
                          '₱500',
                          '₱1000',
                        ],
                        onChanged: (val) {
                          setState(() => feeRange = val);
                          _fetchSuggestions();
                        },
                      ),
                      _buildDropdown(
                        label: 'Preferred Payment Method',
                        value: paymentMethod,
                        items: [
                          'Any',
                          'GCash',
                          'Bank Transfer',
                          'Cash',
                          'gcash',
                          'bank',
                          'cash',
                        ],
                        onChanged: (val) {
                          setState(() => paymentMethod = val);
                          _fetchSuggestions();
                        },
                      ),
                      _buildDropdown(
                        label: 'Open for All?',
                        value: openForAll,
                        items: ['Yes', 'No'],
                        onChanged: (val) {
                          setState(() => openForAll = val);
                          _fetchSuggestions();
                        },
                      ),
                      _buildDropdown(
                        label: 'Fund Support Range',
                        value: fundSupportRange,
                        items: [
                          'Any',
                          '₱0 - ₱500',
                          '₱501 - ₱1000',
                          '₱1001+',
                          '₱500',
                          '₱1000',
                          '₱1500',
                        ],
                        onChanged: (val) {
                          setState(() => fundSupportRange = val);
                          _fetchSuggestions();
                        },
                      ),

                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          if (feeRange == null &&
                              paymentMethod == null &&
                              openForAll == null &&
                              fundSupportRange == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please fill at least one preference or skip.',
                                ),
                              ),
                            );
                            return;
                          }
                          _fetchSuggestions();
                        },
                        child: const Text('Find Matching Units'),
                      ),

                      const SizedBox(height: 24),
                      if (suggestedUnits.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Suggested Dayung Units:',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...suggestedUnits.map((unit) {
                              return Card(
                                child: ListTile(
                                  title: Text(unit['name'] ?? 'Unnamed Unit'),
                                  subtitle: Text(
                                    [
                                          if (unit['barangay'] != null)
                                            unit['barangay'],
                                          if (unit['city'] != null)
                                            unit['city'],
                                          if (unit['province'] != null)
                                            unit['province'],
                                        ]
                                        .where(
                                          (e) =>
                                              (e ?? '').toString().isNotEmpty,
                                        )
                                        .join(', '),
                                  ),
                                  trailing: ElevatedButton(
                                    onPressed: () => _completeRegistration(
                                      selectedUnitId: unit['id'],
                                    ),
                                    child: const Text('Select'),
                                  ),
                                ),
                              );
                            }).toList(),
                            const SizedBox(height: 16),
                          ],
                        )
                      else if (feeRange != null ||
                          paymentMethod != null ||
                          openForAll != null ||
                          fundSupportRange != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: const Text(
                            'No suggestions found with the given preferences.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),

                      const SizedBox(height: 24),

                      Center(
                        child: TextButton(
                          onPressed: () async {
                            await _savePreferences();
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const DayungSuggestionsPage(),
                              ),
                            );
                          },
                          child: const Text('Skip & Continue'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required List<String> items,
    required String? value,
    required Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: items
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: onChanged,
        // Preferences are optional
        validator: (_) => null,
      ),
    );
  }
}
