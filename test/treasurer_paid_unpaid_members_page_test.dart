import 'package:capstone_app/Treasurer/paid_unpaid_members_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows paid and unpaid tabs with provided data', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PaidUnpaidMembersPage(
          dayungUnitId: 42,
          initialTab: 0,
          memberLoader: (status) async => [
            PaymentMember(
              id: '1',
              userId: 'u1',
              fullName: 'Juan Dela Cruz',
              status: status,
              amount: 100,
              date: '2024-01-01T00:00:00Z',
              deceasedName: 'Maria Dela Cruz',
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Paid'), findsWidgets);
    expect(find.text('Unpaid'), findsWidgets);
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('Deceased Name: Maria Dela Cruz'), findsOneWidget);
    expect(find.text('Date: Jan 1, 2024 • 8:00 AM'), findsOneWidget);
  });

  testWidgets('confirms the deceased and amount before marking paid', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PaidUnpaidMembersPage(
          dayungUnitId: 42,
          initialTab: 1,
          memberLoader: (status) async => [
            PaymentMember(
              id: '1',
              userId: 'u1',
              fullName: 'Juan Dela Cruz',
              status: status,
              amount: 125,
              deceasedName: 'Maria Dela Cruz',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark as Paid'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        "Mark Juan Dela Cruz's payment of ₱125.00 for Maria Dela Cruz as paid?",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
