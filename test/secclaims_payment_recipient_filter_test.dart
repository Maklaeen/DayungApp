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
        {'user_id': 'user-1', 'status': 'paid', 'type': 'membership fee'},
        {'user_id': 'user-2', 'status': 'unpaid', 'type': 'membership fee'},
      ];

      final recipients = filterPaymentRecipientsForDeceasedClaim(
        approvedApplications: approvedApplications,
        membershipFeePayments: membershipFeePayments,
        deceasedUserId: 'user-3',
      );

      expect(recipients.map((recipient) => recipient['user_id']), ['user-1']);
    });
  });
}
