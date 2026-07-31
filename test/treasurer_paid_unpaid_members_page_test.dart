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
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Paid'), findsWidgets);
    expect(find.text('Unpaid'), findsWidgets);
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
  });
}
