// ignore_for_file: non_constant_identifier_names

import 'dart:math';

import 'package:capstone_app/Members/dashboard.dart';
import 'package:capstone_app/screens/dayung_map_page.dart';
import 'package:flutter/material.dart';
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

  double? userLat; // <-- Set this to the user's latitude
  double? userLng; // <-- Set this to the user's longitude

  double? selectedDistanceKm; // <-- Add this for distance filter

  String _digits(String? s) => (s ?? '').replaceAll(RegExp(r'[^\d]'), '');
  String _trimLower(String? s) => (s ?? '').trim().toLowerCase();

  Future<void> applyToDayungUnit(String userId, int dayungUnitId) async {
    await Supabase.instance.client.from('applications').insert({
      'user_id': userId,
      'dayung_unit_id': dayungUnitId,
      'status': 'pending',
    });
  }

  // Ang mosunod nga function nag-encode sa user preferences ngadto sa binary vector.
  // Gigamit kini para sa cosine similarity matching sa Dayung units.
  /* 28 positions
3 for meeting frequency
3 for payment method
7 for registration fee
7 for membership payment
7 for penalty payment
1 for open for all*/

  List<double> _generatePreferenceVector() {
    // Meeting Frequency (3 positions)
    double meetWeekly = meeting_frequency == 'Weekly' ? 1.0 : 0.0;
    double meetMonthly = meeting_frequency == 'Monthly' ? 1.0 : 0.0;
    double meetNeeded = meeting_frequency == 'Needed' ? 1.0 : 0.0;

    // Payment Method (3 positions)
    double payCash = payment_method == 'Cash' ? 1.0 : 0.0;
    double payGcash = payment_method == 'GCash' ? 1.0 : 0.0;
    double payBoth = payment_method == 'Both' ? 1.0 : 0.0;

    // Registration Fee Range (7 positions)
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
    ];
  }

  /// Nag-compute sa cosine similarity tali sa user preference vector `u`
  /// ug sa Dayung unit vector `d`.
  ///
  /// Formula:
  /// cosine_similarity(U, D) = (U ⋅ D) / (||U|| * ||D||)
  ///
  /// Asa:
  /// - U ⋅ D mao ang dot product sa duha ka vectors
  /// - ||U|| ug ||D|| mao ang magnitudes (gitas-on) sa vectors
  ///
  /// Ang resulta kay gikan -1 hangtod 1:
  /// - 1 → parehas kaayo (dako og similarity)
  /// - 0 → walay kalabotan
  /// - -1 → supak kaayo (opposite)
  ///
  /// Gigamit kini para i-ranggo ang Dayung units base sa kaparehas sa user preferences.
  double cosineSimilarity(List<double> u, List<double> d) {
    if (u.length != d.length || u.isEmpty) return 0.0;
    double dot = 0, magU = 0, magD = 0;
    for (int i = 0; i < u.length; i++) {
      dot += u[i] * d[i];
      magU += u[i] * u[i];
      magD += d[i] * d[i];
    }
    const eps = 1e-10;
    if (magU < eps || magD < eps) return 0.0;
    return dot / (sqrt(magU) * sqrt(magD));
  }

  // Kini nga function nag-convert sa usa ka Dayung unit row ngadto sa binary vector.
  // Kini nga vector ikumpara sa user vector gamit ang cosine similarity.
  List<double> _buildUnitVectorFromRow(Map<String, dynamic> m) {
    String norm(String? s) => (s ?? '').trim().toLowerCase();
    String clean(String? s) => norm(s).replaceAll(RegExp(r'[^a-z0-9]+'), ' ');

    final meetKey = clean(m['meeting_frequency']?.toString());
    final payKey = clean(m['payment_method']?.toString());
    final regKey = clean(m['contribution_amount']?.toString());
    final memKey = clean(m['membership_payment']?.toString());
    final penKey = clean(m['penalty_payment']?.toString());

    // open_for_all can be bool, string, or number
    final openRaw = m['open_for_all'];
    bool open = false;
    if (openRaw is bool) {
      open = openRaw;
    } else if (openRaw is num) {
      open = openRaw != 0;
    } else if (openRaw is String) {
      final s = norm(openRaw);
      open = s == 'yes' || s == 'true' || s == '1' || s == 'y';
    }

    // Meeting Frequency
    double meetW = 0, meetM = 0, meetN = 0;
    if (meetKey.contains('week')) meetW = 1;
    if (meetKey.contains('month')) meetM = 1;
    if (meetKey.contains('need')) meetN = 1;
    if (meetW + meetM + meetN == 0) meetW = meetM = meetN = 1;

    // Payment Method
    double payCash = 0, payGcash = 0, payBoth = 0;
    if (payKey.contains('both')) payBoth = payCash = payGcash = 1;
    if (payKey.contains('cash')) payCash = 1;
    if (payKey.contains('gcash')) payGcash = 1;
    if (payCash + payGcash + payBoth == 0) payCash = payGcash = payBoth = 1;

    // Helper for fee buckets
    List<String> feeRanges = [
      '50-100',
      '100-150',
      '150-200',
      '200-250',
      '250-300',
      '300-350',
      '400 plus',
    ];
    List<double> bucket(String key) {
      List<double> out = List.filled(feeRanges.length, 0.0);
      for (int i = 0; i < feeRanges.length; i++) {
        if (key.contains(feeRanges[i].replaceAll(' ', ''))) out[i] = 1.0;
      }
      if (out.every((v) => v == 0.0)) out = List.filled(feeRanges.length, 1.0);
      return out;
    }

    final regFee = bucket(regKey);
    final memFee = bucket(memKey);
    final penFee = bucket(penKey);

    final openAll = open ? 1.0 : 0.0;

    return [
      meetW,
      meetM,
      meetN,
      payCash,
      payGcash,
      payBoth,
      ...regFee,
      ...memFee,
      ...penFee,
      openAll,
    ];
  }

  // Helper function para maghimo og vector gikan sa dayung_rules row.
  // Gigamit kini para sa local similarity matching.
  List<double> _buildRuleVector(Map<String, dynamic> m) {
    String norm(String? s) => (s ?? '').trim().toLowerCase();

    // Meeting Frequency (3 positions)
    final meet = norm(m['meeting_frequency']);
    double meetWeekly = meet == 'weekly' ? 1.0 : 0.0;
    double meetMonthly = meet == 'monthly' ? 1.0 : 0.0;
    double meetNeeded = meet == 'needed' ? 1.0 : 0.0;

    // Payment Method (3 positions)
    final pay = norm(m['payment_method']);
    double payCash = pay == 'cash' ? 1.0 : 0.0;
    double payGcash = pay == 'gcash' ? 1.0 : 0.0;
    double payBoth = pay == 'both' ? 1.0 : 0.0;

    // Registration Fee Range (7 positions)
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
      if (norm(m['registration_fee_range']) == feeRanges[i]) regFee[i] = 1.0;
    }

    // Membership Payment (same buckets)
    List<double> memFee = List.filled(feeRanges.length, 0.0);
    for (int i = 0; i < feeRanges.length; i++) {
      if (norm(m['membership_payment']) == feeRanges[i]) memFee[i] = 1.0;
    }

    // Penalty Payment (same buckets)
    List<double> penFee = List.filled(feeRanges.length, 0.0);
    for (int i = 0; i < feeRanges.length; i++) {
      if (norm(m['penalty_payment']) == feeRanges[i]) penFee[i] = 1.0;
    }

    // Open For All (1 position)
    double openAll = norm(m['open_for_all']) == 'yes' ? 1.0 : 0.0;

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
    ];
  }

  // Kini nga function mopangita og Dayung units, maghimo sa ilang vectors,
  // ug mosort base sa cosine similarity sa user preference vector.
  // Dinhi gyud mahitabo ang matching ug ranking.
  Future<void> _fetchSuggestionsLocal() async {
    debugPrint(
      'DEBUG: User "${widget.userId}" (role: ${widget.role}) is searching for Dayung rules',
    );
    setState(() => isLoading = true);
    try {
      final userVector = _generatePreferenceVector();
      debugPrint(
        'DEBUG: User Preference Vector len=${userVector.length}: $userVector',
      );

      // Fetch rules joined with unit info for location
      final resp = await Supabase.instance.client
          .from('dayung_rules')
          .select(
            'id,dayung_unit_id,dayung_unit_name,meeting_frequency,registration_fee_range,membership_payment,penalty_payment,payment_method,open_for_all,'
            'dayung_units(latitude,longitude,barangay,city,province)',
          );

      final rules = <Map<String, dynamic>>[];
      for (final raw in resp) {
        final m = Map<String, dynamic>.from(raw as Map);

        // Merge unit info for location
        final unit = m['dayung_units'];
        if (unit is Map) {
          m['latitude'] = unit['latitude'];
          m['longitude'] = unit['longitude'];
          m['barangay'] = unit['barangay'];
          m['city'] = unit['city'];
          m['province'] = unit['province'];
        }

        // Build vector from rule columns
        m['__parsedVector'] = _buildRuleVector(m);

        // ADD THIS DEBUG PRINT:
        debugPrint('DEBUG: Unit ID:${m['id']} Vector: ${m['__parsedVector']}');

        rules.add(m);
      }

      // Sort by similarity * attribute match boost
      // Dinhi gigamit ang cosine similarity ug ang attributeMatchBoost para i-ranggo ang Dayung units.
      // Ang resulta kay mas taas ang score sa units nga daghan og exact match sa gipili sa user.
      rules.sort((a, b) {
        final va = (a['__parsedVector'] as List<double>? ?? const []);
        final vb = (b['__parsedVector'] as List<double>? ?? const []);
        final simA =
            cosineSimilarity(userVector, va) *
            attributeMatchBoost(userVector, va);
        final simB =
            cosineSimilarity(userVector, vb) *
            attributeMatchBoost(userVector, vb);
        return simB.compareTo(simA);
      });

      setState(() => suggestedUnits = rules);
    } catch (e) {
      debugPrint('DEBUG: Local fetch error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Local similarity error: $e')));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _fetchSuggestions() async {
    await _fetchSuggestionsLocal();
  }

  Future<void> _savePreferences({int? selectedUnitId}) async {
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
  void initState() {
    super.initState();
    selectedDistanceKm = 5;
    _fetchUserAddress();
    _fetchSuggestions();
    _fetchUserLatitude();
    _fetchUserLongitude();
  }

  String? userBarangay, userCity, userProvince;

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
    if (userBarangay == null || userCity == null || userProvince == null)
      return;
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
                      color: Colors.white.withOpacity(0.85),
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

  // Helper function para sa attribute match boost
  // Kini nga function nag-compute og "boost" score base sa pila ka user-selected features (1s sa user vector)
  // nga nag-match pud sa Dayung unit vector. Gigamit ang formula:
  // AttributeMatch(U, D) = 1 + λ * (#matched_selected / #selected)
  // Asa:
  // - #matched_selected = pila ka features nga 1 sa user vector ug 1 pud sa unit vector (nagmatch)
  // - #selected = total nga 1s sa user vector (user-selected features)
  // - λ = boost factor (default 0.25)
  // Ang resulta kay gamultiply sa cosine similarity score para mahatagan og extra weight ang units nga daghan og exact match sa gipili sa user.
  double attributeMatchBoost(
    List<double> user,
    List<double> unit, {
    double lambda = 0.25,
  }) {
    int selected = 0;
    int matched = 0;
    for (int i = 0; i < user.length; i++) {
      if (user[i] == 1.0) {
        selected++;
        if (unit[i] == 1.0) matched++;
      }
    }
    if (selected == 0) return 1.0;
    return 1.0 + lambda * (matched / selected);
  }

  Widget _buildBody(BuildContext context, bool isWide) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }

    // Filter units by distance if user location and filter are set
    List<dynamic> filteredUnits = suggestedUnits;
    if (userLat != null &&
        userLng != null &&
        selectedDistanceKm != null &&
        selectedDistanceKm! > 0) {
      filteredUnits = suggestedUnits.where((unit) {
        final lat = double.tryParse('${unit['latitude']}');
        final lng = double.tryParse('${unit['longitude']}');
        if (lat == null || lng == null) return false;
        final dist = _distanceKm(userLat!, userLng!, lat, lng);

        // DEBUG: Show distance computation for each unit
        debugPrint(
          'DEBUG: Distance filter: User (${userLat!.toStringAsFixed(6)}, ${userLng!.toStringAsFixed(6)}) '
          '→ Unit ID:${unit['id']} (${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}) = '
          '${dist.toStringAsFixed(2)} km (threshold: ${selectedDistanceKm!.toStringAsFixed(2)} km) '
          '${dist <= selectedDistanceKm! ? "[INCLUDED]" : "[EXCLUDED]"}',
        );

        return dist <= selectedDistanceKm!;
      }).toList();
    }

    // Filter out units with similarity below threshold
    // Dinhi gigamit ang cosine similarity ug attributeMatchBoost para maapil ra ang units nga taas og combined score.
    const double similarityThreshold = 0.300; // mao ni ang threshold
    filteredUnits = filteredUnits.where((unit) {
      final sim = cosineSimilarity(
        _generatePreferenceVector(),
        (unit['__parsedVector'] as List<double>? ?? []),
      );
      final boost = attributeMatchBoost(
        _generatePreferenceVector(),
        (unit['__parsedVector'] as List<double>? ?? []),
      );
      final combinedScore = sim * boost;
      // Ipakita sa debug console ang similarity, boost, ug combined score para sa matag unit
      debugPrint(
        'DEBUG: Unit ID:${unit['id']} Similarity=${sim.toStringAsFixed(3)} Boost=${boost.toStringAsFixed(3)} Combined=${combinedScore.toStringAsFixed(3)}',
      );
      return combinedScore >= similarityThreshold;
    }).toList();

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
                      onChanged: (v) => setState(() => meeting_frequency = v),
                    ),
                    _buildDropdown(
                      label: 'Payment Method',
                      items: ['Cash', 'GCash', 'Both'],
                      value: payment_method,
                      onChanged: (v) => setState(() => payment_method = v),
                    ),
                    _buildDropdown(
                      label: 'Registration Fee',
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
                      onChanged: (v) => setState(() => contribution_amount = v),
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
                      onChanged: (v) => setState(() => membership_payment = v),
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
                      onChanged: (v) => setState(() => penalty_payment = v),
                    ),
                    _buildDropdown(
                      label: 'Open for All',
                      items: ['Yes', 'No'],
                      value: openForAll,
                      onChanged: (v) => setState(() => openForAll = v),
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
                          backgroundColor: kAccent.withOpacity(0.10),
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
                                  dayung: unit,
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
                    color: kSubText.withOpacity(0.25),
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
                    'Try adjusting your preferences or distance filter.',
                    style: TextStyle(
                      color: kSubText.withOpacity(0.7),
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
              onPressed: () async {
                await _savePreferences();
                if (!mounted) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => const MemberDashboardPage(),
                  ),
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
      return _StaticOsmTilePreview(
        latitude: latitude,
        longitude: longitude,
        height: 120,
        zoom: 14,
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
          onMapCreated: (ml.MaplibreMapController? controller) async {
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

class _StaticOsmTilePreview extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double height;
  final int zoom;

  const _StaticOsmTilePreview({
    required this.latitude,
    required this.longitude,
    this.height = 120,
    this.zoom = 14,
  });

  (int x, int y) _latLngToTile(double lat, double lon, int z) {
    final n = pow(2.0, z).toDouble();
    final xtile = ((lon + 180.0) / 360.0 * n).floor();
    final latRad = lat * pi / 180.0;
    final ytile = ((1.0 - (log(tan(latRad) + 1 / cos(latRad)) / pi)) / 2.0 * n)
        .floor();
    return (xtile, ytile);
  }

  @override
  Widget build(BuildContext context) {
    final (x, y) = _latLngToTile(latitude, longitude, zoom);
    final url = 'https://tile.openstreetmap.org/$zoom/$x/$y.png';

    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
            ),
            // Center marker overlay
            const IgnorePointer(
              child: Center(
                child: Icon(
                  Icons.location_on,
                  color: Colors.redAccent,
                  size: 28,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/*
  EXPLANATION SA DEBUG OUTPUT:

  Pananglitan:
  DEBUG: User Preference Vector len=28: [0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
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