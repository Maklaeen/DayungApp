import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecretaryMembersPage extends StatefulWidget {
  const SecretaryMembersPage({super.key});

  @override
  State<SecretaryMembersPage> createState() => _SecretaryMembersPageState();
}

String _initialOf(dynamic name) {
  if (name is String) {
    final t = name.trim();
    if (t.isNotEmpty) return t.substring(0, 1).toUpperCase();
  }
  return 'M';
}

class _SecretaryMembersPageState extends State<SecretaryMembersPage> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _infoMsg;
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _infoMsg = null;
    });
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) {
        setState(() {
          _loading = false;
          _infoMsg = 'Please log in.';
        });
        return;
      }

      // 1) Which dayungs does this secretary manage?
      final dayungs = await _sb
          .from('dayung_units')
          .select('id, name')
          .eq('secretary_id', uid);

      final ids = List<Map<String, dynamic>>.from(
        dayungs,
      ).map<int>((e) => e['id'] as int).toList();

      if (ids.isEmpty) {
        setState(() {
          _loading = false;
          _infoMsg = 'You are not assigned as secretary to any Dayung.';
          _members = [];
        });
        return;
      }

      // 2) Fetch members of those dayungs
      final data = await _sb
          .from('users')
          .select(
            'id, full_name, email, profile_url, dayung_unit_id, dayung:dayung_units!users_dayung_unit_id_fkey(name)',
          )
          .inFilter('dayung_unit_id', ids)
          .order('full_name', ascending: true);

      // 3) Optionally include the secretary themselves if not in list
      final me = await _sb
          .from('users')
          .select(
            'id, full_name, email, profile_url, dayung_unit_id, dayung:dayung_units!users_dayung_unit_id_fkey(name)',
          )
          .eq('id', uid)
          .maybeSingle();

      final list = List<Map<String, dynamic>>.from(data);
      if (me != null &&
          me is Map &&
          me['dayung_unit_id'] != null &&
          ids.contains(me['dayung_unit_id']) &&
          !list.any((m) => m['id'] == me['id'])) {
        list.add(Map<String, dynamic>.from(me as Map));
      }

      // Deduplicate by id just in case
      final seen = <String>{};
      final dedup = <Map<String, dynamic>>[];
      for (final m in list) {
        final id = m['id']?.toString();
        if (id != null && seen.add(id)) dedup.add(m);
      }

      setState(() {
        _members = dedup;
        _loading = false;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _loading = false;
        _infoMsg = e.message.isEmpty ? 'Load failed (RLS/Policy?)' : e.message;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _infoMsg = 'Unexpected error loading members';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Members')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_infoMsg != null)
          ? Center(child: Text(_infoMsg!))
          : _members.isEmpty
          ? const Center(child: Text('No members found'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: _members.length,
                itemBuilder: (_, i) {
                  final m = _members[i];
                  final dayung = m['dayung'] as Map<String, dynamic>?;
                  final profileUrl = (m['profile_url'] as String?)?.trim();

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage:
                          (profileUrl != null && profileUrl.isNotEmpty)
                          ? NetworkImage(profileUrl)
                          : null,
                      child: (profileUrl == null || profileUrl.isEmpty)
                          ? Text(_initialOf(m['full_name']))
                          : null,
                    ),
                    title: Text(
                      (m['full_name'] as String?)?.trim().isNotEmpty == true
                          ? (m['full_name'] as String).trim()
                          : 'Member',
                    ),
                    subtitle: Text(dayung?['name'] ?? 'Dayung'),
                  );
                },
              ),
            ),
    );
  }
}
