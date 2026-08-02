import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _kPrimary = Color(0xFF0D47A1);
const Color _kPrimaryDark = Color(0xFF083366);
const Color _kNeutralText = Color(0xFF1F2937);
const Color _kSubText = Color(0xFF4B5563);
const Color _kDanger = Color(0xFFEF4444);
const Color _kSuccess = Color(0xFF10B981);

class CollectorsManagePage extends StatefulWidget {
  final int dayungUnitId;
  const CollectorsManagePage({super.key, required this.dayungUnitId});

  @override
  State<CollectorsManagePage> createState() => _CollectorsManagePageState();
}

class _CollectorsManagePageState extends State<CollectorsManagePage> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _collectors = [];
  List<Map<String, dynamic>> _activeMembers = [];
  Set<String> _collectorUserIds = {};
  Map<String, String> _collectorIdByUser = {};
  Map<String, String> _collectorNameById = {};
  Map<String, int> _assignedCounts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Load collector rows and map collectors_id values.
      final colRows = await _sb
          .from('dayung_collectors')
          .select('collectors_id, user_id')
          .eq('dayung_unit_id', widget.dayungUnitId);

      final collectorUserIds = <String>{};
      final collectorIdByUser = <String, String>{};
      for (final row in List<Map<String, dynamic>>.from(colRows)) {
        final userId = (row['user_id'] ?? '').toString();
        if (userId.isEmpty) continue;
        final collectorId = (row['collectors_id'] ?? row['user_id'] ?? '').toString();
        collectorUserIds.add(userId);
        collectorIdByUser[userId] = collectorId;
      }

      // Load collector user details
      List<Map<String, dynamic>> collectors = [];
      final collectorNamesById = <String, String>{};
      if (collectorUserIds.isNotEmpty) {
        final users = await _sb
            .from('users')
            .select('id, full_name, profile_url, mobile_number')
            .inFilter('id', collectorUserIds.toList());
        final userRows = List<Map<String, dynamic>>.from(users);
        collectors = userRows.map((user) {
          final userId = (user['id'] ?? '').toString();
          final collectorId = collectorIdByUser[userId] ?? userId;
          collectorNamesById[collectorId] = (user['full_name'] ?? 'Collector').toString();
          return {
            'id': userId,
            'collectors_id': collectorId,
            'full_name': (user['full_name'] ?? 'Collector').toString(),
            'profile_url': (user['profile_url'] ?? '').toString(),
            'mobile_number': (user['mobile_number'] ?? '').toString(),
          };
        }).toList();
      }

      // Load active members (approved, not deceased) and current assignment.
      final apps = await _sb
          .from('applications')
          .select('user_id, assigned_collector, user:users(id, full_name, profile_url, is_deceased)')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'approved');

      final memberMap = <String, Map<String, dynamic>>{};
      for (final r in List<Map<String, dynamic>>.from(apps)) {
        final u = r['user'] as Map?;
        if (u == null) continue;
        if (u['is_deceased'] == true) continue;
        final userId = (u['id'] ?? '').toString();
        if (userId.isEmpty) continue;
        final assignedCollector = (r['assigned_collector'] ?? '').toString();
        final member = {
          'id': userId,
          'full_name': (u['full_name'] ?? '').toString(),
          'profile_url': (u['profile_url'] ?? '').toString(),
          'assigned_collector': assignedCollector,
        };

        if (!memberMap.containsKey(userId) ||
            (memberMap[userId]!['assigned_collector'] as String).isEmpty && assignedCollector.isNotEmpty) {
          memberMap[userId] = member;
        }
      }

      final members = memberMap.values.toList();
      members.sort(
        (a, b) => (a['full_name'] as String).compareTo(b['full_name'] as String),
      );

      final assignedCounts = <String, int>{};
      for (final member in members) {
        final assignedCollector = (member['assigned_collector'] ?? '').toString();
        if (assignedCollector.isNotEmpty) {
          assignedCounts[assignedCollector] = (assignedCounts[assignedCollector] ?? 0) + 1;
        }
      }

      if (mounted) {
        setState(() {
          _collectorUserIds = collectorUserIds;
          _collectorIdByUser = collectorIdByUser;
          _collectorNameById = collectorNamesById;
          _collectors = collectors;
          _activeMembers = members;
          _assignedCounts = assignedCounts;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addCollector(String userId) async {
    try {
      // Attempt to compute a new integer primary key for collectors_id.
      // Note: this is a simple max+1 approach and may not be safe under high concurrency.
      int newCollectorsId = 1;
      try {
        final res = await _sb
            .from('dayung_collectors')
            .select('collectors_id')
            .order('collectors_id', ascending: false)
            .limit(1);
        final rows = List<Map<String, dynamic>>.from(res ?? []);
        if (rows.isNotEmpty) {
          final v = rows[0]['collectors_id'];
          if (v is int) {
            newCollectorsId = v + 1;
          } else if (v is String) {
            final parsed = int.tryParse(v);
            if (parsed != null) newCollectorsId = parsed + 1;
          }
        }
      } catch (_) {
        // ignore and fall back to default 1
      }

      await _sb.from('dayung_collectors').insert({
        'collectors_id': newCollectorsId,
        'dayung_unit_id': widget.dayungUnitId,
        'user_id': userId,
        'added_by': _sb.auth.currentUser?.id,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Collector added.')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _removeCollector(String userId) async {
    try {
      await _sb.from('dayung_collectors').delete().match({
        'dayung_unit_id': widget.dayungUnitId,
        'user_id': userId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Collector removed.')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  void _showAddCollectorSheet() {
    final nonCollectors = _activeMembers
        .where((m) => !_collectorUserIds.contains(m['id']))
        .toList();
    String search = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final filtered = search.isEmpty
              ? nonCollectors
              : nonCollectors.where((m) {
                  return (m['full_name'] as String)
                      .toLowerCase()
                      .contains(search.toLowerCase());
                }).toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Assign Collector',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: _kPrimaryDark,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search active member...',
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: _kPrimary,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                        onChanged: (v) => setSheet(() => search = v.trim()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'No available members',
                            style: TextStyle(color: _kSubText),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final m = filtered[i];
                            final profileUrl = m['profile_url'] as String;
                            final name = m['full_name'] as String;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: profileUrl.isNotEmpty
                                    ? NetworkImage(profileUrl)
                                    : null,
                                backgroundColor: _kPrimary.withValues(
                                  alpha: 0.1,
                                ),
                                child: profileUrl.isEmpty
                                    ? Text(
                                        name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : 'M',
                                        style: const TextStyle(
                                          color: _kPrimary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                                trailing: ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _confirmAndAddCollector(m['id'] as String, name);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kPrimary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Assign',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(8, 36, 20, 28),
              decoration: const BoxDecoration(
                color: _kPrimaryDark,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF1E40AF),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.badge_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Assign Collectors',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_collectors.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Assigned collectors section
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _kPrimary),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Assigned collectors
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: _kPrimary.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.badge_rounded,
                                        color: _kPrimary,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Assigned Collectors',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: _kNeutralText,
                                        fontFamily: 'Montserrat',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                if (_collectors.isEmpty)
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'No collectors assigned yet',
                                        style: TextStyle(
                                          color: _kSubText,
                                          fontFamily: 'OpenSans',
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  ..._collectors.map(
                                    (c) => _collectorTile(c),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Active members section
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: _kSuccess.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.groups_rounded,
                                        color: _kSuccess,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Active Members (${_activeMembers.length})',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: _kNeutralText,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Showing approved members for this dayung unit. Tap a member to assign or change their collector.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _kSubText,
                                    fontFamily: 'OpenSans',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ..._activeMembers.map(
                                  (m) => _activeMemberTile(m),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCollectorSheet,
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text(
          'Assign Collector',
          style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Montserrat'),
        ),
      ),
    );
  }

  Widget _collectorTile(Map<String, dynamic> c) {
    final name = (c['full_name'] ?? 'Collector').toString();
    final profileUrl = (c['profile_url'] ?? '').toString();
    final userId = (c['id'] ?? '').toString();
    final phone = (c['mobile_number'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kPrimary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: profileUrl.isNotEmpty
                ? NetworkImage(profileUrl)
                : null,
            backgroundColor: _kPrimary.withValues(alpha: 0.15),
            child: profileUrl.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'C',
                    style: const TextStyle(
                      color: _kPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: _kNeutralText,
                    fontFamily: 'Montserrat',
                  ),
                ),
                Text(
                  'Members: ${_assignedCounts[userId] ?? 0}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _kSubText,
                    fontFamily: 'OpenSans',
                  ),
                ),
                if (phone.isNotEmpty)
                  Text(
                    phone,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _kSubText,
                      fontFamily: 'OpenSans',
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_rounded, color: _kDanger),
            tooltip: 'Remove collector',
            onPressed: () => _showRemoveConfirm(userId, name),
          ),
        ],
      ),
    );
  }

  Widget _activeMemberTile(Map<String, dynamic> m) {
    final name = (m['full_name'] ?? 'Member').toString();
    final profileUrl = (m['profile_url'] ?? '').toString();
    final userId = (m['id'] ?? '').toString();
    final assignedCollectorId = (m['assigned_collector'] ?? '').toString();
    final assignedCollectorLabel = assignedCollectorId.isNotEmpty
        ? _collectorNameById[assignedCollectorId] ?? 'Assigned collector'
        : 'No collector assigned';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        leading: CircleAvatar(
          radius: 18,
          backgroundImage: profileUrl.isNotEmpty
              ? NetworkImage(profileUrl)
              : null,
          backgroundColor: _kSuccess.withValues(alpha: 0.1),
          child: profileUrl.isEmpty
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'M',
                  style: const TextStyle(
                    color: _kSuccess,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                )
              : null,
        ),
        title: Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: _kNeutralText,
            fontFamily: 'Montserrat',
          ),
        ),
        subtitle: Text(
          assignedCollectorLabel,
          style: const TextStyle(
            fontSize: 12,
            color: _kSubText,
            fontFamily: 'OpenSans',
          ),
        ),
        trailing: TextButton(
          onPressed: () => _showAssignMemberSheet(m),
          style: TextButton.styleFrom(
            foregroundColor: _kPrimary,
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
          ),
          child: const Text(
            'Assign',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              fontFamily: 'Montserrat',
            ),
          ),
        ),
      ),
    );
  }

  void _confirmAndAddCollector(String userId, String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Assign Collector',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontFamily: 'Montserrat',
          ),
        ),
        content: Text(
          'Assign $name as a collector?',
          style: const TextStyle(fontFamily: 'OpenSans'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _addCollector(userId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Assign',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _showAssignMemberSheet(Map<String, dynamic> member) {
    final memberName = (member['full_name'] ?? 'Member').toString();
    final currentCollectorId = (member['assigned_collector'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Assign collector for $memberName',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _kPrimaryDark,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose which collector should be responsible for this approved member.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: _kSubText,
                      fontFamily: 'OpenSans',
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Expanded(
              child: _collectors.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'No collectors are assigned yet. Add a collector first to assign this member.',
                          style: const TextStyle(color: _kSubText),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _collectors.length + 1,
                      itemBuilder: (_, index) {
                        if (index == 0) {
                          return ListTile(
                            title: const Text('Unassign collector'),
                            subtitle: const Text('Leave this member without an assigned collector.'),
                            leading: const Icon(Icons.clear, color: _kDanger),
                            selected: currentCollectorId.isEmpty,
                            onTap: () {
                              Navigator.pop(context);
                              _assignMemberToCollector(member['id'] as String, '');
                            },
                          );
                        }
                        final collector = _collectors[index - 1];
                        final collectorId = (collector['collectors_id'] ?? '').toString();
                        final collectorName = (collector['full_name'] ?? 'Collector').toString();
                        return ListTile(
                          title: Text(collectorName),
                          subtitle: Text('Collector for this unit'),
                          leading: const Icon(Icons.badge_rounded, color: _kPrimary),
                          trailing: currentCollectorId == collectorId
                              ? const Icon(Icons.check_circle, color: _kSuccess)
                              : null,
                          onTap: () {
                            Navigator.pop(context);
                            _assignMemberToCollector(member['id'] as String, collectorId);
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

  Future<void> _assignMemberToCollector(String userId, String collectorsId) async {
    try {
      final payload = collectorsId.isEmpty ? {'assigned_collector': null} : {'assigned_collector': collectorsId};
      await _sb.from('applications').update(payload).match({
            'user_id': userId,
            'dayung_unit_id': widget.dayungUnitId,
          });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              collectorsId.isEmpty
                  ? 'Collector assignment removed for the member.'
                  : 'Member assigned to collector successfully.',
            ),
          ),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update assignment: $e')),
        );
      }
    }
  }

  void _showRemoveConfirm(String userId, String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Remove Collector',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontFamily: 'Montserrat',
          ),
        ),
        content: Text(
          'Remove $name as a collector?',
          style: const TextStyle(fontFamily: 'OpenSans'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _removeCollector(userId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kDanger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Remove',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
