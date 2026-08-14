import 'dart:math' as math;

import 'package:capstone_app/utils/dayung_service_tags.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DayungPreferencesData {
  const DayungPreferencesData({
    this.meetingFrequency,
    this.contributionAmount,
    this.membershipPayment,
    this.penaltyPayment,
    this.penaltyPolicy,
    this.paymentMethod,
    this.openForAll,
    this.location,
    this.userLat,
    this.userLng,
  });

  final String? meetingFrequency;
  final String? contributionAmount;
  final String? membershipPayment;
  final String? penaltyPayment;
  final String? penaltyPolicy;
  final String? paymentMethod;
  final bool? openForAll;
  final String? location;
  final double? userLat;
  final double? userLng;

  List<String> get tags {
    final values = <String>[];
    final fields = {
      'Meeting': meetingFrequency,
      'Registration': contributionAmount,
      'Membership': membershipPayment,
      'Penalty Fee': penaltyPayment,
      'Penalty Policy': penaltyPolicy,
      'Payment': paymentMethod,
      'Open For All': openForAll == null ? null : (openForAll! ? 'Yes' : 'No'),
      'Location': location,
    };
    fields.forEach((label, value) {
      if (value != null && value.toString().trim().isNotEmpty) {
        values.add('$label: $value');
      }
    });
    return values;
  }

  DayungPreferencesData copyWith({
    String? meetingFrequency,
    String? contributionAmount,
    String? membershipPayment,
    String? penaltyPayment,
    String? penaltyPolicy,
    String? paymentMethod,
    bool? openForAll,
    String? location,
    double? userLat,
    double? userLng,
  }) {
    return DayungPreferencesData(
      meetingFrequency: meetingFrequency ?? this.meetingFrequency,
      contributionAmount: contributionAmount ?? this.contributionAmount,
      membershipPayment: membershipPayment ?? this.membershipPayment,
      penaltyPayment: penaltyPayment ?? this.penaltyPayment,
      penaltyPolicy: penaltyPolicy ?? this.penaltyPolicy,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      openForAll: openForAll ?? this.openForAll,
      location: location ?? this.location,
      userLat: userLat ?? this.userLat,
      userLng: userLng ?? this.userLng,
    );
  }

  Map<String, dynamic> toUpsertPayload(String userId) {
    return {
      'user_id': userId,
      'meeting_frequency': meetingFrequency,
      'contribution_amount': contributionAmount,
      'membership_payment': membershipPayment,
      'penalty_payment': penaltyPayment,
      'penalty_policy': penaltyPolicy,
      'payment_method': paymentMethod,
      'open_for_all': openForAll,
      'location': location,
      'fee_range': contributionAmount,
      'fund_support_range': membershipPayment,
      'latitude': userLat,
      'longitude': userLng,
    };
  }
}

class DayungRecommendationService {
  static const double similarityThreshold = 0.3;
  static const double maxDistanceKm = 6.0;

  static Future<DayungPreferencesData> loadPreferences(
    SupabaseClient client, {
    required String userId,
  }) async {
    final pref = await client
        .from('user_preferences')
        .select(
          'meeting_frequency, contribution_amount, membership_payment, '
          'penalty_payment, payment_method, open_for_all, penalty_policy, '
          'location',
        )
        .eq('user_id', userId)
        .maybeSingle();

    final user = await client
        .from('users')
        .select('latitude, longitude, barangay, city, province')
        .eq('id', userId)
        .maybeSingle();

    final address = [
      if ((user?['barangay'] ?? '').toString().isNotEmpty) user?['barangay'],
      if ((user?['city'] ?? '').toString().isNotEmpty) user?['city'],
      if ((user?['province'] ?? '').toString().isNotEmpty) user?['province'],
    ].join(', ');

    return DayungPreferencesData(
      meetingFrequency: (pref?['meeting_frequency'] as String?)?.trim(),
      contributionAmount: (pref?['contribution_amount'] as String?)?.trim(),
      membershipPayment: (pref?['membership_payment'] as String?)?.trim(),
      penaltyPayment: (pref?['penalty_payment'] as String?)?.trim(),
      penaltyPolicy: (pref?['penalty_policy'] as String?)?.trim(),
      paymentMethod: (pref?['payment_method'] as String?)?.trim(),
      openForAll: pref?['open_for_all'] as bool?,
      location:
          (pref?['location'] as String?)?.trim() ??
          (address.isEmpty ? null : address),
      userLat: user?['latitude'] != null
          ? double.tryParse('${user?['latitude']}')
          : null,
      userLng: user?['longitude'] != null
          ? double.tryParse('${user?['longitude']}')
          : null,
    );
  }

