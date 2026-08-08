import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_app/utils/dayung_recommendations.dart';
import 'package:capstone_app/utils/dayung_similarity.dart';

void main() {
  group('dayung hybrid filtering', () {
    test('matches the sample computation from the description', () {
      final userVector = [0.0, 1.0, 1.0, 1.0, 0.0, 1.0];
      final unitA = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0];
      final unitB = [1.0, 0.0, 1.0, 1.0, 0.0, 1.0];
      final unitC = [0.0, 1.0, 1.0, 0.0, 1.0, 0.0];

      final scoreA = computeHybridScore(userVector, unitA);
      final scoreB = computeHybridScore(userVector, unitB);
      final scoreC = computeHybridScore(userVector, unitC);

      expect(scoreA.cosineSimilarity, closeTo(0.81649658, 1e-7));
      expect(scoreA.attributeMatchBoost, closeTo(1.25, 1e-7));
      expect(scoreA.finalScore, closeTo(1.02062073, 1e-7));

      expect(scoreB.cosineSimilarity, closeTo(0.75, 1e-7));
      expect(scoreB.attributeMatchBoost, closeTo(1.1875, 1e-7));
      expect(scoreB.finalScore, closeTo(0.890625, 1e-7));

      expect(scoreC.cosineSimilarity, closeTo(0.57735027, 1e-7));
      expect(scoreC.attributeMatchBoost, closeTo(1.125, 1e-7));
      expect(scoreC.finalScore, closeTo(0.649518, 1e-5));
    });

    test('ranks passing recommendations by nearest distance first', () {
      final units = <Map<String, dynamic>>[
        {'id': 1, '__score': 0.75, '__km': 15.0, '__withinRadius': true},
        {'id': 2, '__score': 0.70, '__km': 3.0, '__withinRadius': true},
        {'id': 3, '__score': 0.85, '__km': 8.0, '__withinRadius': true},
        {'id': 4, '__score': 0.20, '__km': 1.0, '__withinRadius': true},
      ];

      final ranked = DayungRecommendationService.rankEligibleUnits(
        units,
        limit: 3,
        similarityThreshold: 0.3,
      );

      expect(ranked.map((unit) => unit['id']), [2, 3, 1]);
    });
  });
}
