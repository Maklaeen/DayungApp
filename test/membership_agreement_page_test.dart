import 'package:capstone_app/pages/membership_agreement_page.dart';
import 'package:capstone_app/profile/required_application_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('agreement content is only shown for an approved application', () {
    expect(
      MembershipAgreementPage.shouldShowAgreementContent(
        hasApprovedApplication: true,
        hasRequiredApplicationContent: true,
      ),
      isTrue,
    );

    expect(
      MembershipAgreementPage.shouldShowAgreementContent(
        hasApprovedApplication: false,
        hasRequiredApplicationContent: true,
      ),
      isFalse,
    );

    expect(
      MembershipAgreementPage.shouldShowAgreementContent(
        hasApprovedApplication: true,
        hasRequiredApplicationContent: false,
      ),
      isFalse,
    );
  });

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

      expect(find.text('Membership Agreement4.1'), findsOneWidget);
      expect(find.text('Membership Terms'), findsOneWidget);
      expect(find.text('Eligibility'), findsOneWidget);
      expect(find.text('Members must be active and verified.'), findsOneWidget);
    },
  );

  testWidgets('shows agreed state for an existing agreement', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MembershipAgreementPage(
          initialAgreed: true,
          initialContent: const RequiredApplicationContent(
            mainTitle: 'Membership Terms',
            sections: [],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Agreed ✓'), findsOneWidget);
    expect(find.text('I Agree'), findsNothing);
  });
}
