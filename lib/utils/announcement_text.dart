String cleanAnnouncementText(Object? value) {
  final text = (value ?? '')
      .toString()
      .replaceAll('**', '')
      .replaceAll('__', '')
      .trim();

  return text
      .replaceFirst(RegExp(r'^title\s*:\s*', caseSensitive: false), '')
      .trim();
}

String cleanAnnouncementTitle(Object? value) {
  return cleanAnnouncementText(value);
}
