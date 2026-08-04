import 'package:capstone_app/Treasurer/dashboard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldCountCurrentFundPayment', () {
    test('excludes payments when is_claimed is true', () {
      final row = {
        'is_claimed': true,
        'iscollectedbytreasurer': true,
        'status': 'paid',
        'type': 'deceased_payment',
      };

      expect(shouldCountCurrentFundPayment(row), isFalse);
    });

    test('includes payments when not claimed and treasurer collected', () {
      final row = {
        'is_claimed': false,
        'iscollectedbytreasurer': true,
        'status': 'paid',
        'type': 'deceased_payment',
      };

      expect(shouldCountCurrentFundPayment(row), isTrue);
    });

    test('excludes payments when treasurer has not collected them', () {
      final row = {
        'is_claimed': false,
        'iscollectedbytreasurer': false,
        'status': 'paid',
        'type': 'deceased_payment',
      };

      expect(shouldCountCurrentFundPayment(row), isFalse);
    });
  });
}
