import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kPrimary = Color(0xFF1E40AF);
const kCardBg = Color(0xFFFFFFFF);
const kSubText = Color(0xFF6B7280);

class SuperAdminAdminsPage extends StatefulWidget {
  const SuperAdminAdminsPage({super.key});

  @override
  State<SuperAdminAdminsPage> createState() => _SuperAdminAdminsPageState();
}

class _SuperAdminAdminsPageState extends State<SuperAdminAdminsPage> {
  late Future<List<Map<String, dynamic>>> _unitsFuture;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _unitsFuture = _fetchUnitsWithAdminsAndCollectors();
  }

  Future<List<Map<String, dynamic>>>
  _fetchUnitsWithAdminsAndCollectors() async {
    final sb = Supabase.instance.client;

    final units = await sb
        .from('dayung_units')
        .select(
          'id, name, barangay, city, province, '
          'president_id, secretary_id, treasurer_id, '
          'president:president_id(full_name, email), '
          'secretary:secretary_id(full_name, email), '
          'treasurer:treasurer_id(full_name, email)',
        );

    final collectorsRes = await sb
        .from('dayung_collectors')
        .select('dayung_unit_id, user_id, user:user_id(full_name, email)');

    // Always convert each collector to Map<String, dynamic> and user to Map<String, dynamic>
    final Map<String, List<Map<String, dynamic>>> collectorsByUnit = {};
    for (final c in collectorsRes) {
      final unitId = c['dayung_unit_id']?.toString();
      final user = c['user'];
      if (unitId != null && user != null) {
        collectorsByUnit.putIfAbsent(unitId, () => []);
        collectorsByUnit[unitId]!.add(Map<String, dynamic>.from(user as Map));
      }
    }

    // Attach admins and collectors to each unit
    for (final unit in units) {
      unit['admins'] = [
        if (unit['president_id'] != null && unit['president'] != null)
          {
            'role': 'President',
            ...Map<String, dynamic>.from(unit['president'] as Map),
          },
        if (unit['secretary_id'] != null && unit['secretary'] != null)
          {
            'role': 'Secretary',
            ...Map<String, dynamic>.from(unit['secretary'] as Map),
          },
        if (unit['treasurer_id'] != null && unit['treasurer'] != null)
          {
            'role': 'Treasurer',
            ...Map<String, dynamic>.from(unit['treasurer'] as Map),
          },
      ];
      unit['collectors'] = (collectorsByUnit[unit['id']?.toString()] ?? [])
          .map((c) => Map<String, dynamic>.from(c as Map))
          .toList();
    }

    return List<Map<String, dynamic>>.from(units);
  }

  void _editAdmin(Map<String, dynamic> admin) {
    showDialog(
      context: context,
      builder: (context) => _EditAdminDialog(admin: admin),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeBg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF18181B)
        : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: themeBg,
      appBar: AppBar(
        title: const Text('Manage Admins'),
        backgroundColor: kPrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search by unit, admin, or collector...',
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
                future: _unitsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('No dayung units found.'));
                  }
                  final units = snapshot.data!
                      .where(
                        (unit) =>
                            (unit['name'] ?? '')
                                .toString()
                                .toLowerCase()
                                .contains(_search) ||
                            (unit['admins'] as List).any(
                              (a) => (a['full_name'] ?? '')
                                  .toString()
                                  .toLowerCase()
                                  .contains(_search),
                            ) ||
                            (unit['collectors'] as List).any(
                              (c) => (c['full_name'] ?? '')
                                  .toString()
                                  .toLowerCase()
                                  .contains(_search),
                            ),
                      )
                      .toList();

                  if (units.isEmpty) {
                    return const Center(
                      child: Text('No units match your search.'),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    separatorBuilder: (_, __) => const SizedBox(height: 24),
                    itemCount: units.length,
                    itemBuilder: (context, i) {
                      final unit = units[i];
                      final admins = unit['admins'] as List;
                      final collectors = unit['collectors'] as List;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            unit['name'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: kPrimary,
                              fontFamily: 'Montserrat',
                            ),
                          ),
                          if (unit['barangay'] != null)
                            Text(
                              'Barangay: ${unit['barangay']}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: kSubText,
                              ),
                            ),
                          if (unit['city'] != null)
                            Text(
                              'City: ${unit['city']}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: kSubText,
                              ),
                            ),
                          if (unit['province'] != null)
                            Text(
                              'Province: ${unit['province']}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: kSubText,
                              ),
                            ),
                          const SizedBox(height: 10),
                          if (admins.isNotEmpty)
                            const Text(
                              'Admins',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: kPrimary,
                              ),
                            ),
                          ...admins.map(
                            (admin) => Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Material(
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
                                    child: const Icon(
                                      Icons.person,
                                      color: kPrimary,
                                    ),
                                  ),
                                  title: Text(
                                    admin['full_name'] ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    admin['role'] ?? '',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.edit,
                                      color: kPrimary,
                                    ),
                                    onPressed: () => _editAdmin(admin),
                                    tooltip: 'Edit Admin',
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (collectors.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const Text(
                              'Collectors',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: kPrimary,
                              ),
                            ),
                            ...collectors.map((collector) {
                              final c = Map<String, dynamic>.from(collector);
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Material(
                                  color: kCardBg,
                                  borderRadius: BorderRadius.circular(16),
                                  elevation: 1,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: kPrimary.withOpacity(
                                        0.1,
                                      ),
                                      child: const Icon(
                                        Icons.person,
                                        color: kPrimary,
                                      ),
                                    ),
                                    title: Text(
                                      c['full_name'] ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: const Text(
                                      'Collector',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.edit,
                                        color: kPrimary,
                                      ),
                                      onPressed: () => _editAdmin({
                                        'role': 'Collector',
                                        ...c,
                                      }),
                                      tooltip: 'Edit Collector',
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ],
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

class _EditAdminDialog extends StatefulWidget {
  final Map<String, dynamic> admin;
  const _EditAdminDialog({required this.admin});

  @override
  State<_EditAdminDialog> createState() => _EditAdminDialogState();
}

class _EditAdminDialogState extends State<_EditAdminDialog> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  String? _role;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.admin['full_name'] ?? '',
    );
    _emailController = TextEditingController(text: widget.admin['email'] ?? '');
    _role = widget.admin['role'] ?? 'President';
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
                'Edit Admin',
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
                readOnly: true,
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
                readOnly: true,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _role,
                items: const [
                  DropdownMenuItem(
                    value: 'President',
                    child: Text('President'),
                  ),
                  DropdownMenuItem(
                    value: 'Secretary',
                    child: Text('Secretary'),
                  ),
                  DropdownMenuItem(
                    value: 'Treasurer',
                    child: Text('Treasurer'),
                  ),
                  DropdownMenuItem(
                    value: 'Collector',
                    child: Text('Collector'),
                  ),
                ],
                onChanged: null,
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
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
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
