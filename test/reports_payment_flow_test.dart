import 'package:capstone_app/pages/reports.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('summarizePaymentFlowRows', () {
    test('aggregates totals and latest claimed date', () {
      final rows = [
        {
          'amount': 100,
          'iscollectedbytreasurer': true,
          'is_claimed': false,
          'is_claimed_date': null,
        },
        {
          'amount': '250.5',
          'iscollectedbytreasurer': false,
          'is_claimed': true,
          'is_claimed_date': '2024-06-12T10:00:00.000Z',
        },
        {
          'amount': 75.25,
          'iscollectedbytreasurer': true,
          'is_claimed': true,
          'is_claimed_date': '2024-07-01T10:00:00.000Z',
        },
      ];

      final summary = summarizePaymentFlowRows(rows);

      expect(summary['in'], 175.25);
      expect(summary['out'], 325.75);
      expect(summary['date'], '2024-07-01');
    });
  });
}
