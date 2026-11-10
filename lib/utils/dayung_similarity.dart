import 'dart:math' as math;

import 'dayung_service_tags.dart';

const double hybridAttributeMatchWeight = 0.25;
const double dayungLocationMatchWeight = 0.30;
const double dayungLocationRadiusKm = 20.0;
const int minimumRecommendationPreferenceCount = 5;

const List<String> _dayungFeeRanges = [
  '50-100',
  '100-150',
  '150-200',
  '200-250',
  '250-300',
  '300-350',
  '400 plus',
];

bool hasEnoughRecommendationPreferences(int selectedCount) =>
    selectedCount >= minimumRecommendationPreferenceCount;

int countDayungPreferences(Map<String, dynamic> preferences) {
  final dropdownCount = [
    preferences['meeting_frequency'],
    preferences['payment_method'],
    preferences['contribution_amount'],
    preferences['membership_payment'],
    preferences['penalty_payment'],
  ].where((value) => value != null).length;
  final serviceCount = dayungServiceTagColumns.values
      .where((column) => preferences[column] == true)
      .length;
  return dropdownCount + serviceCount;
}

List<double> generateDayungPreferenceVector(Map<String, dynamic> preferences) {
  final meetingFrequency = preferences['meeting_frequency'];
  final paymentMethod = preferences['payment_method'];

  List<double> amountVector(Object? amount) =>
      _dayungFeeRanges.map((range) => amount == range ? 1.0 : 0.0).toList();

  return [
    meetingFrequency == 'Weekly' ? 1.0 : 0.0,
    meetingFrequency == 'Monthly' ? 1.0 : 0.0,
    meetingFrequency == 'Needed' ? 1.0 : 0.0,
    paymentMethod == 'Cash' ? 1.0 : 0.0,
    paymentMethod == 'GCash' ? 1.0 : 0.0,
    paymentMethod == 'Both' ? 1.0 : 0.0,
    ...amountVector(preferences['contribution_amount']),
    ...amountVector(preferences['membership_payment']),
    ...amountVector(preferences['penalty_payment']),
    0.0,
    ...dayungServiceTagColumns.values.map(
      (column) => preferences[column] == true ? 1.0 : 0.0,
    ),
  ];
}

List<double> buildDayungRuleVector(Map<String, dynamic> rule) {
  String normalize(Object? value) {
    if (value == null) return '';
    if (value is bool) return value ? 'yes' : 'no';
    return value.toString().trim().toLowerCase();
  }

  final meetingFrequency = normalize(rule['meeting_frequency']);
  final paymentMethod = normalize(rule['payment_method']);

  List<double> amountVector(Object? amount) => _dayungFeeRanges
      .map((range) => isAmountInRange(amount, range) ? 1.0 : 0.0)
      .toList();

  final exactPenalty = rule['exactpenaltypayment'];
  final hasExactPenalty =
      exactPenalty != null && exactPenalty.toString().trim().isNotEmpty;
  final penaltyVector = _dayungFeeRanges.map((range) {
    final matches = hasExactPenalty
        ? isAmountInRange(exactPenalty, range)
        : normalize(rule['penalty_payment']) == range;
    return matches ? 1.0 : 0.0;
  });

  return [
    meetingFrequency == 'weekly' ? 1.0 : 0.0,
    meetingFrequency == 'monthly' ? 1.0 : 0.0,
    meetingFrequency == 'needed' ? 1.0 : 0.0,
    paymentMethod == 'cash' ? 1.0 : 0.0,
    paymentMethod == 'gcash' ? 1.0 : 0.0,
    paymentMethod == 'both' ? 1.0 : 0.0,
    ...amountVector(rule['exactamountforcollection']),
    ...amountVector(rule['exactamountformembership']),
    ...penaltyVector,
    rule['open_for_all'] == true ? 1.0 : 0.0,
    ...dayungServiceTagColumns.values.map(
      (column) => rule[column] == true ? 1.0 : 0.0,
    ),
  ];
}

