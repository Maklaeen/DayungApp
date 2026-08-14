import 'package:capstone_app/profile/required_application_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RequiredApplicationContent', () {
    test('splits the main title from individual section rows', () {
      final content = RequiredApplicationContent.fromRows([
        {'id': 1, 'title': 'Main Title', 'description': ''},
        {
          'id': 2,
          'title': 'Organization Name',
          'description': 'Unity Mutual Aid Association',
        },
        {'id': 3, 'title': 'Benefits', 'description': 'Emergency support'},
      ]);

      expect(content.mainTitle, 'Main Title');
      expect(content.sections.length, 2);
      expect(content.sections.first.title, 'Organization Name');
      expect(
        content.sections.first.description,
        'Unity Mutual Aid Association',
      );
    });

    test('preserves dayung unit id when converting rows for saving', () {
      final content = RequiredApplicationContent.fromRows([
        {'title': 'Main Title', 'description': '', 'dayung_unit_id': 7},
        {
          'title': 'Benefits',
          'description': 'Emergency support',
          'dayung_unit_id': 7,
        },
      ]);

      final rows = content.toRows(
        userId: 'user-123',
        dayungUnitId: content.dayungUnitId,
      );

      expect(content.dayungUnitId, 7);
      expect(rows.first['dayung_unit_id'], 7);
      expect(rows.last['user_id'], 'user-123');
    });

    test('copies the dayung unit id into the saved content state', () {
      final content = const RequiredApplicationContent(
        mainTitle: 'Main Title',
        sections: [
          RequiredApplicationSection(
            title: 'Benefits',
            description: 'Emergency support',
          ),
        ],
        dayungUnitId: 7,
      );

      final updatedContent = content.copyWith(dayungUnitId: 9);

      expect(updatedContent.dayungUnitId, 9);
      expect(updatedContent.mainTitle, 'Main Title');
    });

    test('uses NO TITLE for a blank first section title when saving', () {
      const content = RequiredApplicationContent(
        mainTitle: 'Main Title',
        sections: [
          RequiredApplicationSection(title: '', description: 'Emergency support'),
        ],
      );

      final rows = content.toRows(userId: 'user-123', dayungUnitId: 7);

      expect(rows[1]['title'], 'NO TITLE');
      expect(rows[1]['description'], 'Emergency support');
    });

    test(
      'shows the agreement notice only when the user already has an application record',
      () {
        expect(
          RequiredApplicationsPage.shouldShowAgreementNotice(
            hasApplicationRecord: true,
          ),
          isTrue,
        );
        expect(
          RequiredApplicationsPage.shouldShowAgreementNotice(
            hasApplicationRecord: false,
          ),
          isFalse,
        );
      },
    );
  });
}
