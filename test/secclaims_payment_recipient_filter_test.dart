import 'package:capstone_app/Secretary/secclaims.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('filterPaymentRecipientsForDeceasedClaim', () {
    test('excludes users with unpaid membership fee payments', () {
      final approvedApplications = [
        {'user_id': 'user-1'},
        {'user_id': 'user-2'},
        {'user_id': 'user-3'},
      ];

      final membershipFeePayments = [
        {'user_id': 'user-1', 'status': 'paid', 'type': 'membership_payment'},
        {'user_id': 'user-2', 'status': 'unpaid', 'type': 'membership_payment'},
      ];

      final recipients = filterPaymentRecipientsForDeceasedClaim(
        approvedApplications: approvedApplications,
        membershipFeePayments: membershipFeePayments,
        deceasedUserId: 'user-3',
      );

      expect(recipients.map((recipient) => recipient['user_id']), ['user-1']);
    });
  });

  test(
    'sums only paid payments collected by the treasurer for the deceased',
    () {
      final total = calculateTreasurerCollectedAmount(
        userDeceased: 'deceased-1',
        paymentRows: [
          {
            'userdeceased': 'deceased-1',
            'status': 'paid',
            'iscollectedbytreasurer': true,
            'amount': 100,
          },
          {
            'userdeceased': 'deceased-1',
            'status': 'unpaid',
            'iscollectedbytreasurer': true,
            'amount': 200,
          },
          {
            'userdeceased': 'deceased-1',
            'status': 'paid',
            'iscollectedbytreasurer': false,
            'amount': 300,
          },
          {
            'userdeceased': 'deceased-2',
            'status': 'paid',
            'iscollectedbytreasurer': true,
            'amount': 400,
          },
        ],
      );

      expect(total, 100);
    },
  );
}
