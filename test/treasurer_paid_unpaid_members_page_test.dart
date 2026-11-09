import 'package:capstone_app/Treasurer/paid_unpaid_members_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _selectDeceased(WidgetTester tester, String deceasedName) async {
  await tester.tap(find.text('Choose deceased member'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(deceasedName));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('filters paid and unpaid members by selected deceased', (
    tester,
  ) async {
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
              userDeceasedId: 'd1',
            ),
            PaymentMember(
              id: '2',
              userId: 'u2',
              fullName: 'Ana Santos',
              status: status,
              amount: 200,
              deceasedName: 'Pedro Santos',
              userDeceasedId: 'd2',
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Paid'), findsWidgets);
    expect(find.text('Unpaid'), findsWidgets);
    expect(find.text('Juan Dela Cruz'), findsNothing);
    expect(find.text('Ana Santos'), findsNothing);

    await _selectDeceased(tester, 'Maria Dela Cruz');

    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('Ana Santos'), findsNothing);
    expect(find.text('User ID: u1'), findsOneWidget);
    expect(find.text('Deceased Name: Maria Dela Cruz'), findsOneWidget);
    expect(find.text('Date: Jan 1, 2024 • 8:00 AM'), findsOneWidget);

    await tester.tap(find.text('Unpaid').last);
    await tester.pumpAndSettle();
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('Ana Santos'), findsNothing);
  });

  testWidgets('confirms the deceased and amount before marking paid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

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
              userDeceasedId: 'd1',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectDeceased(tester, 'Maria Dela Cruz');

    await tester.ensureVisible(find.text('Mark as Paid'));
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
