import 'package:flutter/material.dart';

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
    return ListView.builder(
      shrinkWrap: true,
      itemCount: applications.length,
      itemBuilder: (context, i) {
        final app = applications[i];
        final unit = app['dayung_units'] ?? {};
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Text(unit['name'] ?? ''),
            subtitle: Text(
              '${unit['barangay'] ?? ''}${unit['city'] != null ? ', ${unit['city']}' : ''}${unit['province'] != null ? ', ${unit['province']}' : ''}',
            ),
            trailing: Text(
              (app['status'] ?? 'pending').toString().toUpperCase(),
              style: TextStyle(
                color: app['status'] == 'approved'
                    ? Colors.green
                    : app['status'] == 'rejected'
                        ? Colors.red
                        : Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      },
    );
  }
}