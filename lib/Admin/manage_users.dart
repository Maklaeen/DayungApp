import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageUsersPage extends StatefulWidget {
  const ManageUsersPage({super.key});

  @override
  State<ManageUsersPage> createState() => _ManageUsersPageState();
}

class _ManageUsersPageState extends State<ManageUsersPage> {
  List<Map<String, dynamic>> users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() => _loading = true);
    final data = await Supabase.instance.client
        .from('users')
        .select('id, full_name, email, role, status')
        .order('full_name', ascending: true);
    setState(() {
      users = List<Map<String, dynamic>>.from(data);
      _loading = false;
    });
  }

  Future<void> _updateRole(String userId, String newRole) async {
    await Supabase.instance.client
        .from('users')
        .update({'role': newRole})
        .eq('id', userId);
    _fetchUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Users')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, i) {
                final user = users[i];
                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(user['full_name'] ?? ''),
                  subtitle: Text('${user['email']} • ${user['role']}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) => _updateRole(user['id'], value),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'admin', child: Text('Make Admin')),
                      const PopupMenuItem(value: 'secretary', child: Text('Make Secretary')),
                      const PopupMenuItem(value: 'member', child: Text('Make Member')),
                    ],
                  ),
                );
              },
            ),
    );
  }
}