  static Future<void> savePreferences(
    SupabaseClient client, {
    required String userId,
    required DayungPreferencesData preferences,
  }) async {
    await client
        .from('user_preferences')
        .upsert(preferences.toUpsertPayload(userId), onConflict: 'user_id');
  }

  static Future<Set<int>> loadPendingApplicationDayungIds(
    SupabaseClient client, {
    required String userId,
  }) async {
    final rows = await client
        .from('applications')
        .select('dayung_unit_id')
        .eq('user_id', userId)
        .eq('status', 'pending');

    return (rows as List)
        .map((row) => (row as Map)['dayung_unit_id'])
        .whereType<int>()
        .toSet();
  }

  static List<Map<String, dynamic>> rankEligibleUnits(
    List<Map<String, dynamic>> units, {
    int limit = 5,
    double similarityThreshold = similarityThreshold,
  }) {
    final ranked = List<Map<String, dynamic>>.from(units);

    ranked.sort((left, right) {
      final leftKm = (left['__km'] as num?)?.toDouble();
      final rightKm = (right['__km'] as num?)?.toDouble();

      if (leftKm != null && rightKm != null) {
        final distanceCmp = leftKm.compareTo(rightKm);
        if (distanceCmp != 0) return distanceCmp;
      } else if (leftKm != null && rightKm == null) {
        return -1;
      } else if (leftKm == null && rightKm != null) {
        return 1;
      }

      return ((right['__score'] as num?) ?? 0).compareTo(
        (left['__score'] as num?) ?? 0,
      );
    });

    final eligible = ranked
        .where(
          (unit) => ((unit['__score'] as num?) ?? 0) >= similarityThreshold,
        )
        .toList();

    final preferredDistanceUnits = eligible
        .where((unit) => unit['__withinRadius'] == true)
        .toList();

    final filtered = preferredDistanceUnits.isNotEmpty
        ? preferredDistanceUnits
        : eligible;

    return filtered.take(limit).toList();
  }

  static Future<List<Map<String, dynamic>>> loadRecommendations(
    SupabaseClient client, {
    required DayungPreferencesData preferences,
    int? currentDayungId,
    Set<int> excludedDayungIds = const {},
    int limit = 5,
  }) async {
    final userVector = _generatePreferenceVector(preferences);
    final rows = await client
        .from('dayung_rules')
        .select(
          'id, dayung_unit_id, dayung_unit_name, meeting_frequency, '
          'collection_fee_range, membership_payment, penalty_payment, '
          'payment_method, open_for_all, ${dayungServiceTagLabels.map((label) => dayungServiceTagColumns[label]!).join(', ')}, dayung_units('
          'id, name, latitude, longitude, barangay, city, province)',
        );

    final scoredUnits = <Map<String, dynamic>>[];

    for (final row in rows as List) {
      final data = Map<String, dynamic>.from(row as Map);
      final unit = data['dayung_units'];
      if (unit is Map) {
        data['id'] = data['dayung_unit_id'] ?? unit['id'];
        data['name'] = data['dayung_unit_name'] ?? unit['name'];
        data['latitude'] = unit['latitude'];
        data['longitude'] = unit['longitude'];
        data['barangay'] = unit['barangay'];
        data['city'] = unit['city'];
        data['province'] = unit['province'];
      }

      final unitId = data['id'];
      if (unitId == null || unitId == currentDayungId) continue;
      if (unitId is int && excludedDayungIds.contains(unitId)) continue;

      final ruleVector = _buildRuleVector(data);
      final similarity = _cosineSimilarity(userVector, ruleVector);
      final score = similarity * _attributeMatchBoost(userVector, ruleVector);

      final lat = data['latitude'] != null
          ? double.tryParse('${data['latitude']}')
          : null;
      final lng = data['longitude'] != null
          ? double.tryParse('${data['longitude']}')
          : null;

      double? km;
      if (preferences.userLat != null &&
          preferences.userLng != null &&
          lat != null &&
          lng != null) {
        km = _distanceKm(preferences.userLat!, preferences.userLng!, lat, lng);
      }

      final withinRadius = km == null || km <= maxDistanceKm;
      final tags = <String>[
        if ((data['collection_fee_range'] ?? '').toString().isNotEmpty)
          'Collection ${data['collection_fee_range']}',
        if ((data['membership_payment'] ?? '').toString().isNotEmpty)
          'Membership ${data['membership_payment']}',
        if ((data['payment_method'] ?? '').toString().isNotEmpty)
          '${data['payment_method']}',
        if ((data['open_for_all'] ?? '').toString().toLowerCase() == 'yes')
          'Open for all',
        ...dayungServiceTagLabels.where((label) {
          final column = dayungServiceTagColumns[label]!;
          return data[column] == true;
        }),
        if (km != null) '${km.toStringAsFixed(1)} km away',
      ];

      scoredUnits.add({
        'id': unitId,
        'name': data['name'] ?? 'Unnamed Dayung',
        'barangay': data['barangay'],
        'city': data['city'],
        'province': data['province'],
        'latitude': lat,
        'longitude': lng,
        'meeting_frequency': data['meeting_frequency'],
        'collection_fee_range': data['collection_fee_range'],
        'membership_payment': data['membership_payment'],
        'payment_method': data['payment_method'],
        'open_for_all': data['open_for_all'],
        '__score': score,
        '__km': km,
        '__withinRadius': withinRadius,
        '__tags': tags,
      });
    }

    return rankEligibleUnits(
      scoredUnits,
      limit: limit,
      similarityThreshold: similarityThreshold,
    );
  }

