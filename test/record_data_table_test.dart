import 'package:capstone_app/widgets/record_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('record tables render readable cards on mobile', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var selected = false;
    var cellTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordDataTable(
            minWidth: 700,
            columns: const [
              DataColumn(label: Text('Member')),
              DataColumn(label: Text('Status')),
            ],
            rows: [
              DataRow(
                cells: [
                  DataCell(
                    const Text('Sample Member'),
                    onTap: () => cellTapped = true,
                  ),
                  DataCell(Text('Active')),
                ],
                onSelectChanged: (value) => selected = value ?? false,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Member'), findsOneWidget);
    expect(find.text('Sample Member'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    await tester.tap(find.text('Sample Member'));
    expect(cellTapped, isTrue);
    await tester.tap(find.byType(Checkbox));
    expect(selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('record tables handle unbounded horizontal constraints', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: RecordDataTable(
              columns: [
                DataColumn(label: Text('Member')),
                DataColumn(label: Text('Status')),
              ],
              rows: [
                DataRow(
                  cells: [
                    DataCell(Text('Sample Member')),
                    DataCell(Text('Active')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
