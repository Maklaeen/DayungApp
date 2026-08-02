import 'package:capstone_app/pages/reports.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'formats reports date as Philippine date and time in 12-hour format',
    () {
      const raw = '2026-08-02T14:35:00.000Z';

      expect(formatPhilippineDateTime(raw), 'Aug 2, 2026 • 10:35 PM');
    },
  );

  test('handles UTC claim timestamps from Supabase correctly', () {
    const raw = '2026-08-02 12:07:40.864+00';

    expect(formatPhilippineDateTime(raw), 'Aug 2, 2026 • 8:07 PM');
  });

  test('returns fallback for empty values', () {
    expect(formatPhilippineDateTime(null), '—');
    expect(formatPhilippineDateTime(''), '—');
  });
}
