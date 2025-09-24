import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AssignUserToDayungWidget extends StatefulWidget {
  const AssignUserToDayungWidget({super.key});

  @override
  State<AssignUserToDayungWidget> createState() =>
      _AssignUserToDayungWidgetState();
}

class _AssignUserToDayungWidgetState extends State<AssignUserToDayungWidget> {
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> dayungUnits = [];
  String? selectedUserId;
  int? selectedDayungId;
  String? selectedRole;
  bool _loading = true;

  final List<String> roles = ['member', 'president', 'secretary'];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _loading = true);
    final usersData = await Supabase.instance.client
        .from('users')
        .select('id, full_name, email, role, dayung_unit_id')
        .order('full_name', ascending: true);
    final dayungData = await Supabase.instance.client
        .from('dayung_units')
        .select('id, name')
        .order('name', ascending: true);
    setState(() {
      users = List<Map<String, dynamic>>.from(usersData);
      dayungUnits = List<Map<String, dynamic>>.from(dayungData);
      _loading = false;
    });
  }

  Future<void> _assignUser() async {
    if (selectedUserId == null ||
        selectedDayungId == null ||
        selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select user, dayung, and role.')),
      );
      return;
    }
    await Supabase.instance.client
        .from('users')
        .update({'dayung_unit_id': selectedDayungId, 'role': selectedRole})
        .eq('id', selectedUserId as Object);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('User assigned successfully!')),
    );
    _fetchData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assign User to Dayung')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select User:', style: TextStyle(fontSize: 16)),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: selectedUserId,
                    hint: const Text('Choose user'),
                    items: users.map<DropdownMenuItem<String>>((u) {
                      return DropdownMenuItem<String>(
                        value: u['id'] as String,
                        child: Text('${u['full_name']} (${u['email']})'),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => selectedUserId = val),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Select Dayung Unit:',
                    style: TextStyle(fontSize: 16),
                  ),
                  DropdownButton<int>(
                    isExpanded: true,
                    value: selectedDayungId,
                    hint: const Text('Choose dayung unit'),
                    items: dayungUnits.map<DropdownMenuItem<int>>((d) {
                      return DropdownMenuItem<int>(
                        value: d['id'] as int,
                        child: Text(d['name']),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => selectedDayungId = val),
                  ),
                  const SizedBox(height: 24),
                  const Text('Select Role:', style: TextStyle(fontSize: 16)),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: selectedRole,
                    hint: const Text('Choose role'),
                    items: roles.map((r) {
                      return DropdownMenuItem(
                        value: r,
                        child: Text(r[0].toUpperCase() + r.substring(1)),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => selectedRole = val),
                  ),
                  const SizedBox(height: 32),
                  Center(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('Assign'),
                      onPressed: _assignUser,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
