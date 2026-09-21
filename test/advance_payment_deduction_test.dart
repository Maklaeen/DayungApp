import 'package:capstone_app/Secretary/secclaims.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('advance payment deduction', () {
    test('fully consumes a matching advance payment balance', () {
      final result = applyAdvancePaymentDeduction(
        remainingAmount: 100,
        currentAdvanceAmount: 100,
      );

      expect(result['deduction'], 100);
      expect(result['updatedAmount'], 0);
      expect(result['hasRemaining'], isFalse);
    });

    test('partially reduces the advance payment balance', () {
      final result = applyAdvancePaymentDeduction(
        remainingAmount: 70,
        currentAdvanceAmount: 100,
      );

      expect(result['deduction'], 70);
      expect(result['updatedAmount'], 30);
      expect(result['hasRemaining'], isTrue);
    });
  });
}
