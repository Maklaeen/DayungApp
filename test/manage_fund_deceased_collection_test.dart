import 'package:capstone_app/Treasurer/manage_fund.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deceasedUsersFromClaims', () {
    test('returns distinct non-empty claims user IDs', () {
      expect(
        deceasedUsersFromClaims([
          {'user_id': 'deceased-1'},
          {'user_id': ' deceased-1 '},
          {'user_id': 'deceased-2'},
          {'user_id': ''},
          {'user_id': null},
        ]),
        ['deceased-1', 'deceased-2'],
      );
    });
  });
}
