import 'dart:convert';
import 'dart:math';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/screens/dayung_suggestions.dart'
    hide kPrimary, kAccent, kWarn;
import 'package:capstone_app/screens/selectdayung.dart'
    hide kPrimary, kWarn, kAccent;
import 'package:capstone_app/screens/dayung_map_page.dart' as map;
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Additional colors for manage dayung styling
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimaryLight = Color(0xFF3B82F6);
const kAccentDark = Color(0xFF047857);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);
const double kEdge = 16;

class DayungProfile extends StatefulWidget {
  const DayungProfile({super.key});

  @override
  State<DayungProfile> createState() => _DayungProfileState();
}

class _DayungProfileState extends State<DayungProfile> with RouteAware {
  int? _currentDayungId;
  String? _currentDayungName;
  Map<String, dynamic>? _currentDayungData;
  bool _loadingDayung = false;
  // Preferences state
  bool _loadingPrefs = false;
  bool _savingPrefs = false;

  // NEW: align fields with dayungquestion.dart
  String? _prefMeetingFrequency; // meeting_frequency
  String?
  _prefContributionAmount; // contribution_amount (registration fee range)
  String? _prefMembershipPayment; // membership_payment
  String? _prefPenaltyPayment; // penalty_payment
  String? _prefPenaltyPolicy; // penalty_policy

  // Legacy / filter fields (still used by _loadRecommendations)
  String? _prefFeeRange; // kept, but driven from _prefContributionAmount
  String? _prefPaymentMethod;
  bool? _prefOpenForAll;
  String? _prefFundSupportRange;
  bool _loadingRecs = false;
  List<Map<String, dynamic>> _recommendedUnits = [];
  String? _prefLocation;

  // Location for distance filter (5 km)
  double? _userLat;
  double? _userLng;

  // Same defaults as in dayungquestion.dart
  static const double kSimilarityThreshold = 0.300;
  static const double kMaxDistanceKm = 6.0;

  bool _loadingApplied = false;
  List<Map<String, dynamic>> _appliedDayungs = [];
  String? _appliedDebug;

  String _digits(String? s) => (s ?? '').replaceAll(RegExp(r'[^\d]'), '');
  String _trimLower(String? s) => (s ?? '').trim().toLowerCase();

