import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kPrimary = Color(0xFF1E40AF);
const kCardBg = Color(0xFFFFFFFF);
const kSubText = Color(0xFF6B7280);

class SuperAdminUsersPage extends StatefulWidget {
  const SuperAdminUsersPage({super.key});

  @override
  State<SuperAdminUsersPage> createState() => _SuperAdminUsersPageState();
}

class _SuperAdminUsersPageState extends State<SuperAdminUsersPage> {
  late Future<List<Map<String, dynamic>>> _usersFuture;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _usersFuture = _fetchUsers();
  }

  Future<List<Map<String, dynamic>>> _fetchUsers() async {
    final sb = Supabase.instance.client;
    final res = await sb
        .from('users')
        .select('id, full_name, email, role, is_deceased');
    return List<Map<String, dynamic>>.from(res);
  }

  void _editUser(Map<String, dynamic> user) async {
    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditUserDialog(user: user),
    );
    if (updated != null) {
      setState(() {
        _usersFuture = _fetchUsers();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeBg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF18181B)
        : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: themeBg,
      appBar: AppBar(
        title: const Text('Manage Users'),
        backgroundColor: kPrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search by name or email...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: kCardBg,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 0,
                    horizontal: 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: kPrimary.withOpacity(0.15)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: kPrimary.withOpacity(0.15)),
                  ),
                ),
                onChanged: (v) =>
                    setState(() => _search = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _usersFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('No users found.'));
                  }
                  final users = snapshot.data!
                      .where(
                        (u) =>
                            (u['full_name'] ?? '')
                                .toString()
                                .toLowerCase()
                                .contains(_search) ||
                            (u['email'] ?? '')
                                .toString()
                                .toLowerCase()
                                .contains(_search),
                      )
                      .toList();
                  if (users.isEmpty) {
                    return const Center(
                      child: Text('No users match your search.'),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final user = users[i];
                      return Material(
                        color: kCardBg,
                        borderRadius: BorderRadius.circular(16),
                        elevation: 1,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: kPrimary.withOpacity(0.1),
                            child: Icon(Icons.person, color: kPrimary),
                          ),
                          title: Text(
                            user['full_name'] ?? 'No Name',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user['email'] ?? '',
                                style: const TextStyle(fontSize: 13),
                              ),
                              Row(
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(
                                      top: 4,
                                      right: 8,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kPrimary.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      user['role'] ?? 'member',
                                      style: TextStyle(
                                        color: kPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  if (user['is_deceased'] == true)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'Deceased',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit, color: kPrimary),
                            onPressed: () => _editUser(user),
                            tooltip: 'Edit User',
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditUserDialog extends StatefulWidget {
  final Map<String, dynamic> user;
  const _EditUserDialog({required this.user});

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  String? _role;
  bool? _isDeceased;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.user['full_name'] ?? '',
    );
    _emailController = TextEditingController(text: widget.user['email'] ?? '');
    _role = widget.user['role'] ?? 'member';
    _isDeceased = widget.user['is_deceased'] ?? false;
  }

  Future<void> _save() async {
    final sb = Supabase.instance.client;
    await sb
        .from('users')
        .update({
          'full_name': _nameController.text,
          'email': _emailController.text,
          'role': _role,
          'is_deceased': _isDeceased,
        })
        .eq('id', widget.user['id']);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: kCardBg,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.edit, color: kPrimary, size: 36),
              const SizedBox(height: 8),
              const Text(
                'Edit User',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: kPrimary,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.person),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.email),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _role,
                items: const [
                  DropdownMenuItem(value: 'member', child: Text('Member')),
                  DropdownMenuItem(
                    value: 'president',
                    child: Text('President'),
                  ),
                  DropdownMenuItem(
                    value: 'secretary',
                    child: Text('Secretary'),
                  ),
                  DropdownMenuItem(
                    value: 'treasurer',
                    child: Text('Treasurer'),
                  ),
                  DropdownMenuItem(
                    value: 'collector',
                    child: Text('Collector'),
                  ),
                  DropdownMenuItem(
                    value: 'superadmin',
                    child: Text('SuperAdmin'),
                  ),
                ],
                onChanged: (v) => setState(() => _role = v),
                decoration: InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.verified_user),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Deceased'),
                value: _isDeceased ?? false,
                onChanged: (v) => setState(() => _isDeceased = v),
                activeThumbColor: Colors.red,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
