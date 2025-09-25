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

class _SecretaryMembersPageState extends State<SecretaryMembersPage>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  String? _infoMsg;

  late TabController _tabController;

  // Raw fetched members (approved + pending) for secretary’s dayungs
  List<Map<String, dynamic>> _all = [];
  List<int> _managedDayungIds = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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

      // Dayung units this secretary manages
      final dayungs = await _sb
          .from('dayung_units')
          .select('id,name')
          .eq('secretary_id', uid);

      final ids = List<Map<String, dynamic>>.from(
        dayungs,
      ).map<int>((e) => e['id'] as int).toList();

      if (ids.isEmpty) {
        setState(() {
          _loading = false;
          _infoMsg = 'You are not assigned to any Dayung.';
          _all = [];
          _managedDayungIds = [];
        });
        return;
      }

      // Fetch users with status approved OR pending in those dayungs
      final data = await _sb
          .from('users')
          .select(
            'id, full_name, email, profile_url, status, dayung_unit_id, dayung:dayung_units!users_dayung_unit_id_fkey(name)',
          )
          .inFilter('dayung_unit_id', ids)
          .inFilter('status', ['approved', 'pending'])
          .order('full_name');

      final list = List<Map<String, dynamic>>.from(data);
      // Deduplicate just in case
      final seen = <String>{};
      final dedup = <Map<String, dynamic>>[];
      for (final m in list) {
        final id = m['id']?.toString();
        if (id != null && seen.add(id)) dedup.add(m);
      }

      setState(() {
        _managedDayungIds = ids;
        _all = dedup;
        _loading = false;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _loading = false;
        _infoMsg = e.message.isEmpty ? 'Load failed (policies?)' : e.message;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _infoMsg = 'Unexpected error loading members';
      });
    }
  }

  List<Map<String, dynamic>> get _approved =>
      _all.where((m) => (m['status'] ?? '').toString() == 'approved').toList();

  List<Map<String, dynamic>> get _pending =>
      _all.where((m) => (m['status'] ?? '').toString() == 'pending').toList();

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() => _load();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Approved (${_approved.length})'),
            Tab(text: 'Pending (${_pending.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_infoMsg != null)
          ? Center(child: Text(_infoMsg!))
          : TabBarView(
              controller: _tabController,
              children: [_memberList(_approved), _memberList(_pending)],
            ),
    );
  }

  Widget _memberList(List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Icon(Icons.people_outline, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Center(child: Text('No members in this status')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final m = list[i];
          final dayung = m['dayung'] as Map<String, dynamic>?;
          final profileUrl = (m['profile_url'] as String?)?.trim();
          final status = (m['status'] ?? '').toString();

          Color chipColor;
          if (status == 'approved') {
            chipColor = Colors.green;
          } else if (status == 'pending') {
            chipColor = Colors.orange;
          } else {
            chipColor = Colors.grey;
          }

          return ListTile(
            leading: CircleAvatar(
              backgroundImage: (profileUrl != null && profileUrl.isNotEmpty)
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
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: chipColor.withOpacity(.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: chipColor),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: chipColor,
                ),
              ),
            ),
            onTap: () {
              // Optional member detail navigation
            },
          );
        },
      ),
    );
  }
}
