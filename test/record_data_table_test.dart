import 'package:capstone_app/widgets/record_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('record tables use readable default styling on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordDataTable(
            minWidth: 700,
            columns: const [
              DataColumn(label: Text('Member')),
              DataColumn(label: Text('Status')),
            ],
            rows: const [
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
    );

    final table = tester.widget<DataTable>(find.byType(DataTable));
    expect(table.dataRowMinHeight, 72);
    expect(table.dataRowMaxHeight, 144);
    expect(table.headingTextStyle?.fontSize, 16);
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
