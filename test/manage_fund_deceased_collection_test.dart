import 'package:capstone_app/Treasurer/manage_fund.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldCountDeceasedCollectionPayment', () {
    test('returns true when the payment is paid and confirmed by the treasurer', () {
      expect(
        shouldCountDeceasedCollectionPayment({
          'status': 'paid',
          'iscollectedbytreasurer': true,
        }),
        isTrue,
      );
    });

    test('returns false when the treasurer flag is not true', () {
      expect(
        shouldCountDeceasedCollectionPayment({
          'status': 'paid',
          'iscollectedbytreasurer': false,
        }),
        isFalse,
      );
    });

    test('returns false when the payment is not paid', () {
      expect(
        shouldCountDeceasedCollectionPayment({
          'status': 'pending',
          'iscollectedbytreasurer': true,
        }),
        isFalse,
      );
    });
  });
}