/// Combines the preference score with proximity when distance is available.
double hybridScoreAsPercentage(double score, {double? distanceKm}) {
  final preferencePercentage = (score / (1 + hybridAttributeMatchWeight) * 100)
      .clamp(0, 100)
      .toDouble();
  if (distanceKm == null || !distanceKm.isFinite) return preferencePercentage;

  final locationPercentage =
      (1 - distanceKm / dayungLocationRadiusKm).clamp(0, 1) * 100;
  return preferencePercentage * (1 - dayungLocationMatchWeight) +
      locationPercentage * dayungLocationMatchWeight;
}

double dayungDistanceKm(
  double latitude1,
  double longitude1,
  double latitude2,
  double longitude2,
) {
  const earthRadiusKm = 6371.0;
  final latitudeDelta = (latitude2 - latitude1) * math.pi / 180;
  final longitudeDelta = (longitude2 - longitude1) * math.pi / 180;
  final haversine =
      math.pow(math.sin(latitudeDelta / 2), 2) +
      math.cos(latitude1 * math.pi / 180) *
          math.cos(latitude2 * math.pi / 180) *
          math.pow(math.sin(longitudeDelta / 2), 2);
  return earthRadiusKm *
      2 *
      math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
}

bool isAmountInRange(Object? amount, String range) {
  final value = amount is num
      ? amount.toDouble()
      : double.tryParse(amount?.toString().trim() ?? '');
  if (value == null || !value.isFinite) return false;

  if (range.trim().toLowerCase() == '400 plus') return value >= 400;

  final bounds = RegExp(
    r'^(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)$',
  ).firstMatch(range.trim());
  if (bounds == null) return false;

  final minimum = double.parse(bounds.group(1)!);
  final maximum = double.parse(bounds.group(2)!);
  return value >= minimum && value <= maximum;
}

class HybridScoreResult {
  const HybridScoreResult({
    required this.cosineSimilarity,
    required this.attributeMatchBoost,
    required this.finalScore,
    required this.dotProduct,
    required this.userMagnitude,
    required this.unitMagnitude,
    required this.selectedCount,
    required this.matchedSelectedCount,
  });

  final double cosineSimilarity;
  final double attributeMatchBoost;
  final double finalScore;
  final double dotProduct;
  final double userMagnitude;
  final double unitMagnitude;
  final int selectedCount;
  final int matchedSelectedCount;
}

HybridScoreResult computeHybridScore(List<double> user, List<double> unit) {
  if (user.length != unit.length || user.isEmpty) {
    return const HybridScoreResult(
      cosineSimilarity: 0.0,
      attributeMatchBoost: 1.0,
      finalScore: 0.0,
      dotProduct: 0.0,
      userMagnitude: 0.0,
      unitMagnitude: 0.0,
      selectedCount: 0,
      matchedSelectedCount: 0,
    );
  }

  double dot = 0.0;
  double magUser = 0.0;
  double magUnit = 0.0;

  for (int index = 0; index < user.length; index++) {
    dot += user[index] * unit[index];
    magUser += user[index] * user[index];
    magUnit += unit[index] * unit[index];
  }

  const eps = 1e-10;
  final cosine = (magUser < eps || magUnit < eps)
      ? 0.0
      : dot / (math.sqrt(magUser) * math.sqrt(magUnit));

  int selectedCount = 0;
  int matchedSelectedCount = 0;
  for (int index = 0; index < user.length; index++) {
    if (user[index] == 1.0) {
      selectedCount++;
      if (unit[index] == 1.0) matchedSelectedCount++;
    }
  }

  final boost = selectedCount == 0
      ? 1.0
      : 1.0 +
            hybridAttributeMatchWeight * (matchedSelectedCount / selectedCount);

  return HybridScoreResult(
    cosineSimilarity: cosine,
    attributeMatchBoost: boost,
    finalScore: cosine * boost,
    dotProduct: dot,
    userMagnitude: math.sqrt(magUser),
    unitMagnitude: math.sqrt(magUnit),
    selectedCount: selectedCount,
    matchedSelectedCount: matchedSelectedCount,
  );
}
