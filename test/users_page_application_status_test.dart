import 'package:capstone_app/SuperAdmin/users_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('application status normalization', () {
    test('returns approved for approved values', () {
      expect(normalizeApplicationStatus('Approved'), 'approved');
      expect(normalizeApplicationStatus('approved'), 'approved');
    });

    test('returns pending for pending values', () {
      expect(normalizeApplicationStatus('Pending'), 'pending');
      expect(normalizeApplicationStatus('pending'), 'pending');
    });

    test('returns null for unrelated values', () {
      expect(normalizeApplicationStatus('rejected'), null);
      expect(normalizeApplicationStatus(null), null);
    });
  });
}
