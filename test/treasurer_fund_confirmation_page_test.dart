import 'package:capstone_app/Treasurer/treasurer_fund_confirmation_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('subtracts amounts already marked received by treasurer', () {
    final paymentRows = [
      {
        'amount': 100.0,
        'collected_by': 'collector-1',
        'userdeceased': 'member-1',
        'iscollectedbytreasurer': false,
      },
      {
        'amount': 50.0,
        'collected_by': 'collector-1',
        'userdeceased': 'member-1',
        'iscollectedbytreasurer': true,
      },
      {
        'amount': 25.0,
        'collected_by': 'collector-1',
        'userdeceased': 'member-2',
        'iscollectedbytreasurer': true,
      },
      {
        'amount': 75.0,
        'collected_by': 'collector-2',
        'userdeceased': 'member-3',
        'iscollectedbytreasurer': false,
      },
    ];

    expect(
      calculateCollectorPendingAmount(
        paymentRows: paymentRows,
        collectorId: 'collector-1',
      ),
      100.0,
    );
  });
}
