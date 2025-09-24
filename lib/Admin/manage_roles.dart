import 'package:flutter/material.dart';

class ManageRolesPage extends StatelessWidget {
  const ManageRolesPage({super.key});

  @override
  Widget build(BuildContext context) {
    // You can expand this to allow adding/removing roles if you store them in a table
    final roles = ['admin', 'secretary', 'member', 'president'];
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Roles')),
      body: ListView.builder(
        itemCount: roles.length,
        itemBuilder: (context, i) => ListTile(
          leading: const Icon(Icons.security),
          title: Text(roles[i]),
        ),
      ),
    );
  }
}