  // ---- Matching helpers (ported from dayungquestion.dart) ----
  List<double> _generatePreferenceVector() {
    // Meeting Frequency (Weekly, Monthly, Needed)
    double meetWeekly = _prefMeetingFrequency == 'Weekly' ? 1.0 : 0.0;
    double meetMonthly = _prefMeetingFrequency == 'Monthly' ? 1.0 : 0.0;
    double meetNeeded = _prefMeetingFrequency == 'Needed' ? 1.0 : 0.0;

    // Payment Method (Cash, GCash, Both)
    double payCash = _prefPaymentMethod == 'Cash' ? 1.0 : 0.0;
    double payGcash = _prefPaymentMethod == 'GCash' ? 1.0 : 0.0;
    double payBoth = _prefPaymentMethod == 'Both' ? 1.0 : 0.0;

    // Buckets
    final feeRanges = [
      '50-100',
      '100-150',
      '150-200',
      '200-250',
      '250-300',
      '300-350',
      '400 plus',
    ];
    List<double> bucket(String? selected) {
      final out = List<double>.filled(feeRanges.length, 0.0);
      for (int i = 0; i < feeRanges.length; i++) {
        if (selected == feeRanges[i]) out[i] = 1.0;
      }
      return out;
    }

    final regFee = bucket(_prefContributionAmount);
    final memFee = bucket(_prefMembershipPayment);
    final penFee = bucket(_prefPenaltyPayment);

    // Open For All
    double openAll = (_prefOpenForAll == true) ? 1.0 : 0.0;

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

  List<double> _buildRuleVector(Map<String, dynamic> m) {
    String norm(String? s) => (s ?? '').trim().toLowerCase();
    // Meeting Frequency
    final meet = norm(m['meeting_frequency']);
    double meetWeekly = meet == 'weekly' ? 1.0 : 0.0;
    double meetMonthly = meet == 'monthly' ? 1.0 : 0.0;
    double meetNeeded = meet == 'needed' ? 1.0 : 0.0;
    // Payment Method
    final pay = norm(m['payment_method']);
    double payCash = pay == 'cash' ? 1.0 : 0.0;
    double payGcash = pay == 'gcash' ? 1.0 : 0.0;
    double payBoth = pay == 'both' ? 1.0 : 0.0;
    // Buckets
    final feeRanges = [
      '50-100',
      '100-150',
      '150-200',
      '200-250',
      '250-300',
      '300-350',
      '400 plus',
    ];
    List<double> bucket(String? v) {
      final out = List<double>.filled(feeRanges.length, 0.0);
      for (int i = 0; i < feeRanges.length; i++) {
        if (norm(v) == feeRanges[i]) out[i] = 1.0;
      }
      return out.every((e) => e == 0.0)
          ? List<double>.filled(feeRanges.length, 1.0)
          : out;
    }

    final regFee = bucket(m['registration_fee_range']);
    final memFee = bucket(m['membership_payment']);
    final penFee = bucket(m['penalty_payment']);
    // Open For All
    final openAll = norm('${m['open_for_all']}') == 'yes' ? 1.0 : 0.0;
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

  // Haversine distance in km
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
  // ------------------------------------------------------------

  List<String> get _prefsTags {
    final tags = <String>[];
    final prefFields = {
      'Meeting Frequency': _prefMeetingFrequency,
      'Contribution Amount': _prefContributionAmount,
      'Membership Payment': _prefMembershipPayment,
      'Penalty Payment': _prefPenaltyPayment,
      'Penalty Policy': _prefPenaltyPolicy,
      'Payment Method': _prefPaymentMethod,
      'Open For All': _prefOpenForAll == null
          ? null
          : (_prefOpenForAll! ? 'Yes' : 'No'),
      'Fee Range': _prefFeeRange,
      'Fund Support Range': _prefFundSupportRange,
      'Location': _prefLocation,
    };
    prefFields.forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) {
        tags.add('$k: $v');
      }
    });
    return tags.isEmpty ? ['No preferences set'] : tags;
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentDayung();
    _loadPreferences().then((_) async {
      await _fetchUserLatLng();
      await _loadRecommendations();
    });
    _loadAppliedDayungs();
  }

  Future<void> _fetchUserLatLng() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final resp = await supabase
          .from('users')
          .select('latitude,longitude')
          .eq('id', user.id)
          .maybeSingle();
      setState(() {
        _userLat = resp?['latitude'] != null
            ? double.tryParse('${resp?['latitude']}')
            : null;
        _userLng = resp?['longitude'] != null
            ? double.tryParse('${resp?['longitude']}')
            : null;
      });
    } catch (_) {}
  }

  Future<void> _loadAppliedDayungs() async {
    setState(() {
      _loadingApplied = true;
      _appliedDebug = null;
    });
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loadingApplied = false;
        _appliedDayungs = [];
        _appliedDebug = 'No user.';
      });
      return;
    }

    try {
      final rows = await supabase
          .from('applications')
          .select('id,status,applied_at,name,dayung_unit_id,dayung_units(name)')
          .eq('user_id', user.id)
          .eq('status', 'pending')
          .order('applied_at', ascending: false);

      final list = (rows as List).map((r) => Map<String, dynamic>.from(r)).map((
        r,
      ) {
        final fallback = (r['dayung_units'] is Map && r['dayung_units'] != null)
            ? r['dayung_units']['name']
            : null;
        r['display_name'] = (r['name'] as String?)?.trim().isNotEmpty == true
            ? r['name']
            : (fallback ?? 'Unknown Dayung');
        return r;
      }).toList();

      setState(() {
        _appliedDayungs = list;
        if (list.isEmpty) {
          _appliedDebug = '';
        }
      });
    } on PostgrestException catch (e) {
      setState(() {
        _appliedDayungs = [];
        _appliedDebug = 'Postgrest: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _appliedDayungs = [];
        _appliedDebug = 'Error: $e';
      });
    } finally {
      setState(() => _loadingApplied = false);
    }
  }

  Future<void> _loadRecommendations() async {
    setState(() => _loadingRecs = true);
    final supabase = Supabase.instance.client;

    try {
      debugPrint(
        'DEBUG: Loading recommendations. userLat=$_userLat, userLng=$_userLng',
      );

      // 1) Build user vector (same style as QuestionnaireScreen)
      final userVec = _generatePreferenceVector();
      debugPrint(
        'DEBUG: User preference vector len=${userVec.length}: $userVec',
      );

      // 2) Fetch rules + unit location
      final rows = await supabase
          .from('dayung_rules')
          .select(
            'id, dayung_unit_id, dayung_unit_name, meeting_frequency, '
            'registration_fee_range, membership_payment, penalty_payment, '
            'payment_method, open_for_all, '
            'dayung_units(latitude,longitude,barangay,city,province)',
          );

      final out = <Map<String, dynamic>>[];

      for (final r in rows as List) {
        final m = Map<String, dynamic>.from(r as Map);

        // Merge location from dayung_units
        final unit = m['dayung_units'];
        if (unit is Map) {
          m['latitude'] = unit['latitude'];
          m['longitude'] = unit['longitude'];
          m['barangay'] = unit['barangay'];
          m['city'] = unit['city'];
          m['province'] = unit['province'];
        }

        // 3) Build rule vector using same helper as questionnaire
        final ruleVec = _buildRuleVector(m);

        // 4) Similarity + boost + combined score
        final sim = cosineSimilarity(userVec, ruleVec);
        final boost = attributeMatchBoost(userVec, ruleVec);
        final score = sim * boost;

        // 5) Distance (Haversine helper)
        double? km;
        if (_userLat != null &&
            _userLng != null &&
            m['latitude'] != null &&
            m['longitude'] != null) {
          final lat = double.tryParse('${m['latitude']}');
          final lng = double.tryParse('${m['longitude']}');
          if (lat != null && lng != null) {
            km = _distanceKm(_userLat!, _userLng!, lat, lng);
          }
        }

        final withinRadius = km != null ? km <= kMaxDistanceKm : false;
        final included = withinRadius && score >= kSimilarityThreshold;

        debugPrint(
          'DEBUG: Unit ${m['dayung_unit_id'] ?? m['id']} '
          'Similarity=${sim.toStringAsFixed(3)} '
          'Boost=${boost.toStringAsFixed(3)} '
          'Combined=${score.toStringAsFixed(3)} '
          'Distance=${km?.toStringAsFixed(2) ?? '—'} km '
          'Threshold=$kSimilarityThreshold '
          '${included ? "[INCLUDED]" : "[EXCLUDED]"}',
        );

        if (included) {
          out.add({
            'id': m['dayung_unit_id'] ?? m['id'],
            'name': m['dayung_unit_name'] ?? 'Unnamed Dayung',
            'barangay': m['barangay'],
            'city': m['city'],
            'province': m['province'],
            'latitude': m['latitude'],
            'longitude': m['longitude'],
            '__score': score,
            '__km': km,
          });
        }
      }

      // 6) Sort by score desc
      out.sort(
        (a, b) => (b['__score'] as double).compareTo(a['__score'] as double),
      );

      setState(() {
        _recommendedUnits = out;
      });
    } catch (e) {
      debugPrint('ERROR loading recommendations: $e');
      setState(() => _recommendedUnits = []);
    } finally {
      if (mounted) setState(() => _loadingRecs = false);
    }
  }

  Future<void> _loadPreferences() async {
    setState(() => _loadingPrefs = true);
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _loadingPrefs = false);
      return;
    }
    try {
      final pref = await supabase
          .from('user_preferences')
          .select(
            'meeting_frequency, contribution_amount, membership_payment, '
            'penalty_payment, payment_method, open_for_all, penalty_policy, '
            'fee_range, fund_support_range, location',
          )
          .eq('user_id', user.id)
          .maybeSingle();

      String? userAddress;
      final userObj = pref?['users'];
      if (userObj != null) {
        final parts = [
          if ((userObj['barangay'] ?? '').toString().isNotEmpty)
            userObj['barangay'],
          if ((userObj['city'] ?? '').toString().isNotEmpty) userObj['city'],
          if ((userObj['province'] ?? '').toString().isNotEmpty)
            userObj['province'],
        ];
        userAddress = parts.join(', ');
      }

      setState(() {
        _prefMeetingFrequency = (pref?['meeting_frequency'] as String?)?.trim();
        _prefContributionAmount = (pref?['contribution_amount'] as String?)
            ?.trim();
        _prefMembershipPayment = (pref?['membership_payment'] as String?)
            ?.trim();
        _prefPenaltyPayment = (pref?['penalty_payment'] as String?)?.trim();
        _prefPenaltyPolicy = (pref?['penalty_policy'] as String?)?.trim();
        _prefFeeRange =
            (_prefContributionAmount ?? (pref?['fee_range'] as String?))
                ?.trim();
        _prefPaymentMethod = (pref?['payment_method'] as String?)?.trim();
        _prefOpenForAll = pref?['open_for_all'] as bool?;
        _prefFundSupportRange = (pref?['fund_support_range'] as String?)
            ?.trim();
        _prefLocation = userAddress;
        _loadingPrefs = false;
      });
    } catch (e) {
      debugPrint('ERROR LOADING PREFS: $e');
      setState(() => _loadingPrefs = false);
    }
  }

  Future<void> _savePreferences() async {
    setState(() => _savingPrefs = true);
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _savingPrefs = false);
      return;
    }

    // 1. Fetch user's latitude and longitude from users table
    double? latitude;
    double? longitude;
    try {
      final userObj = await supabase
          .from('users')
          .select('latitude,longitude')
          .eq('id', user.id)
          .maybeSingle();
      latitude = userObj?['latitude'] != null
          ? double.tryParse('${userObj?['latitude']}')
          : null;
      longitude = userObj?['longitude'] != null
          ? double.tryParse('${userObj?['longitude']}')
          : null;
    } catch (e) {
      debugPrint('Failed to fetch user lat/lng: $e');
    }

    final payload = {
      'user_id': user.id,
      // Canonical fields (same as QuestionnaireScreen)
      'meeting_frequency': _prefMeetingFrequency,
      'contribution_amount': _prefContributionAmount,
      'membership_payment': _prefMembershipPayment,
      'penalty_payment': _prefPenaltyPayment,
      'penalty_policy': _prefPenaltyPolicy,
      'payment_method': _prefPaymentMethod,
      'open_for_all': _prefOpenForAll,
      // Optional extra
      'location': _prefLocation,
      // Legacy / for existing queries that still read these
      'fee_range': _prefContributionAmount,
      'fund_support_range': _prefMembershipPayment,
      // Add latitude and longitude
      'latitude': latitude,
      'longitude': longitude,
    };

    try {
      await supabase
          .from('user_preferences')
          .upsert(payload, onConflict: 'user_id');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preferences updated')));
      Navigator.of(context).maybePop();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: ${e.message}')));
    } finally {
      if (mounted) setState(() => _savingPrefs = false);
    }
  }

  void _showEditPreferencesSheet() {
    final formKey = GlobalKey<FormState>();

    // Local form copies (default to 'Any' where applicable)
    String? meetingFrequency = _prefMeetingFrequency ?? 'Any';
    String? contributionAmount = _prefContributionAmount ?? 'Any';
    String? membershipPayment = _prefMembershipPayment ?? 'Any';
    String? penaltyPayment = _prefPenaltyPayment ?? 'Any';
    String? paymentMethod = _prefPaymentMethod ?? 'Any';
    String? openForAllStr = _prefOpenForAll == null
        ? null
        : (_prefOpenForAll! ? 'Yes' : 'No');
    String? penaltyPolicy = _prefPenaltyPolicy;
    String? location = _prefLocation; // now always from user address

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 4,
                  width: 40,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: kSubText.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const Text(
                  'Edit Preferences',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Montserrat',
                    color: kText,
                  ),
                ),
                const SizedBox(height: 12),

                // Meeting Frequency (same options as questionnaire)
                DropdownButtonFormField<String>(
                  initialValue: meetingFrequency,
                  decoration: const InputDecoration(
                    labelText: 'Meeting Frequency',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['Any', 'Weekly', 'Monthly', 'Needed']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => meetingFrequency = v,
                ),
                const SizedBox(height: 10),

                // Registration Fee Range / contribution_amount
                DropdownButtonFormField<String>(
                  initialValue: contributionAmount,
                  decoration: const InputDecoration(
                    labelText: 'Registration Fee Range',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      const [
                            'Any',
                            '50-100',
                            '100-150',
                            '150-200',
                            '200-250',
                            '250-300',
                            '300-350',
                            '400 plus',
                          ]
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                  onChanged: (v) => contributionAmount = v,
                ),
                const SizedBox(height: 10),

                // Membership Payment
                DropdownButtonFormField<String>(
                  initialValue: membershipPayment,
                  decoration: const InputDecoration(
                    labelText: 'Membership Payment',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      const [
                            'Any',
                            '50-100',
                            '100-150',
                            '150-200',
                            '200-250',
                            '250-300',
                            '300-350',
                            '400 plus',
                          ]
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                  onChanged: (v) => membershipPayment = v,
                ),
                const SizedBox(height: 10),

                // Penalty Payment
                DropdownButtonFormField<String>(
                  initialValue: penaltyPayment,
                  decoration: const InputDecoration(
                    labelText: 'Penalty Payment',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      const [
                            'Any',
                            '50-100',
                            '100-150',
                            '150-200',
                            '200-250',
                            '250-300',
                            '300-350',
                            '400 plus',
                          ]
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                  onChanged: (v) => penaltyPayment = v,
                ),
                const SizedBox(height: 10),

                // Payment Method
                DropdownButtonFormField<String>(
                  initialValue: paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Preferred Payment Method',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['Any', 'Cash', 'GCash', 'Both']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => paymentMethod = v,
                ),
                const SizedBox(height: 10),

                // Open for All?
                DropdownButtonFormField<String>(
                  initialValue: openForAllStr,
                  decoration: const InputDecoration(
                    labelText: 'Open for All?',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['Yes', 'No']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => openForAllStr = v,
                ),
                const SizedBox(height: 10),

                // Penalty Policy (optional text)
                TextFormField(
                  initialValue: penaltyPolicy,
                  decoration: const InputDecoration(
                    labelText: 'Penalty Policy (optional)',
                    border: OutlineInputBorder(),
                    hintText: 'Brief description of penalties',
                  ),
                  maxLines: 2,
                  onChanged: (v) =>
                      penaltyPolicy = v.trim().isEmpty ? null : v.trim(),
                ),
                const SizedBox(height: 10),

                // Location (now read-only, auto-filled)
                TextFormField(
                  initialValue: location,
                  decoration: const InputDecoration(
                    labelText: 'Location (from your address)',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., Davao City',
                  ),
                  enabled: false, // make it read-only
                ),
                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _savingPrefs
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      _savingPrefs ? 'Saving...' : 'Save Preferences',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryLight,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _savingPrefs
                        ? null
                        : () async {
                            setState(() {
                              // Apply "Any" → null rule, same as questionnaire
                              _prefMeetingFrequency = meetingFrequency == 'Any'
                                  ? null
                                  : meetingFrequency;
                              _prefContributionAmount =
                                  contributionAmount == 'Any'
                                  ? null
                                  : contributionAmount;
                              _prefMembershipPayment =
                                  membershipPayment == 'Any'
                                  ? null
                                  : membershipPayment;
                              _prefPenaltyPayment = penaltyPayment == 'Any'
                                  ? null
                                  : penaltyPayment;
                              _prefPaymentMethod = paymentMethod == 'Any'
                                  ? null
                                  : paymentMethod;

                              _prefOpenForAll = openForAllStr == null
                                  ? null
                                  : openForAllStr == 'Yes';

                              _prefPenaltyPolicy = penaltyPolicy;
                              _prefLocation = location;

                              // Keep legacy fee_range in sync with contribution_amount
                              _prefFeeRange = _prefContributionAmount;
                            });
                            await _savePreferences();
                            if (mounted) setState(() {}); // refresh tags
                          },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadCurrentDayung() async {
    setState(() => _loadingDayung = true);

    // Use DayungUnitProvider or SharedPreferences as the source of truth
    final provider = context.read<DayungUnitProvider>();
    await provider.loadDayungUnit(); // ensures latest from prefs

    final obj = provider.dayungUnitObj;
    final name = provider.dayungUnit;
    setState(() {
      _currentDayungId = obj?['id'] as int?;
      _currentDayungName = name;
      _currentDayungData = obj;
      _loadingDayung = false;
    });
  }

  String _address(Map<String, dynamic> d) {
    final parts = <String>[
      if ((d['barangay'] ?? '').toString().isNotEmpty) d['barangay'],
      if ((d['city'] ?? '').toString().isNotEmpty) d['city'],
      if ((d['province'] ?? '').toString().isNotEmpty) d['province'],
    ];
    return parts.join(', ');
  }

  // Show requirements sheet for an applied Dayung
  void _showRequirementsSheet(String dayungName, {List<String>? requirements}) {
    final reqs =
        requirements ??
        const [
          'Birth Certificate',
          'Valid Government ID',
          'Proof of Residency',
          'Marriage Certificate (if applicable)',
        ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: kSubText.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Text(
                'Upload Requirements',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Montserrat',
                  color: kText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Your application for $dayungName is pending. Please upload the following:',
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'OpenSans',
                  color: kSubText,
                ),
              ),
              const SizedBox(height: 12),
              ...reqs.map(
                (r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.description_rounded,
                        size: 16,
                        color: kPrimary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          r,
                          style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'OpenSans',
                            color: kText,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: kAccent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'Montserrat',
                            color: kAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    final sectionTitleStyle = TextStyle(
      fontSize: isWide ? 20 : 16,
      fontWeight: FontWeight.w600,
      fontFamily: 'Montserrat',
    );
    final bodyTextStyle = TextStyle(
      fontSize: isWide ? 18 : 14,
      fontFamily: 'OpenSans',
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1E40AF), // Deep blue gradient
              Color(0xFF3B82F6), // Medium blue
              Color(0xFFF8FAFC), // Light background
            ],
            stops: [0.0, 0.15, 0.15],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Modern Header
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
                      onPressed: () => Navigator.pop(context, true),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Manage Dayung',
                        style: TextStyle(
                          fontSize: isWide ? 24 : 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontFamily: 'Montserrat',
                          letterSpacing: 0.3,
                          shadows: [
                            const Shadow(
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
              // Content
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
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
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Current Dayung card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: kPrimary.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: kPrimary,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.home_rounded,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        'Current Dayung',
                                        style: sectionTitleStyle.copyWith(
                                          color: kText,
                                          fontSize: isWide ? 16 : 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              if (_loadingDayung)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: kPrimary.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: kPrimary.withValues(
                                            alpha: 0.08,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            color: kPrimary,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        'Loading dayung information...',
                                        style: TextStyle(
                                          color: kPrimary,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else ...[
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: _currentDayungName != null
                                            ? kSuccess.withValues(alpha: 0.08)
                                            : kWarn.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Icon(
                                        _currentDayungName != null
                                            ? Icons.check_circle_rounded
                                            : Icons.warning_amber_rounded,
                                        color: _currentDayungName != null
                                            ? kSuccess
                                            : kWarn,
                                        size: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        _currentDayungName ??
                                            'No Dayung Assigned',
                                        style: bodyTextStyle.copyWith(
                                          color: _currentDayungName != null
                                              ? kText
                                              : kSubText,
                                          fontWeight: FontWeight.w500,
                                          fontSize: isWide ? 14 : 12,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: kPrimary.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: IconButton(
                                        tooltip: 'Refresh',
                                        onPressed: _loadCurrentDayung,
                                        icon: const Icon(
                                          Icons.refresh_rounded,
                                          color: kPrimary,
                                          size: 12,
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_currentDayungData != null) ...[
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: kSubText.withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: kSubText.withValues(
                                              alpha: 0.08,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              3,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.location_on_rounded,
                                            color: kSubText,
                                            size: 12,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            _address(_currentDayungData!),
                                            style: TextStyle(
                                              color: kSubText,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w400,
                                              fontFamily: 'OpenSans',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    if (_currentDayungData != null &&
                                        _currentDayungData!['latitude'] !=
                                            null &&
                                        _currentDayungData!['longitude'] !=
                                            null)
                                      Expanded(
                                        child: Container(
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: kAccent,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => map.DayungMapPage(
                                                      dayung:
                                                          _currentDayungData!,
                                                      isApplied:
                                                          true, // disable apply on map
                                                      isMember:
                                                          true, // mark as current
                                                    ),
                                                  ),
                                                );
                                              },
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  const Icon(
                                                    Icons.map_rounded,
                                                    color: Colors.white,
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'View on Map',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      fontFamily: 'Montserrat',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (_currentDayungData != null &&
                                        _currentDayungData!['latitude'] !=
                                            null &&
                                        _currentDayungData!['longitude'] !=
                                            null)
                                      const SizedBox(width: 12),
                                    Expanded(
                                      child: Container(
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: kPrimary,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            onTap: () async {
                                              final selected =
                                                  await Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          const SelectDayungPage(),
                                                    ),
                                                  );

                                              // If user picked a Dayung, update users.dayung_unit_id
                                              if (!mounted) return;
                                              if (selected != null &&
                                                  selected
                                                      is Map<String, dynamic>) {
                                                final supabase =
                                                    Supabase.instance.client;
                                                final user =
                                                    supabase.auth.currentUser;
                                                if (user != null &&
                                                    selected['id'] != null) {
                                                  try {
                                                    await supabase
                                                        .from('users')
                                                        .update({
                                                          'dayung_unit_id':
                                                              selected['id'],
                                                        })
                                                        .eq('id', user.id);

                                                    // Persist the new selection to SharedPreferences so ClaimsPage picks it up
                                                    final prefs =
                                                        await SharedPreferences.getInstance();
                                                    await prefs.setString(
                                                      'selectedDayungUnit',
                                                      jsonEncode({
                                                        'id': selected['id'],
                                                        'name':
                                                            selected['name'],
                                                        'barangay':
                                                            selected['barangay'],
                                                        'city':
                                                            selected['city'],
                                                      }),
                                                    );

                                                    // (Optional) notify a provider if you use one
                                                    // context.read<DayungUnitProvider>().setDayungName(selected['name']);

                                                    if (!mounted) return;
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          'Current Dayung updated to ${selected['name']}',
                                                        ),
                                                      ),
                                                    );
                                                  } on PostgrestException catch (
                                                    e
                                                  ) {
                                                    if (!mounted) return;
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          'Failed to set Dayung: ${e.message}',
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                }
                                              }

                                              await _loadCurrentDayung(); // refresh UI
                                            },
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  Icons.swap_horiz_rounded,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Change',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                    fontFamily: 'Montserrat',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Apply a Dayung
                        Container(
                          width: double.infinity,
                          height: 44,
                          decoration: BoxDecoration(
                            color: kAccent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () async {
                                final selectedDayung = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const DayungSuggestionsPage(),
                                  ),
                                );
                                if (selectedDayung != null &&
                                    selectedDayung is Map<String, dynamic>) {
                                  // Application was sent via RPC in DayungSuggestionsPage
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Application for ${selectedDayung['name']} sent!',
                                      ),
                                    ),
                                  );
                                  await _loadCurrentDayung(); // refresh in case approval was instant
                                  await _loadAppliedDayungs(); // refresh pending list
                                }
                              },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(
                                      Icons.add_rounded,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Apply a Dayung',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          height: 44,
                          decoration: BoxDecoration(
                            color: kPrimaryLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                showModalBottomSheet(
                                  context: context,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(16),
                                    ),
                                  ),
                                  builder: (ctx) => Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      20,
                                      20,
                                      32,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Center(
                                          child: Container(
                                            width: 40,
                                            height: 4,
                                            margin: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              color: kSubText.withOpacity(0.2),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                        ),
                                        const Text(
                                          'Requirements to Apply for a Dayung',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            fontFamily: 'Montserrat',
                                            color: kText,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        const Text(
                                          'You will need to upload the following documents when applying for a Dayung:',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontFamily: 'OpenSans',
                                            color: kSubText,
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                        // Show requirements list (same as _showRequirementsSheet)
                                        ...const [
                                          'Birth Certificate',
                                          'Valid Government ID',
                                          'Proof of Residency',
                                          'Marriage Certificate (if applicable)',
                                        ].map(
                                          (r) => Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 4,
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.description_rounded,
                                                  size: 16,
                                                  color: kPrimary,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    r,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontFamily: 'OpenSans',
                                                      color: kText,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: kPrimary,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                  ),
                                            ),
                                            child: const Text('Got it'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(
                                      Icons.info_outline_rounded,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'How to Apply?',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Applied Dayung List
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Applied Dayung (Pending)',
                                style: sectionTitleStyle,
                              ),
                              // Add info button to show modal
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  icon: const Icon(
                                    Icons.info_outline_rounded,
                                    size: 18,
                                    color: kPrimary,
                                  ),
                                  label: const Text(
                                    'What does this mean?',
                                    style: TextStyle(
                                      color: kPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    minimumSize: Size(0, 0),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: context,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(16),
                                        ),
                                      ),
                                      builder: (ctx) => Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          20,
                                          20,
                                          20,
                                          32,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Center(
                                              child: Container(
                                                width: 40,
                                                height: 4,
                                                margin: const EdgeInsets.only(
                                                  bottom: 12,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: kSubText.withOpacity(
                                                    0.2,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                              ),
                                            ),
                                            const Text(
                                              'Pending Applications',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                fontFamily: 'Montserrat',
                                                color: kText,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            const Text(
                                              'These are Dayung units you have applied to join but are still awaiting approval. '
                                              'You may need to upload requirements or wait for the Dayung admin to review your application.',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontFamily: 'OpenSans',
                                                color: kSubText,
                                              ),
                                            ),
                                            const SizedBox(height: 18),
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton(
                                                onPressed: () =>
                                                    Navigator.of(ctx).pop(),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: kPrimary,
                                                  foregroundColor: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 12,
                                                      ),
                                                ),
                                                child: const Text('Got it'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_loadingApplied)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              else if (_appliedDayungs.isEmpty) ...[
                                Text(
                                  'You have no pending applications.',
                                  style: bodyTextStyle.copyWith(
                                    color: kSubText,
                                  ),
                                ),
                                if (_appliedDebug != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    _appliedDebug!,
                                    style: bodyTextStyle.copyWith(
                                      color: kSubText,
                                      fontSize: isWide ? 12 : 10,
                                    ),
                                  ),
                                ],
                              ] else
                                ..._appliedDayungs.map((app) {
                                  final dayungName =
                                      (app['name'] as String?) ?? 'N/A';
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(6),
                                      onTap: () =>
                                          _showRequirementsSheet(dayungName),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                          horizontal: 12,
                                        ),
                                        margin: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: kSubText.withOpacity(0.05),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: kBorderColor,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                dayungName,
                                                style: bodyTextStyle.copyWith(
                                                  fontWeight: FontWeight.w500,
                                                  color: kPrimary,
                                                  decoration:
                                                      TextDecoration.underline,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Icon(
                                              Icons.upload_file_rounded,
                                              size: 16,
                                              color: kPrimary,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Filters
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: kAccent.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: kAccent,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.filter_list_rounded,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        'Filters',
                                        style: sectionTitleStyle.copyWith(
                                          color: kText,
                                          fontSize: isWide ? 16 : 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: kPrimary.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: TextButton.icon(
                                        onPressed: _showEditPreferencesSheet,
                                        icon: const Icon(
                                          Icons.edit_rounded,
                                          color: kPrimary,
                                          size: 12,
                                        ),
                                        label: Text(
                                          'Edit',
                                          style: TextStyle(
                                            color: kPrimary,
                                            fontSize: isWide ? 12 : 10,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: 'Montserrat',
                                          ),
                                        ),
                                        style: TextButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              if (_loadingPrefs)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              else ...[
                                Text(
                                  'Selected tags:',
                                  style: bodyTextStyle.copyWith(
                                    color: kSubText,
                                    fontWeight: FontWeight.w500,
                                    fontSize: isWide ? 14 : 12,
                                    fontFamily: 'Montserrat',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: _prefsTags.map((tag) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: kAccent.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        tag,
                                        style: TextStyle(
                                          fontSize: isWide ? 12 : 10,
                                          color: kAccent,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: kPrimary.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: kPrimary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  Icons.recommend_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  'Recommended for you',
                                  style: sectionTitleStyle.copyWith(
                                    color: kText,
                                    fontSize: isWide ? 16 : 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Refresh',
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 16,
                                  color: kPrimary,
                                ),
                                onPressed: _loadRecommendations,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_loadingRecs)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (_recommendedUnits.isEmpty)
                          Text(
                            'No recommendations within ${kMaxDistanceKm.toStringAsFixed(0)} km and threshold ${kSimilarityThreshold.toStringAsFixed(3)}. Edit your filters above.',
                            style: TextStyle(
                              color: kSubText,
                              fontSize: isWide ? 14 : 12,
                            ),
                          )
                        else
                          Column(
                            children: _recommendedUnits.map((d) {
                              return GestureDetector(
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => map.DayungMapPage(
                                        dayung: d,
                                        isApplied: false,
                                        isMember: false,
                                      ),
                                    ),
                                  );
                                  if (result != null && mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Application sent to ${d['name']}!',
                                        ),
                                      ),
                                    );
                                    await _loadCurrentDayung();
                                  }
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: kAccent.withValues(
                                                alpha: 0.05,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Icon(
                                              Icons.home_rounded,
                                              color: kAccent,
                                              size: 12,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              d['name'] ?? 'Unnamed Dayung',
                                              style: TextStyle(
                                                fontSize: isWide ? 14 : 12,
                                                fontWeight: FontWeight.w500,
                                                fontFamily: 'Montserrat',
                                                color: kText,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _address(d),
                                        style: TextStyle(
                                          color: kSubText,
                                          fontSize: 12,
                                          fontFamily: 'OpenSans',
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Builder(
                                        builder: (_) {
                                          final km = d['__km'] as double?;
                                          final sc = d['__score'] as double?;
                                          return Text(
                                            '≈ ${km != null ? km.toStringAsFixed(2) : '—'} km • Score ${sc != null ? sc.toStringAsFixed(3) : '—'}',
                                            style: const TextStyle(
                                              color: kSubText,
                                              fontSize: 11,
                                              fontFamily: 'OpenSans',
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          OutlinedButton.icon(
                                            icon: const Icon(
                                              Icons.map_rounded,
                                              size: 16,
                                            ),
                                            label: const Text('Map'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: kPrimary,
                                              side: const BorderSide(
                                                color: kPrimary,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                            ),
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      map.DayungMapPage(
                                                        dayung: d,
                                                        isApplied: false,
                                                        isMember: false,
                                                      ),
                                                ),
                                              );
                                            },
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton.icon(
                                            icon: const Icon(
                                              Icons.refresh_rounded,
                                              size: 16,
                                            ),
                                            label: const Text('Similar'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: kPrimary,
                                              side: const BorderSide(
                                                color: kPrimary,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                            ),
                                            onPressed: _loadRecommendations,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Register this page to listen for navigation events
    final routeObserver = ModalRoute.of(context)?.navigator?.widget.observers
        .whereType<RouteObserver<PageRoute>>()
        .firstOrNull;
    routeObserver?.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    // Unregister
    final routeObserver = ModalRoute.of(context)?.navigator?.widget.observers
        .whereType<RouteObserver<PageRoute>>()
        .firstOrNull;
    routeObserver?.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // Called when coming back to this page
    _loadPreferences();
    _loadCurrentDayung();
    _loadAppliedDayungs();
    _fetchUserLatLng();
    _loadRecommendations();
  }
}
