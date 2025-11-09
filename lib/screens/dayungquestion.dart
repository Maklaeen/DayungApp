// ignore_for_file: non_constant_identifier_names

import 'dart:math';

import 'package:capstone_app/Members/dashboard.dart';
import 'package:capstone_app/screens/dayung_map_page.dart';
import 'package:capstone_app/screens/dayung_suggestions.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:supabase_flutter/supabase_flutter.dart';

const Color kPrimary = Color(0xFF3B82F6);
const Color kPrimaryDark = Color(0xFF1E40AF);
const Color kAccent = Color(0xFF10B981);
const Color kWarn = Color(0xFFF59E0B);
const Color kDanger = Color(0xFFEF4444);
const Color kBg = Color(0xFFF8FAFC);
const Color kCardBg = Color(0xFFFFFFFF);
const Color kSubText = Color(0xFF6B7280);
const Color kText = Color(0xFF111827);

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

  String? contribution_amount;
  String? membership_payment;
  String? penalty_payment;
  String? payment_method;
  String? openForAll;
  String? fundSupportRange;
  List<dynamic> suggestedUnits = [];
  bool isLoading = false;
  bool isSubmitting = false;

  String _digits(String? s) => (s ?? '').replaceAll(RegExp(r'[^\d]'), '');
  String _trimLower(String? s) => (s ?? '').trim().toLowerCase();

  Future<void> applyToDayungUnit(String userId, int dayungUnitId) async {
    await Supabase.instance.client.from('applications').insert({
      'user_id': userId,
      'dayung_unit_id': dayungUnitId,
      'status': 'pending',
    });
  }

  // numeric vector for pgvector
  List<double> _generatePreferenceVector() {
    double fee = double.tryParse(_digits(contribution_amount)) ?? 0.0;
    double membership = membership_payment == 'Monthly'
        ? 1
        : membership_payment == 'Yearly'
        ? 2
        : 0;
    double penalty = penalty_payment == 'Strict'
        ? 2
        : penalty_payment == 'Mild'
        ? 1
        : 0;
    double method = payment_method == 'Cash'
        ? 1
        : payment_method == 'Online'
        ? 2
        : 0;
    double open = openForAll == 'Yes' ? 1 : 0;
    double fund = double.tryParse(_digits(fundSupportRange)) ?? 0.0;

    // between 0 and 1 for similarity
    return [
      (fee / 1000).clamp(0, 1),
      membership / 2,
      penalty / 2,
      method / 2,
      open,
      (fund / 1000).clamp(0, 1),
    ];
  }

  // pgvector
  Future<void> _fetchSuggestions() async {
    setState(() => isLoading = true);
    try {
      final vector = _generatePreferenceVector();
      print('User vector: $vector');
      final response = await Supabase.instance.client.rpc(
        'match_dayung_units',
        params: {'user_vector': vector, 'match_count': 10},
      );
      if (response is List) {
        setState(() {
          suggestedUnits = response;
        });
      }

      print('pgvector suggestions: ${suggestedUnits.length}');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching pgvector suggestions: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _savePreferences({int? selectedUnitId}) async {
    final payload = {
      'user_id': widget.userId,
      'contribution_amount': contribution_amount,
      'membership_payment': membership_payment,
      'penalty_payment': penalty_payment,
      'payment_method': payment_method,
      'open_for_all': openForAll == null ? null : (openForAll == 'Yes'),
      'fund_support_range': fundSupportRange,
      'selected_unit_id': selectedUnitId,
    };

    final existing = await Supabase.instance.client
        .from('user_preferences')
        .select('id')
        .eq('user_id', widget.userId)
        .limit(1);

    if ((existing as List).isNotEmpty) {
      await Supabase.instance.client
          .from('user_preferences')
          .update(payload)
          .eq('user_id', widget.userId);
    } else {
      await Supabase.instance.client.from('user_preferences').insert(payload);
    }
  }

  Future<void> _completeRegistration({int? selectedUnitId}) async {
    setState(() => isSubmitting = true);
    try {
      await _savePreferences(selectedUnitId: selectedUnitId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preferences saved'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
            backgroundColor: Colors.blue,
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MemberDashboardPage()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    return Scaffold(
      backgroundColor: kBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kPrimaryDark, kPrimary, kBg],
            stops: [0.0, 0.15, 0.15],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Find a Dayung',
                        style: TextStyle(
                          fontSize: isWide ? 24 : 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontFamily: 'Montserrat',
                          letterSpacing: 0.3,
                          shadows: const [
                            Shadow(
                              color: Colors.black26,
                              offset: Offset(0, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: kBg,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 20,
                        offset: Offset(0, -5),
                      ),
                    ],
                  ),
                  child: _buildBody(context, isWide),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, bool isWide) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }

    return RefreshIndicator(
      onRefresh: () async => _fetchSuggestions(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 2,
            color: kCardBg,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildDropdown(
                      label: 'Registration Fee Range',
                      value: contribution_amount,
                      items: [
                        'Any',
                        'Free',
                        '₱1 - ₱100',
                        '₱101 - ₱500',
                        '₱501+',
                        '₱100',
                        '₱500',
                        '₱150',
                        '₱1000',
                      ],
                      onChanged: (val) {
                        setState(() => contribution_amount = val);
                        _fetchSuggestions();
                      },
                    ),
                    _buildDropdown(
                      label: 'Membership Payment',
                      value: membership_payment,
                      items: [
                        'Any',
                        'Free',
                        '₱1 - ₱100',
                        '₱101 - ₱500',
                        '₱501+',
                        '₱100',
                        '₱500',
                        '₱150',
                        '₱1000',
                      ],
                      onChanged: (val) {
                        setState(() => membership_payment = val);
                        _fetchSuggestions();
                      },
                    ),
                    _buildDropdown(
                      label: 'Penalty Payment',
                      value: penalty_payment,
                      items: ['100', '200', '300', '500'],
                      onChanged: (val) {
                        setState(() => penalty_payment = val);
                        _fetchSuggestions();
                      },
                    ),
                    _buildDropdown(
                      label: 'Payment Method',
                      value: payment_method,
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
                        setState(() => payment_method = val);
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
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.search),
                        label: const Text('Find Matching Units'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          if (contribution_amount == null &&
                              membership_payment == null &&
                              penalty_payment == null &&
                              payment_method == null &&
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
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (suggestedUnits.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Suggested Dayung Units',
                style: TextStyle(
                  fontSize: isWide ? 20 : 18,
                  fontWeight: FontWeight.w800,
                  color: kPrimaryDark,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...suggestedUnits.map((unit) {
              return Card(
                elevation: 2,
                color: kCardBg,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            backgroundColor: kPrimary.withOpacity(0.12),
                            child: const Icon(Icons.home, color: kPrimary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  unit['name'] ?? 'Unnamed Unit',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: kText,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  [
                                        if (unit['barangay'] != null)
                                          unit['barangay'],
                                        if (unit['city'] != null) unit['city'],
                                        if (unit['province'] != null)
                                          unit['province'],
                                      ]
                                      .where(
                                        (e) => (e ?? '').toString().isNotEmpty,
                                      )
                                      .join(', '),
                                  style: const TextStyle(
                                    color: kSubText,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // --- Map preview here ---
                      Builder(
                        builder: (context) {
                          final lat = double.tryParse('${unit['latitude']}');
                          final lng = double.tryParse('${unit['longitude']}');
                          if (lat != null && lng != null) {
                            return Padding(
                              padding: const EdgeInsets.only(
                                top: 10.0,
                                bottom: 8.0,
                              ),
                              child: DayungMapPreview(
                                latitude: lat,
                                longitude: lng,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                      // --- Action buttons ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.map),
                            label: const Text('Map'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kPrimary,
                              side: const BorderSide(color: kPrimary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              final selected = Map<String, dynamic>.from(
                                unit as Map,
                              );
                              final all = suggestedUnits
                                  .map(
                                    (e) => Map<String, dynamic>.from(e as Map),
                                  )
                                  .toList();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DayungMapPage(
                                    dayung: selected,
                                    isApplied: false,
                                    isMember: false,
                                    allDayungs: all,
                                    nearbyRadiusMeters: 5000,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Select'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kPrimary,
                              side: const BorderSide(color: kPrimary),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => _completeRegistration(
                              selectedUnitId: unit['id'] as int,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ] else if (contribution_amount != null ||
              membership_payment != null ||
              penalty_payment != null ||
              payment_method != null ||
              openForAll != null ||
              fundSupportRange != null) ...[
            const SizedBox(height: 8),
            const Text(
              'No suggestions found with the given preferences.',
              style: TextStyle(color: kSubText),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Skip & Continue'),
              style: TextButton.styleFrom(
                foregroundColor: kPrimaryDark,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onPressed: () async {
                await _savePreferences();
                if (!mounted) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => const DayungSuggestionsPage(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
        items: items
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: onChanged,
        validator: (_) => null,
      ),
    );
  }
}

class DayungMapPreview extends StatelessWidget {
  final double latitude;
  final double longitude;

  const DayungMapPreview({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ml.MapLibreMap(
          styleString: 'https://demotiles.maplibre.org/style.json',
          initialCameraPosition: ml.CameraPosition(
            target: ml.LatLng(latitude, longitude),
            zoom: 14,
          ),
          onMapCreated: (ml.MaplibreMapController controller) async {
            await controller.addSymbol(
              ml.SymbolOptions(
                geometry: ml.LatLng(latitude, longitude),
                iconImage: "marker-15",
                iconSize: 1.4,
              ),
            );
          },
          myLocationEnabled: false,
          compassEnabled: false,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          scrollGesturesEnabled: false,
          zoomGesturesEnabled: false,
          attributionButtonMargins: const Point(8, 8),
          logoViewMargins: const Point(8, 8),
        ),
      ),
    );
  }
}
