import 'package:capstone_app/Auth/login.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('membership redirect guard', () {
    test('opens apply membership wizard only for for_confirmation status', () {
      expect(shouldOpenApplyMembershipWizard('for_confirmation'), isTrue);
      expect(shouldOpenApplyMembershipWizard('approved'), isFalse);
      expect(shouldOpenApplyMembershipWizard('pending'), isFalse);
      expect(shouldOpenApplyMembershipWizard(null), isFalse);
    });
  });
}
