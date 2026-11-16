import 'package:capstone_app/shared/president_secretary_member_reports.dart';
import 'package:capstone_app/ui/theme/dayung_theme.dart';
import 'package:capstone_app/widgets/record_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shared Material surfaces follow each theme brightness', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final theme = buildDayungTheme(brightness);
      final isDark = brightness == Brightness.dark;

      expect(theme.cardTheme.color, theme.colorScheme.surface);
      expect(theme.dialogTheme.backgroundColor, theme.colorScheme.surface);
      expect(theme.bottomSheetTheme.backgroundColor, theme.colorScheme.surface);
      expect(theme.popupMenuTheme.color, theme.colorScheme.surface);
      expect(
        theme.inputDecorationTheme.fillColor,
        isDark ? isNot(theme.colorScheme.surface) : theme.colorScheme.surface,
      );
      expect(
        theme.dataTableTheme.headingRowColor?.resolve(const {}),
        isDark
            ? theme.colorScheme.surfaceContainerHigh
            : theme.colorScheme.primaryContainer,
      );
    }
  });

  testWidgets('membership summary and report table use theme surfaces', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final brightness in [Brightness.light, Brightness.dark]) {
      final theme = buildDayungTheme(brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          themeAnimationDuration: Duration.zero,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const PresidentSecretaryMemberReports(
                    addedMembers: 2,
                    removedMembers: 1,
                    deceasedMembers: 0,
                    deceasedBeneficiaries: 0,
                  ),
                  SizedBox(
                    width: 900,
                    child: RecordDataTable(
                      columns: const [DataColumn(label: Text('Name'))],
                      rows: const [
                        DataRow(cells: [DataCell(Text('Member'))]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final summary = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Membership Activity'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (summary.decoration! as BoxDecoration).color,
        theme.colorScheme.surface,
      );

      final table = tester.widget<DataTable>(find.byType(DataTable));
      expect(
        table.headingRowColor!.resolve(const {}),
        brightness == Brightness.dark
            ? theme.colorScheme.surfaceContainerHigh
            : theme.colorScheme.primaryContainer,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
