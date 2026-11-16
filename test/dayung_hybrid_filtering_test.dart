import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_app/utils/dayung_recommendations.dart';
import 'package:capstone_app/utils/dayung_similarity.dart';

void main() {
  group('dayung hybrid filtering', () {
    test('requires at least five selected preferences for recommendations', () {
      expect(hasEnoughRecommendationPreferences(4), isFalse);
      expect(hasEnoughRecommendationPreferences(5), isTrue);
      expect(hasEnoughRecommendationPreferences(6), isTrue);
    });

    test('matches exact contribution amounts to inclusive ranges', () {
      expect(isAmountInRange('100', '50-100'), isTrue);
      expect(isAmountInRange(100, '100-150'), isTrue);
      expect(isAmountInRange('150', '100-150'), isTrue);
      expect(isAmountInRange(150.01, '100-150'), isFalse);
      expect(isAmountInRange('400', '400 plus'), isTrue);
      expect(isAmountInRange(500, '400 plus'), isTrue);
      expect(isAmountInRange(399.99, '400 plus'), isFalse);
      expect(isAmountInRange(null, '100-150'), isFalse);
      expect(isAmountInRange('invalid', '100-150'), isFalse);
    });

    test('matches exact membership amounts to inclusive ranges', () {
      expect(isAmountInRange('50', '50-100'), isTrue);
      expect(isAmountInRange(100, '100-150'), isTrue);
      expect(isAmountInRange('150', '100-150'), isTrue);
      expect(isAmountInRange(150.01, '100-150'), isFalse);
      expect(isAmountInRange('400', '400 plus'), isTrue);
    });

    test('builds the 37-dimension pgvector query in database column order', () {
      const preferences = DayungPreferencesData(
        meetingFrequency: 'Weekly',
        contributionAmount: '100-150',
        paymentMethod: 'Cash',
        serviceTags: {'Prayer Support': true},
      );
      final vector = DayungRecommendationService.preferenceVector(preferences);

      expect(vector, hasLength(37));
      expect(vector[0], 1.0);
      expect(vector[3], 1.0);
      expect(vector[7], 1.0);
      expect(vector[27], 0.0);
      expect(vector[36], 1.0);
      expect(
        preferences.toUpsertPayload('user-id').containsKey('open_for_all'),
        isFalse,
      );
      expect(
        DayungRecommendationService.serializePreferenceVector(vector),
        startsWith('[1.0,0.0,0.0,1.0'),
      );
    });

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

    test('scores 37-position vectors with the configured feature weight', () {
      final userVector = List<double>.filled(37, 0.0)..[0] = 1.0;
      final unitVector = List<double>.filled(37, 0.0)
        ..[0] = 1.0
        ..[1] = 1.0;

      final score = computeHybridScore(userVector, unitVector);

      expect(score.selectedCount, 1);
      expect(score.matchedSelectedCount, 1);
      expect(score.cosineSimilarity, closeTo(0.7071067811865475, 1e-12));
      expect(score.attributeMatchBoost, 1 + hybridAttributeMatchWeight);
      expect(score.finalScore, closeTo(0.8838834764831844, 1e-12));
    });

    test(
      'builds identical preference and rule vectors for both result pages',
      () {
        final preferences = <String, dynamic>{
          'meeting_frequency': 'Weekly',
          'payment_method': 'Cash',
          'contribution_amount': '100-150',
          'membership_payment': '200-250',
          'penalty_payment': '400 plus',
          'prayer_support': true,
        };
        final rule = <String, dynamic>{
          'meeting_frequency': 'weekly',
          'payment_method': 'cash',
          'exactamountforcollection': 125,
          'exactamountformembership': 225,
          'exactpenaltypayment': 450,
          'prayer_support': true,
        };

        final userVector = generateDayungPreferenceVector(preferences);
        final unitVector = buildDayungRuleVector(rule);

        expect(userVector, hasLength(37));
        expect(unitVector, hasLength(37));
        expect(unitVector, userVector);
        expect(userVector[0], 1.0);
        expect(unitVector[0], 1.0);
        expect(userVector[36], 1.0);
        expect(unitVector[36], 1.0);
        expect(countDayungPreferences(preferences), 6);
        expect(
          hasEnoughRecommendationPreferences(
            countDayungPreferences(preferences),
          ),
          isTrue,
        );
      },
    );

    test('converts the hybrid score into a bounded match percentage', () {
      expect(hybridScoreAsPercentage(1.25), 100);
      expect(hybridScoreAsPercentage(1.02062073), closeTo(81.6496584, 1e-6));
      expect(hybridScoreAsPercentage(-0.2), 0);
      expect(hybridScoreAsPercentage(1.5), 100);
    });

    test('includes proximity in the percentage within a 20 km radius', () {
      expect(hybridScoreAsPercentage(1.25, distanceKm: 0), 100);
      expect(hybridScoreAsPercentage(1.25, distanceKm: 10), 85);
      expect(hybridScoreAsPercentage(1.25, distanceKm: 20), 70);
      expect(hybridScoreAsPercentage(1.25, distanceKm: 30), 70);
      expect(dayungDistanceKm(14.0, 121.0, 14.0, 121.0), 0);
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
