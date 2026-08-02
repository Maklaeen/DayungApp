import 'package:capstone_app/pages/membership_agreement_page.dart';
import 'package:capstone_app/profile/required_application_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'agreement content is only shown when the user has an application record',
    () {
      expect(
        MembershipAgreementPage.shouldShowAgreementContent(
          hasApplicationRecord: true,
          hasRequiredApplicationContent: true,
        ),
        isTrue,
      );

      expect(
        MembershipAgreementPage.shouldShowAgreementContent(
          hasApplicationRecord: false,
          hasRequiredApplicationContent: true,
        ),
        isFalse,
      );

      expect(
        MembershipAgreementPage.shouldShowAgreementContent(
          hasApplicationRecord: true,
          hasRequiredApplicationContent: false,
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'Membership agreement page shows content from required applications',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MembershipAgreementPage(
            initialContent: const RequiredApplicationContent(
              mainTitle: 'Membership Terms',
              sections: [
                RequiredApplicationSection(
                  title: 'Eligibility',
                  description: 'Members must be active and verified.',
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Membership Agreement'), findsOneWidget);
      expect(find.text('Membership Terms'), findsOneWidget);
      expect(find.text('Eligibility'), findsOneWidget);
      expect(find.text('Members must be active and verified.'), findsOneWidget);
    },
  );
}