  static List<double> _generatePreferenceVector(DayungPreferencesData prefs) {
    const feeRanges = [
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
      for (int index = 0; index < feeRanges.length; index++) {
        if (selected == feeRanges[index]) out[index] = 1.0;
      }
      return out;
    }

    final serviceTags = dayungServiceTagLabels.map((label) {
      return 0.0;
    }).toList();

    return [
      prefs.meetingFrequency == 'Weekly' ? 1.0 : 0.0,
      prefs.meetingFrequency == 'Monthly' ? 1.0 : 0.0,
      prefs.meetingFrequency == 'Needed' ? 1.0 : 0.0,
      prefs.paymentMethod == 'Cash' ? 1.0 : 0.0,
      prefs.paymentMethod == 'GCash' ? 1.0 : 0.0,
      prefs.paymentMethod == 'Both' ? 1.0 : 0.0,
      ...bucket(prefs.contributionAmount),
      ...bucket(prefs.membershipPayment),
      ...bucket(prefs.penaltyPayment),
      prefs.openForAll == true ? 1.0 : 0.0,
      ...serviceTags,
    ];
  }

  static List<double> _buildRuleVector(Map<String, dynamic> data) {
    String norm(String? value) => (value ?? '').trim().toLowerCase();
    const feeRanges = [
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
      for (int index = 0; index < feeRanges.length; index++) {
        if (norm(selected) == feeRanges[index]) out[index] = 1.0;
      }
      return out.every((value) => value == 0.0)
          ? List<double>.filled(feeRanges.length, 1.0)
          : out;
    }

    final meeting = norm(data['meeting_frequency']);
    final paymentMethod = norm(data['payment_method']);

    final serviceTagVector = dayungServiceTagLabels.map((label) {
      final column = dayungServiceTagColumns[label]!;
      return data[column] == true ? 1.0 : 0.0;
    }).toList();

    return [
      meeting == 'weekly' ? 1.0 : 0.0,
      meeting == 'monthly' ? 1.0 : 0.0,
      meeting == 'needed' ? 1.0 : 0.0,
      paymentMethod == 'cash' ? 1.0 : 0.0,
      paymentMethod == 'gcash' ? 1.0 : 0.0,
      paymentMethod == 'both' ? 1.0 : 0.0,
      ...bucket(data['collection_fee_range']),
      ...bucket(data['membership_payment']),
      ...bucket(data['penalty_payment']),
      norm('${data['open_for_all']}') == 'yes' ? 1.0 : 0.0,
      ...serviceTagVector,
    ];
  }

  static double _cosineSimilarity(List<double> user, List<double> rule) {
    if (user.length != rule.length || user.isEmpty) return 0.0;
    double dot = 0.0;
    double magUser = 0.0;
    double magRule = 0.0;
    for (int index = 0; index < user.length; index++) {
      dot += user[index] * rule[index];
      magUser += user[index] * user[index];
      magRule += rule[index] * rule[index];
    }
    const eps = 1e-10;
    if (magUser < eps || magRule < eps) return 0.0;
    return dot / (math.sqrt(magUser) * math.sqrt(magRule));
  }

  static double _attributeMatchBoost(List<double> user, List<double> rule) {
    int selected = 0;
    int matched = 0;
    for (int index = 0; index < user.length; index++) {
      if (user[index] == 1.0) {
        selected++;
        if (rule[index] == 1.0) matched++;
      }
    }
    if (selected == 0) return 1.0;
    return 1.0 + 0.25 * (matched / selected);
  }

  static double _distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const radius = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLng = (lng2 - lng1) * math.pi / 180.0;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return radius * c;
  }
}
