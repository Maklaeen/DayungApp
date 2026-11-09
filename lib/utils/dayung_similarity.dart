import 'dart:math' as math;

const double hybridAttributeMatchWeight = 0.25;
const int minimumRecommendationPreferenceCount = 5;

bool hasEnoughRecommendationPreferences(int selectedCount) =>
    selectedCount >= minimumRecommendationPreferenceCount;

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
