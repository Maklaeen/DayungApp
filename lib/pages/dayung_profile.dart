import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DayungProfilePage extends StatefulWidget {
  // CHANGED: keep the passed unit id
  final int? dayungUnitId;
  const DayungProfilePage({super.key, this.dayungUnitId});

  @override
  State<DayungProfilePage> createState() => _DayungProfilePageState();
}

class _DayungProfilePageState extends State<DayungProfilePage> {
  final supabase = Supabase.instance.client;

  Map<String, dynamic>? dayung;
  List<Map<String, dynamic>> members = [];
  bool _loading = true;
  // ignore: unused_field
  int? _unitId;

  void _setStateSafe(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _setStateSafe(() => _loading = true);

    // 1) Resolve unit id: prop -> prefs
    int? unitId = widget.dayungUnitId;
    _unitId = unitId;

    if (unitId == null) {
      _setStateSafe(() => _loading = false);
      return;
    }

    try {
      // 2) Fetch dayung info
      final d = await supabase
          .from('dayung_units')
          .select('id,name,barangay,city,province,description')
          .eq('id', unitId)
          .maybeSingle();

      // 3) Fetch approved members by applications join (NOT users.dayung_unit_id)
      final m = await supabase
          .from('applications')
          .select('user:users(id, full_name, email, role, profile_url)')
          .eq('dayung_unit_id', unitId)
          .eq('status', 'approved');

      if (!mounted) return;
      _setStateSafe(() {
        dayung = d != null ? Map<String, dynamic>.from(d) : null;
        members = List<Map<String, dynamic>>.from(
          (m as List).map((r) => (r['user'] as Map?) ?? const {}),
        ).where((u) => u.isNotEmpty).toList();
        _loading = false;
      });
    } on PostgrestException catch (_) {
      if (!mounted) return;
      _setStateSafe(() {
        dayung = null;
        members = [];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      _setStateSafe(() {
        dayung = null;
        members = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (dayung == null) {
      return const Scaffold(body: Center(child: Text('No Dayung selected.')));
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
            '${dayung!['barangay'] ?? ''}'
            '${dayung!['city'] != null ? ', ${dayung!['city']}' : ''}'
            '${dayung!['province'] != null ? ', ${dayung!['province']}' : ''}',
            style: const TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          const Text(
            'Members',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          for (final m in members)
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(m['full_name'] ?? 'Member'),
              subtitle: Text(
                '${m['role'] ?? ''}${m['email'] != null ? ' • ${m['email']}' : ''}',
              ),
            ),
        ],
      ),
    );
  }
}
