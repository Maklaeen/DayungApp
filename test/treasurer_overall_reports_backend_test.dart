import 'package:capstone_app/Treasurer/treasurer_overall_reports.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deduplicates members by user_id and resolves full_name from users', () {
    final rows = [
      {
        'user_id': 'u-1',
        'amount': 200,
        'status': 'paid',
        'type': 'deceased_payment',
        'paid_at': '2024-01-01T10:00:00Z',
        'users': {'full_name': 'Ana Rosa'},
      },
      {
        'user_id': 'u-1',
        'amount': 500,
        'status': 'paid',
        'type': 'deceased_payment',
        'paid_at': '2024-01-02T10:00:00Z',
        'users': {'full_name': 'Ana Rosa'},
      },
      {
        'user_id': 'u-2',
        'amount': 300,
        'status': 'unpaid',
        'type': 'deceased_payment',
        'paid_at': '2024-01-03T10:00:00Z',
        'users': {'full_name': 'Jose Cruz'},
      },
      {
        'user_id': 'u-3',
        'amount': 999,
        'status': 'paid',
        'type': 'membership_payment',
        'users': {'full_name': 'Ignored Member'},
      },
      {
        'user_id': '',
        'amount': 999,
        'status': 'paid',
        'type': 'deceased_payment',
        'users': {'full_name': 'Ignored Empty Member'},
      },
    ];

    final members = TreasurerOverallReportsMemberBuilder.fromPaymentRows(rows);

    expect(members.length, 2);
    expect(members.any((m) => m.userId == 'u-1' && m.amount == 500), isTrue);
    expect(
      members.any((m) => m.userId == 'u-2' && m.name == 'Jose Cruz'),
      isTrue,
    );
    expect(
      members.any(
        (m) => m.userId == 'u-1' && m.dropStatus.toLowerCase() == 'no',
      ),
      isTrue,
    );
    expect(
      members.any(
        (m) => m.userId == 'u-2' && m.dropStatus.toLowerCase() == 'yes',
      ),
      isTrue,
    );
    expect(members.every((m) => m.name != 'Ignored Member'), isTrue);
  });

  test('normalizes active notice index for empty and out-of-range tabs', () {
    expect(TreasurerOverallReportsPage.safeActiveTabIndex(0, 0), 0);
    expect(TreasurerOverallReportsPage.safeActiveTabIndex(4, 2), 1);
    expect(TreasurerOverallReportsPage.safeActiveTabIndex(-2, 3), 0);
  });

  test('includes the total advance payment per member', () {
    final rows = [
      {
        'user_id': 'u-1',
        'amount': 200,
        'status': 'paid',
        'type': 'deceased_payment',
        'paid_at': '2024-01-01T10:00:00Z',
        'users': {'full_name': 'Ana Rosa'},
      },
      {
        'user_id': 'u-2',
        'amount': 300,
        'status': 'unpaid',
        'type': 'deceased_payment',
        'paid_at': '2024-01-03T10:00:00Z',
        'users': {'full_name': 'Jose Cruz'},
      },
    ];

    final members = TreasurerOverallReportsMemberBuilder.fromPaymentRows(
      rows,
      const [],
      {'u-1': 250.0, 'u-2': 0.0},
    );

    expect(members.firstWhere((m) => m.userId == 'u-1').advanceAmount, 250.0);
    expect(members.firstWhere((m) => m.userId == 'u-2').advanceAmount, 0.0);
  });
}
