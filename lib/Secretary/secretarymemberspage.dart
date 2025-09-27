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
  List<Map<String, dynamic>> _rows = [];
  final Map<int, String> _dayungNames = {};
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
          _rows = [];
          _managedDayungIds = [];
          _dayungNames.clear();
        });
        return;
      }

      // 1) Dayungs this secretary manages
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
          _rows = [];
          _managedDayungIds = [];
          _dayungNames.clear();
        });
        return;
      }

      _dayungNames
        ..clear()
        ..addEntries(
          List<Map<String, dynamic>>.from(dayungs).map(
            (e) => MapEntry(e['id'] as int, (e['name'] ?? 'Dayung') as String),
          ),
        );

      // Fetch users with status approved OR pending in those dayungs
      final apps = await _sb
          .from('applications')
          .select(
            'user_id, status, dayung_unit_id, approved_at, user:users(id, full_name, email, profile_url)',
          )
          .inFilter('dayung_unit_id', ids)
          .inFilter('status', ['approved', 'pending'])
          .order('approved_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(apps);

      // Optional: dedupe multiple applications for same user-dayung by latest approved_at
      final byKey = <String, Map<String, dynamic>>{};
      for (final r in list) {
        final u = r['user'] as Map<String, dynamic>?;
        final userId = (u?['id'] ?? r['user_id']).toString();
        final dayungId = r['dayung_unit_id'] as int;
        final key = '$userId-$dayungId';
        if (!byKey.containsKey(key)) {
          byKey[key] = r;
        } else {
          final prev = byKey[key]!;
          final prevAt = prev['approved_at']?.toString();
          final currAt = r['approved_at']?.toString();
          if (currAt != null &&
              (prevAt == null ||
                  DateTime.tryParse(
                        currAt,
                      )?.isAfter(DateTime.tryParse(prevAt) ?? DateTime(0)) ==
                      true)) {
            byKey[key] = r;
          }
        }
      }

      setState(() {
        _managedDayungIds = ids;
        _rows = byKey.values.toList()
          ..sort((a, b) {
            // Sort: approved first, then by approved_at desc
            final sa = (a['status'] ?? '').toString();
            final sb = (b['status'] ?? '').toString();
            if (sa != sb) {
              return sa == 'approved' ? -1 : 1;
            }
            final ta = DateTime.tryParse(a['approved_at']?.toString() ?? '');
            final tb = DateTime.tryParse(b['approved_at']?.toString() ?? '');
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });
        _loading = false;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _loading = false;
        _infoMsg = e.message.isEmpty ? 'Load failed (policies?)' : e.message;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _infoMsg = 'Unexpected error loading members';
      });
    }
  }

  List<Map<String, dynamic>> get _approved =>
      _rows.where((r) => (r['status'] ?? '').toString() == 'approved').toList();

  List<Map<String, dynamic>> get _pending =>
      _rows.where((r) => (r['status'] ?? '').toString() == 'pending').toList();

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

  String _initialOf(dynamic name) {
    if (name is String) {
      final t = name.trim();
      if (t.isNotEmpty) return t.substring(0, 1).toUpperCase();
    }
    return 'M';
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
          final r = list[i];
          final u = r['user'] as Map<String, dynamic>?;
          final profileUrl = (u?['profile_url'] as String?)?.trim();
          final status = (r['status'] ?? '').toString();
          final dayungId = r['dayung_unit_id'] as int?;
          final dayungName = dayungId != null
              ? (_dayungNames[dayungId] ?? 'Dayung')
              : 'Dayung';

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
                  ? Text(_initialOf(u?['full_name']))
                  : null,
            ),
            title: Text(
              (u?['full_name'] as String?)?.trim().isNotEmpty == true
                  ? (u?['full_name'] as String).trim()
                  : 'Member',
            ),
            subtitle: Text(dayungName),
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
              // Optional member detail
            },
          );
        },
      ),
    );
  }
}
