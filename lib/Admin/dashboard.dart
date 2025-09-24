import 'package:capstone_app/Auth/login.dart';
import 'package:flutter/material.dart';
import 'package:capstone_app/Admin/assign_user_dayung.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 24),
          const Center(
            child: Icon(
              Icons.admin_panel_settings,
              size: 80,
              color: Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Welcome, Admin!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 32),
          _AdminTile(
            icon: Icons.people,
            label: 'Manage Users',
            onTap: () => Navigator.pushNamed(context, '/admin-users'),
          ),
          _AdminTile(
            icon: Icons.security,
            label: 'Manage Roles',
            onTap: () => Navigator.pushNamed(context, '/admin-roles'),
          ),
          _AdminTile(
            icon: Icons.house,
            label: 'Manage Dayung Units',
            onTap: () => Navigator.pushNamed(context, '/admin-dayung-units'),
          ),
          _AdminTile(
            icon: Icons.assignment_ind,
            label: 'Assign User to Dayung',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AssignUserToDayungWidget(),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              onPressed: () async {
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Logged out successfully')),
                  );
                  await Future.delayed(const Duration(milliseconds: 800));
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const Login()),
                    (route) => false,
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AdminTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: ListTile(
        leading: Icon(icon, size: 36, color: Colors.blueGrey),
        title: Text(label, style: const TextStyle(fontSize: 20)),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: onTap,
      ),
    );
  }
}
