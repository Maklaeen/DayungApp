import 'package:intl/intl.dart';
import 'package:capstone_app/utils/philippine_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats UTC timestamps in Philippine time with seconds', () {
    final value = parseUtcTimestamp('2026-10-29 11:12:37.139+00');
    expect(value, isNotNull);

    expect(
      DateFormat(
        "MMMM d, y, 'at' h:mm:ss a",
      ).format(toPhilippineWallTime(value!)),
      'October 29, 2026, at 7:12:37 PM',
    );
  });

  test('treats timestamps without an offset as UTC', () {
    final value = parseUtcTimestamp('2026-10-29 11:12:37.139');

    expect(value, DateTime.utc(2026, 10, 29, 11, 12, 37, 139));
    expect(
      DateFormat(
        "MMMM d, y, 'at' h:mm:ss a",
      ).format(toPhilippineWallTime(value!)),
      'October 29, 2026, at 7:12:37 PM',
    );
  });

  test('formats an instant with the Philippine UTC+8 offset', () {
    final value = DateTime.utc(2026, 10, 29, 11, 56, 49);

    final timestamp = toPhilippineTimestamp(value);
    final parsed = DateTime.parse(timestamp);

    expect(timestamp, '2026-10-29T19:56:49.000+08:00');
    expect(parsed.toUtc(), value);
  });
}
