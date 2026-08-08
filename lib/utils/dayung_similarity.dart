import 'dart:math' as math;

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
      : 1.0 + 0.25 * (matchedSelectedCount / selectedCount);

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
