import 'package:capstone_app/Members/dashboard.dart';
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
  String? location;

  List<dynamic> suggestedUnits = [];

  bool isLoading = false;
  bool isSubmitting = false;

  Future<void> applyToDayungUnit(String userId, int dayungUnitId) async {
  await Supabase.instance.client.from('applications').insert({
    'user_id': userId,
    'dayung_unit_id': dayungUnitId,
    'status': 'pending',
  });
}

  Future<void> _fetchSuggestions() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
    });

    try {
      final response = await Supabase.instance.client
          .from('dayung_units')
          .select()
          .ilike('fee_range', '%$feeRange%')
          .ilike('payment_method', '%$paymentMethod%')
          .eq('open_for_all', openForAll == 'Yes')
          .ilike('fund_support_range', '%$fundSupportRange%')
          .ilike('location', '%$location%');

      setState(() {
        suggestedUnits = response;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error fetching suggestions: $e')));
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _completeRegistration({String? selectedUnitId}) async {
    setState(() => isSubmitting = true);

    try {
      // Save preferences (optional)
      // await Supabase.instance.client.from('user_preferences').insert({
      //   'user_id': widget.userId,
      //   'fee_range': feeRange,
      //   'payment_method': paymentMethod,
      //   'open_for_all': openForAll == 'Yes',
      //   'fund_support_range': fundSupportRange,
      //   'location': location,
      //   'selected_unit_id': selectedUnitId,
      // });

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
  items: ['Free', '₱1 - ₱100', '₱101 - ₱500', '₱501+'],
  onChanged: (val) {
    setState(() => feeRange = val);
    _fetchSuggestions();
  },
),
                      _buildDropdown(
                        label: 'Preferred Payment Method',
                        value: paymentMethod,
                        items: ['GCash', 'Bank Transfer', 'Cash', 'Any'],
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
                        items: ['₱0 - ₱500', '₱501 - ₱1000', '₱1001+'],
                        onChanged: (val) {
                          setState(() => fundSupportRange = val);
                          _fetchSuggestions();
                        },
                      ),
                      _buildDropdown(
                        label: 'Preferred Location',
                        value: location,
                        items: ['Cebu', 'Davao', 'Manila', 'Anywhere'],
                        onChanged: (val) {
                          setState(() => location = val);
                          _fetchSuggestions();
                        },
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          if (feeRange == null &&
                              paymentMethod == null &&
                              openForAll == null &&
                              fundSupportRange == null &&
                              location == null) {
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
                                  subtitle: Text(unit['location'] ?? ''),
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
                          fundSupportRange != null ||
                          location != null)
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
                          onPressed: () => _completeRegistration(),
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
        validator: (val) => val == null ? 'This field is required' : null,
      ),
    );
  }
}
