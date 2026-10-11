// ignore_for_file: non_constant_identifier_names

import 'dart:math';

import 'package:capstone_app/profile/dayung_profile.dart';
import 'package:capstone_app/screens/dayung_map_page.dart';
import 'package:capstone_app/Providers/role_router.dart';
import 'package:capstone_app/utils/dayung_recommendations.dart';
import 'package:capstone_app/utils/dayung_service_tags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'dart:convert';

const Color kPrimary = Color(0xFF3B82F6);
const Color kPrimaryDark = Color(0xFF1E40AF);
const Color kAccent = Color(0xFF10B981);
const Color kWarn = Color(0xFFF59E0B);
const Color kDanger = Color(0xFFEF4444);
const Color kBg = Color(0xFFF8FAFC);
const Color kCardBg = Color(0xFFFFFFFF);
const Color kSubText = Color(0xFF6B7280);
const Color kText = Color(0xFF111827);
const Color kBorderColor = Color(0xFFE5E7EB);

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
  String? meeting_frequency;
  String? penalty_policy;
  List<dynamic> suggestedUnits = [];
  bool isLoading = false;
  bool isSubmitting = false;
  int _suggestionRequestId = 0;
  final Map<String, bool> selectedServiceTags = {};

  double? userLat; // <-- Set this to the user's latitude
  double? userLng; // <-- Set this to the user's longitude

  double? selectedDistanceKm; // <-- Add this for distance filter

  Future<void> applyToDayungUnit(String userId, int dayungUnitId) async {
    await Supabase.instance.client.from('applications').insert({
      'user_id': userId,
      'dayung_unit_id': dayungUnitId,
      'status': 'pending',
    });
  }

  // Helper to get the correct dayung_unit_id from a unit map
  int? getDayungUnitId(Map<String, dynamic> unit) {
    final raw = unit['dayung_unit_id'] ?? unit['id'];
    if (raw is int) return raw;
    return int.tryParse('$raw');
  }

  // Ang mosunod nga function nag-encode sa user preferences ngadto sa binary vector.
  // Gigamit kini para sa cosine similarity matching sa Dayung units.
  /* 37 positions
3 for meeting frequency
3 for payment method
7 for registration fee
7 for membership payment
7 for penalty payment
1 for open for all
9 for support services*/

  List<double> _generatePreferenceVector() {
    // Meeting Frequency (3 positions)
    double meetWeekly = meeting_frequency == 'Weekly' ? 1.0 : 0.0;
    double meetMonthly = meeting_frequency == 'Monthly' ? 1.0 : 0.0;
    double meetNeeded = meeting_frequency == 'Needed' ? 1.0 : 0.0;

    // Payment Method (3 positions)
    double payCash = payment_method == 'Cash' ? 1.0 : 0.0;
    double payGcash = payment_method == 'GCash' ? 1.0 : 0.0;
    double payBoth = payment_method == 'Both' ? 1.0 : 0.0;

    List<String> feeRanges = [
      '50-100',
      '100-150',
      '150-200',
      '200-250',
      '250-300',
      '300-350',
      '400 plus',
    ];
    List<double> regFee = List.filled(feeRanges.length, 0.0);
    for (int i = 0; i < feeRanges.length; i++) {
      if (contribution_amount == feeRanges[i]) regFee[i] = 1.0;
    }

    // Membership Payment (same buckets)
    List<double> memFee = List.filled(feeRanges.length, 0.0);
    for (int i = 0; i < feeRanges.length; i++) {
      if (membership_payment == feeRanges[i]) memFee[i] = 1.0;
    }

    // Penalty Payment (same buckets)
    List<double> penFee = List.filled(feeRanges.length, 0.0);
    for (int i = 0; i < feeRanges.length; i++) {
      if (penalty_payment == feeRanges[i]) penFee[i] = 1.0;
    }

    // Open For All (1 position)
    double openAll = openForAll == 'Yes' ? 1.0 : 0.0;

    final serviceTagVector = dayungServiceTagLabels.map((label) {
      return selectedServiceTags[label] == true ? 1.0 : 0.0;
    }).toList();

    return [
      meetWeekly,
      meetMonthly,
      meetNeeded,
      payCash,
      payGcash,
      payBoth,
      ...regFee,
      ...memFee,
      ...penFee,
      openAll,
      ...serviceTagVector,
    ];
  }

  Future<void> _fetchSuggestionsLocal() async {
    final requestId = ++_suggestionRequestId;
    debugPrint(
      'DEBUG: User "${widget.userId}" (role: ${widget.role}) is searching for Dayung rules',
    );
    setState(() => isLoading = true);
    try {
      final userVector = _generatePreferenceVector();
      debugPrint(
        'DEBUG: User Preference Vector len=${userVector.length}: $userVector',
      );
      final matches = await DayungRecommendationService.matchPreferenceVector(
        Supabase.instance.client,
        preferenceVector: userVector,
        similarityThreshold: 0.3,
      );
      if (!mounted || requestId != _suggestionRequestId) return;
      setState(() => suggestedUnits = matches);
    } catch (e) {
      debugPrint('DEBUG: Local fetch error: $e');
      if (!mounted || requestId != _suggestionRequestId) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local similarity error: $e')));
    } finally {
      if (mounted && requestId == _suggestionRequestId) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _fetchSuggestions() async {
    await _fetchSuggestionsLocal();
  }

  Future<void> _savePreferences({int? selectedUnitId}) async {
    setState(() => isSubmitting = true);
    try {
      final payload = {
        'user_id': widget.userId,
        'meeting_frequency': meeting_frequency,
        'penalty_policy': penalty_policy,
        'contribution_amount': contribution_amount,
        'membership_payment': membership_payment,
        'penalty_payment': penalty_payment,
        'payment_method': payment_method,
        'open_for_all': openForAll == null ? null : (openForAll == 'Yes'),
        'selected_unit_id': selectedUnitId,
        for (final label in dayungServiceTagLabels)
          dayungServiceTagColumns[label]!: selectedServiceTags[label] ?? false,
      };

      final existing = await Supabase.instance.client
          .from('user_preferences')
          .select('id')
          .eq('user_id', widget.userId)
          .limit(1)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => <Map<String, dynamic>>[],
          );

      if ((existing as List).isNotEmpty) {
        await Supabase.instance.client
            .from('user_preferences')
            .update(payload)
            .eq('user_id', widget.userId)
            .timeout(const Duration(seconds: 10), onTimeout: () => <dynamic>[]);
      } else {
        await Supabase.instance.client
            .from('user_preferences')
            .insert(payload)
            .timeout(const Duration(seconds: 10), onTimeout: () => <dynamic>[]);
      }
    } catch (e, st) {
      debugPrint('Save preferences failed: $e\n$st');
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    selectedDistanceKm = 5;
    _loadSavedServicePreferences();
    _fetchUserAddress();
    _fetchSuggestions();
    _fetchUserLatitude();
    _fetchUserLongitude();
  }

  String? userBarangay, userCity, userProvince;

  Future<void> _loadSavedServicePreferences() async {
    try {
      final resp = await Supabase.instance.client
          .from('user_preferences')
          .select(
            dayungServiceTagLabels
                .map((label) => dayungServiceTagColumns[label]!)
                .join(','),
          )
          .eq('user_id', widget.userId)
          .maybeSingle();

      if (resp == null) return;
      if (!mounted) return;

      setState(() {
        for (final label in dayungServiceTagLabels) {
          final column = dayungServiceTagColumns[label]!;
          selectedServiceTags[label] = resp[column] == true;
        }
      });
      await _fetchSuggestions();
    } catch (e) {
      debugPrint('Failed to load saved service preferences: $e');
    }
  }

  Future<void> _fetchUserAddress() async {
    try {
      final resp = await Supabase.instance.client
          .from('users')
          .select('barangay,city,province,latitude,longitude')
          .eq('id', widget.userId)
          .single();
      setState(() {
        userBarangay = resp['barangay'];
        userCity = resp['city'];
        userProvince = resp['province'];
        userLat = resp['latitude'] != null
            ? double.tryParse('${resp['latitude']}')
            : null;
        userLng = resp['longitude'] != null
            ? double.tryParse('${resp['longitude']}')
            : null;
      });
      if (userLat == null || userLng == null) {
        await geocodeAndSaveUserLocation();
      }
      debugPrint(
        'DEBUG: User Address for ID ${widget.userId}: '
        'Barangay: $userBarangay, City: $userCity, Province: $userProvince, '
        'Latitude: $userLat, Longitude: $userLng',
      );
    } catch (e) {
      debugPrint('Failed to fetch user address: $e');
    }
  }

  Future<void> _fetchUserLatitude() async {
    try {
      final resp = await Supabase.instance.client
          .from('users')
          .select('latitude')
          .eq('id', widget.userId)
          .single();
      setState(() {
        userLat = resp['latitude'] != null
            ? double.tryParse('${resp['latitude']}')
            : null;
      });
      debugPrint('DEBUG: User Latitude for ID ${widget.userId}: $userLat');
    } catch (e) {
      debugPrint('Failed to fetch user latitude: $e');
    }
  }

  Future<void> _fetchUserLongitude() async {
    try {
      final resp = await Supabase.instance.client
          .from('users')
          .select('longitude')
          .eq('id', widget.userId)
          .single();
      setState(() {
        userLng = resp['longitude'] != null
            ? double.tryParse('${resp['longitude']}')
            : null;
      });
      debugPrint('DEBUG: User Longitude for ID ${widget.userId}: $userLng');
    } catch (e) {
      debugPrint('Failed to fetch user longitude: $e');
    }
  }

  Future<void> geocodeAndSaveUserLocation() async {
    if (userBarangay == null || userCity == null || userProvince == null) {
      return;
    }
    final address =
        '${userBarangay!}, ${userCity!}, ${userProvince!}, Philippines';
    final url =
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(address)}&format=json&limit=1';
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'capstone-app/1.0 (your@email.com)'},
      );
      if (response.statusCode == 200) {
        final results = json.decode(response.body);
        if (results is List && results.isNotEmpty) {
          final lat = double.tryParse(results[0]['lat']);
          final lon = double.tryParse(results[0]['lon']);
          if (lat != null && lon != null) {
            // Save to users table
            await Supabase.instance.client
                .from('users')
                .update({'latitude': lat, 'longitude': lon})
                .eq('id', widget.userId);
            setState(() {
              userLat = lat;
              userLng = lon;
            });
            debugPrint('Geocoded: $address → $lat, $lon');
          }
        }
      }
    } catch (e) {
      debugPrint('Geocoding failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Modern Curved Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 36),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kPrimaryDark, kPrimary],
                ),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(32),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dayung Preferences',
                    style: TextStyle(
                      fontSize: isWide ? 28 : 22,
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
                  const SizedBox(height: 8),
                  Text(
                    'Set your preferences to get the best Dayung unit suggestions.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 15,
                      fontFamily: 'OpenSans',
                    ),
                  ),
                ],
              ),
            ),
            // Main Content
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: kBg,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: _buildBody(context, isWide),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Haversine formula for distance in km
  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLng = (lng2 - lng1) * pi / 180.0;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) *
            cos(lat2 * pi / 180.0) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  List<dynamic> _rankPassingUnits(List<dynamic> units) {
    const double similarityThreshold = 0.300;
    final eligible = <Map<String, dynamic>>[];

    for (final unit in units) {
      final score = (unit['__score'] as num?)?.toDouble() ?? 0.0;
      if (score < similarityThreshold) continue;

      final lat = double.tryParse('${unit['latitude']}');
      final lng = double.tryParse('${unit['longitude']}');
      double? distanceKm;
      if (userLat != null && userLng != null && lat != null && lng != null) {
        distanceKm = _distanceKm(userLat!, userLng!, lat, lng);
      }

      eligible.add({
        ...Map<String, dynamic>.from(unit as Map),
        '__hybridScore': score,
        '__distanceKm': distanceKm,
      });
    }

    final nearEligible = selectedDistanceKm != null && selectedDistanceKm! > 0
        ? eligible.where((unit) {
            final distance = unit['__distanceKm'] as double?;
            return distance != null && distance <= selectedDistanceKm!;
          }).toList()
        : <Map<String, dynamic>>[];

    final rankedSource = nearEligible.isNotEmpty ? nearEligible : eligible;

    rankedSource.sort((a, b) {
      final distanceA = (a['__distanceKm'] as num?)?.toDouble();
      final distanceB = (b['__distanceKm'] as num?)?.toDouble();

      if (distanceA != null && distanceB != null) {
        final distanceCmp = distanceA.compareTo(distanceB);
        if (distanceCmp != 0) return distanceCmp;
      } else if (distanceA != null && distanceB == null) {
        return -1;
      } else if (distanceA == null && distanceB != null) {
        return 1;
      }

      final scoreCmp = ((b['__hybridScore'] as num?) ?? 0).compareTo(
        (a['__hybridScore'] as num?) ?? 0,
      );
      if (scoreCmp != 0) return scoreCmp;

      return (a['dayung_unit_name'] ?? a['id'] ?? '').toString().compareTo(
        (b['dayung_unit_name'] ?? b['id'] ?? '').toString(),
      );
    });

    return rankedSource.take(3).toList();
  }

  Widget _buildBody(BuildContext context, bool isWide) {
    if (isLoading && suggestedUnits.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }

    final filteredUnits = _rankPassingUnits(suggestedUnits);

    return RefreshIndicator(
      onRefresh: () async => _fetchSuggestions(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        children: [
          // Preferences Form Card
          Card(
            elevation: 4,
            color: kCardBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildDropdown(
                      label: 'Meeting Frequency',
                      items: ['Weekly', 'Monthly', 'Needed'],
                      value: meeting_frequency,
                      onChanged: (v) {
                        setState(() => meeting_frequency = v);
                        _fetchSuggestions();
                      },
                    ),
                    _buildDropdown(
                      label: 'Payment Method',
                      items: ['Cash', 'GCash', 'Both'],
                      value: payment_method,
                      onChanged: (v) {
                        setState(() => payment_method = v);
                        _fetchSuggestions();
                      },
                    ),
                    _buildDropdown(
                      label: 'Collection Fee',
                      items: [
                        '50-100',
                        '100-150',
                        '150-200',
                        '200-250',
                        '250-300',
                        '300-350',
                        '400 plus',
                      ],
                      value: contribution_amount,
                      onChanged: (v) {
                        setState(() => contribution_amount = v);
                        _fetchSuggestions();
                      },
                    ),
                    _buildDropdown(
                      label: 'Membership Payment',
                      items: [
                        '50-100',
                        '100-150',
                        '150-200',
                        '200-250',
                        '250-300',
                        '300-350',
                        '400 plus',
                      ],
                      value: membership_payment,
                      onChanged: (v) {
                        setState(() => membership_payment = v);
                        _fetchSuggestions();
                      },
                    ),
                    _buildDropdown(
                      label: 'Penalty Payment',
                      items: [
                        '50-100',
                        '100-150',
                        '150-200',
                        '200-250',
                        '250-300',
                        '300-350',
                        '400 plus',
                      ],
                      value: penalty_payment,
                      onChanged: (v) {
                        setState(() => penalty_payment = v);
                        _fetchSuggestions();
                      },
                    ),
                    _buildDropdown(
                      label: 'Open for All',
                      items: ['Yes', 'No'],
                      value: openForAll,
                      onChanged: (v) {
                        setState(() => openForAll = v);
                        _fetchSuggestions();
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Preferred Support Services',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: kPrimaryDark,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Select the support services you want.',
                        style: TextStyle(
                          fontSize: 13,
                          color: kSubText,
                          fontFamily: 'OpenSans',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: dayungServiceTagLabels.map((label) {
                        return FilterChip(
                          label: Text(label),
                          selected: selectedServiceTags[label] ?? false,
                          onSelected: (value) {
                            setState(() {
                              selectedServiceTags[label] = value;
                            });
                            _fetchSuggestions();
                          },
                          side: const BorderSide(color: kBorderColor),
                          selectedColor: kPrimary.withValues(alpha: 0.16),
                          checkmarkColor: kPrimary,
                        );
                      }).toList(),
                    ),
                    // const SizedBox(height: 18),
                    // Distance Filter Slider
                    // Row(
                    //   children: [
                    //     const Icon(Icons.location_on, color: kPrimaryDark),
                    //     const SizedBox(width: 8),
                    //     Expanded(
                    //       child: Slider(
                    //         value: selectedDistanceKm ?? 5,
                    //         min: 1,
                    //         max: 20,
                    //         divisions: 19,
                    //         label:
                    //             '${selectedDistanceKm?.toStringAsFixed(0) ?? 5} km',
                    //         activeColor: kPrimary,
                    //         onChanged: (v) =>
                    //             setState(() => selectedDistanceKm = v),
                    //       ),
                    //     ),
                    //     Text(
                    //       '${selectedDistanceKm?.toStringAsFixed(0) ?? 5} km',
                    //       style: const TextStyle(
                    //         color: kPrimaryDark,
                    //         fontWeight: FontWeight.bold,
                    //       ),
                    //     ),
                    //   ],
                    // ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Suggestions List
          if (filteredUnits.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Suggested Dayung Units',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: kPrimaryDark,
                  fontSize: 17,
                  fontFamily: 'Montserrat',
                ),
              ),
            ),
            ...filteredUnits.map((unit) {
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: Card(
                  elevation: 4,
                  color: kCardBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: kAccent.withValues(alpha: 0.10),
                          child: const Icon(
                            Icons.home,
                            color: kAccent,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                unit['dayung_unit_name'] ?? 'Unnamed Unit',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: kText,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                [
                                      if (unit['barangay'] != null)
                                        unit['barangay'],
                                      if (unit['city'] != null) unit['city'],
                                      if (unit['province'] != null)
                                        unit['province'],
                                    ]
                                    .where(
                                      (e) =>
                                          e != null && e.toString().isNotEmpty,
                                    )
                                    .join(', '),
                                style: const TextStyle(
                                  color: kSubText,
                                  fontSize: 14,
                                  fontFamily: 'OpenSans',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.map, color: Colors.white),
                          label: const Text(
                            'Map',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            final lat = unit['latitude'] as double?;
                            final lng = unit['longitude'] as double?;
                            if (lat == null || lng == null) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'No location set for this Dayung.',
                                  ),
                                ),
                              );
                              return;
                            }
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DayungMapPage(
                                  dayung: {
                                    ...unit,
                                    // Always ensure dayung_unit_id is present and used
                                    'dayung_unit_id': getDayungUnitId(unit),
                                  },
                                  isApplied: false,
                                  isMember: false,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ] else if (contribution_amount != null ||
              membership_payment != null ||
              penalty_payment != null ||
              payment_method != null ||
              openForAll != null ||
              penalty_policy != null) ...[
            const SizedBox(height: 32),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.search_off,
                    size: 64,
                    color: kSubText.withValues(alpha: 0.25),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'No suggestions found with the given preferences.',
                    style: TextStyle(
                      color: kSubText,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Units may disappear when their hybrid score is below 0.3 or when they fall outside the selected distance range.',
                    style: TextStyle(
                      color: kSubText.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Modern Skip Button
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.arrow_forward, color: Colors.white),
              label: const Text(
                'Skip & Continue',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  fontFamily: 'Montserrat',
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 2,
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final navigator = Navigator.of(context);
                      await _savePreferences();
                      if (!mounted) return;
                      Widget destination = const RoleRouter();
                      final user = Supabase.instance.client.auth.currentUser;
                      if (user != null) {
                        try {
                          final profile = await Supabase.instance.client
                              .from('users')
                              .select('dayung_unit_id')
                              .eq('id', user.id)
                              .maybeSingle();
                          if (profile?['dayung_unit_id'] == null) {
                            destination = const DayungSettingsPage();
                          }
                        } catch (_) {}
                      }
                      if (!mounted) return;
                      navigator.pushReplacement(
                        MaterialPageRoute(builder: (_) => destination),
                      );
                    },
            ),
          ),
        ],
      ),
    );
  }
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
      initialValue: value ?? items.first,
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
    if (kIsWeb) {
      return SizedBox(
        height: 120,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: FlutterMap(
            options: MapOptions(
              initialCenter: ll.LatLng(latitude, longitude),
              initialZoom: 14,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'capstone_app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: ll.LatLng(latitude, longitude),
                    width: 36,
                    height: 36,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.redAccent,
                      size: 28,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

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
          onMapCreated: (ml.MapLibreMapController? controller) async {
            if (controller == null) return;
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

/*
  EXPLANATION SA DEBUG OUTPUT:

  Pananglitan:
  DEBUG: User Preference Vector len=37: [preference values, including 9 service-tag positions]
  DEBUG: Unit ID:1 Similarity=0.632 Boost=1.250 Combined=0.791

  - Ang "User Preference Vector" nagpakita sa mga gipili sa user nga features (1 = gipili, 0 = wala).
  - Ang "Similarity" (0.632) mao ang cosine similarity score tali sa user vector ug sa unit vector, nagbase kung pila ka features ang nagmatch.
    > Gikuha ang dot product sa user vector ug unit vector (pila ka positions nga pareho og 1).
    > Gidivide sa product sa ilang magnitudes (gitas-on sa vector).
    > Pananglitan, kung ang unit vector kay [0, 1, 0, 0, 0, 0, 1, ...] pud:
    > Dot product = 1 (sa pos 1) + 1 (sa pos 6) = 2
    > Magnitude sa user vector = √(1² + 1²) = √2 ≈ 1.414
    > Magnitude sa unit vector = depende sa pila ka 1s, pananglitan √5 ≈ 2.236
    > Cosine similarity = 2 / (1.414 × 2.236) ≈ 0.632
  - Ang "Boost" (1.250) kay extra factor nga nagdepende kung pila ka gipili sa user nga na-match gyud sa unit (formula: 1 + λ * 
  (#matched_selected / #selected), default λ=0.25).
  - Ang "Combined" (0.791) mao ang final score nga gigamit para i-ranggo ug i-filter ang units: Similarity × Boost.
  - Mas taas ang combined score, mas dako ang posibilidad nga ang unit mo-fit sa user preferences.
*/

/* SIMILARITY EXPLANATION:
pila ang unit na tugma sa user \ (number of 1s sa user then squarerooted) * (number of 1s sa unit then squarerted)
example: 3 / (2.236 * 2.236) = 0.600

BOOST EXPLANATION:
1 + 0.25 x (pila ang unit na tugma sa user / number of 1s sa user)

COMBINE EXPLANATION::
similarity x boost = combined score
*/

/*GET THE KM

EXAMPLE:

lat2 − lat1 = 7.103253 − 7.058006 = 0.045247°
Distance ≈ 0.045247 × 111 ≈ 5.022 km   
lon2 − lon1 = 125.607820 − 125.608528 = -0.000708°
Distance ≈ 0.000708 × (111 × cos(7°)) ≈ 0.078 km   

Comparison:
Latitude difference → ~5.02 km
Longitude difference → ~0.08 km  

Conclusion:
The distance is almost entirely determined by the latitude difference. 
The longitude difference has a very small effect.*/
