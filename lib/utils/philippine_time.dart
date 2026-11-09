const _philippineOffset = Duration(hours: 8);

DateTime? parseUtcTimestamp(dynamic value) {
  if (value is DateTime) return value.toUtc();
  if (value == null) return null;

  final timestamp = value.toString().trim();
  if (timestamp.isEmpty) return null;

  final hasTimezone = RegExp(
    r'(?:[zZ]|[+-]\d{2}(?::?\d{2})?)$',
  ).hasMatch(timestamp);
  return DateTime.tryParse(hasTimezone ? timestamp : '${timestamp}Z')?.toUtc();
}

DateTime toPhilippineWallTime(DateTime value) {
  return value.toUtc().add(_philippineOffset);
}

String toPhilippineTimestamp(DateTime value) {
  final philippineTime = toPhilippineWallTime(value);
  final timestamp = philippineTime.toIso8601String().replaceFirst('Z', '');
  return '$timestamp+08:00';
}
