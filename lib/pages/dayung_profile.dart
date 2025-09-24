import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DayungProfilePage extends StatefulWidget {
  const DayungProfilePage({super.key, required int dayungUnitId});

  @override
  State<DayungProfilePage> createState() => _DayungProfilePageState();
}

class _DayungProfilePageState extends State<DayungProfilePage> {
  Map<String, dynamic>? dayung;
  List<Map<String, dynamic>> members = [];
  bool _loading = true;
  int? dayungUnitId;

  @override
  void initState() {
    super.initState();
    _fetchUserDayungAndProfile();
  }

  Future<void> _fetchUserDayungAndProfile() async {
    setState(() => _loading = true);
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        dayung = null;
      });
      return;
    }
    // Fetch the user's assigned dayung_unit_id
    final userData = await supabase
        .from('users')
        .select('dayung_unit_id')
        .eq('id', user.id)
        .single();

    dayungUnitId = userData['dayung_unit_id'];
    if (dayungUnitId == null) {
      setState(() {
        _loading = false;
        dayung = null;
      });
      return;
    }
    // Fetch dayung info
    final d = await supabase
        .from('dayung_units')
        .select()
        .eq('id', dayungUnitId as Object)
        .single();
    // Fetch users assigned to this dayung unit
    final m = await supabase
        .from('users')
        .select('id, full_name, email, role')
        .eq('dayung_unit_id', dayungUnitId as Object);
    setState(() {
      dayung = d;
      members = List<Map<String, dynamic>>.from(m);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (dayung == null) {
      return const Scaffold(
        body: Center(
          child: Text('No dayung assigned to your account.'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(dayung!['name'] ?? 'Dayung Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            dayung!['name'] ?? '',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(
            '${dayung!['barangay'] ?? ''}${dayung!['city'] != null ? ', ${dayung!['city']}' : ''}${dayung!['province'] != null ? ', ${dayung!['province']}' : ''}',
            style: const TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          const Text(
            'Members:',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          ...members.map(
            (m) => ListTile(
              leading: const Icon(Icons.person),
              title: Text(m['full_name'] ?? ''),
              subtitle: Text('${m['role'] ?? ''} • ${m['email'] ?? ''}'),
            ),
          ),
        ],
      ),
    );
  }
}