import 'package:capstone_app/Treasurer/ledger_balance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('filterCollectorsCollectedPayments', () {
    test('includes only paid deceased payments collected by the treasurer', () {
      final rows = [
        {
          'id': 'received',
          'type': 'deceased_payment',
          'status': 'paid',
          'collected_by': 'collector-1',
          'iscollectedbytreasurer': true,
        },
        {
          'id': 'not-received',
          'type': 'deceased_payment',
          'status': 'paid',
          'collected_by': 'collector-1',
          'iscollectedbytreasurer': false,
        },
        {
          'id': 'unpaid',
          'type': 'deceased_payment',
          'status': 'unpaid',
          'collected_by': 'collector-1',
          'iscollectedbytreasurer': true,
        },
        {
          'id': 'other-payment',
          'type': 'regular_payment',
          'status': 'paid',
          'collected_by': 'collector-1',
          'iscollectedbytreasurer': true,
        },
        {
          'id': 'no-collector',
          'type': 'deceased_payment',
          'status': 'paid',
          'iscollectedbytreasurer': true,
        },
      ];

      final filtered = filterCollectorsCollectedPayments(rows);

      expect(filtered.map((row) => row['id']), ['received']);
    });
  });

  group('calculateDeceasedPaymentLedgerBalance', () {
    test('does not make the balance negative for a claimed payment', () {
      final rows = [
        {
          'type': 'deceased_payment',
          'amount': 500,
          'iscollectedbytreasurer': false,
          'is_claimed': true,
        },
      ];

      expect(calculateDeceasedPaymentLedgerBalance(rows), 0);
    });

    test('excludes a claimed payment even after it was received', () {
      final rows = [
        {
          'type': 'deceased_payment',
          'amount': 500,
          'iscollectedbytreasurer': true,
          'is_claimed': true,
        },
      ];

      expect(calculateDeceasedPaymentLedgerBalance(rows), 0);
    });

    test('includes received, unclaimed deceased payments only', () {
      final rows = [
        {
          'type': 'deceased_payment',
          'amount': 500,
          'iscollectedbytreasurer': true,
          'is_claimed': false,
        },
        {
          'type': 'deceased_payment',
          'amount': 200,
          'iscollectedbytreasurer': false,
          'is_claimed': false,
        },
        {
          'type': 'regular_payment',
          'amount': 100,
          'iscollectedbytreasurer': true,
          'is_claimed': false,
        },
      ];

      expect(calculateDeceasedPaymentLedgerBalance(rows), 500);
    });
  });
}
