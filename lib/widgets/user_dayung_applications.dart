import 'package:flutter/material.dart';
import 'package:capstone_app/widgets/record_data_table.dart';

class UserDayungApplications extends StatelessWidget {
  final List<Map<String, dynamic>> applications;
  const UserDayungApplications({super.key, required this.applications});

  @override
  Widget build(BuildContext context) {
    if (applications.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No dayung applications yet.'),
      );
    }
    return RecordDataTable(
      minWidth: 600,
      columns: const [
        DataColumn(label: Text('Dayung unit')),
        DataColumn(label: Text('Location')),
        DataColumn(label: Text('Status')),
      ],
      rows: applications.map((app) {
        final unit = app['dayung_units'] ?? {};
        final location = [
          unit['barangay'],
          unit['city'],
          unit['province'],
        ].where((part) => part != null && part.toString().isNotEmpty).join(', ');
        final status = (app['status'] ?? 'pending').toString();
        return DataRow(
          cells: [
            DataCell(Text((unit['name'] ?? '').toString())),
            DataCell(Text(location)),
            DataCell(
              Text(
                status.toUpperCase(),
                style: TextStyle(
                  color: status == 'approved'
                      ? Colors.green
                      : status == 'rejected'
                      ? Colors.red
                      : Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}