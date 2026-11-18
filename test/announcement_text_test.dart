import 'package:capstone_app/utils/announcement_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes markdown emphasis and a leading title label', () {
    expect(
      cleanAnnouncementTitle('**Title:** Monthly General Meeting Announcement'),
      'Monthly General Meeting Announcement',
    );
  });

  test('keeps regular announcement titles unchanged', () {
    expect(
      cleanAnnouncementTitle('Monthly General Meeting Announcement'),
      'Monthly General Meeting Announcement',
    );
  });

  test('removes markdown emphasis from announcement descriptions', () {
    expect(
      cleanAnnouncementText('**Title:** Monthly General Meeting Announcement'),
      'Monthly General Meeting Announcement',
    );
  });
}
