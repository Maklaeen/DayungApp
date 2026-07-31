import 'package:capstone_app/shared/collectors_manage_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _kPageBg = Color(0xFFF8FAFC);
const Color _kHeaderGradientStart = Color(0xFF083366);
const Color _kHeaderGradientEnd = Color(0xFF0D47A1);
const Color _kCard = Colors.white;
const Color _kBorder = Color(0xFFE5E7EB);
const Color _kTextSub = Color(0xFF6B7280);

class AssignCollectorsPage extends StatefulWidget {
  final int dayungUnitId;
  const AssignCollectorsPage({super.key, required this.dayungUnitId});

  @override
  State<AssignCollectorsPage> createState() => _AssignCollectorsPageState();
}

class _AssignCollectorsPageState extends State<AssignCollectorsPage> {
  final _sb = Supabase.instance.client;
  String _search = '';
  String _assignmentFilter = 'all';
  List<Map<String, dynamic>> _collectors = [];
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final collectorRows = List<Map<String, dynamic>>.from(
        await _sb
            .from('dayung_collectors')
            .select('collectors_id, user_id')
            .eq('dayung_unit_id', widget.dayungUnitId),
      );

      final collectorUserIds = <String>{};
      for (final row in collectorRows) {
        final collectorId = (row['collectors_id'] ?? '').toString();
        final userId = (row['user_id'] ?? '').toString();
        if (collectorId.isEmpty || userId.isEmpty) continue;
        collectorUserIds.add(userId);
      }

      final collectorUsers = collectorUserIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _sb
                  .from('users')
                  .select('id, full_name, profile_url, mobile_number')
                  .inFilter('id', collectorUserIds.toList()),
            );

      final collectorUserMap = {
        for (final user in collectorUsers) (user['id'] ?? '').toString(): user,
      };

      _collectors = collectorRows
          .map((row) {
            final collectorId = (row['collectors_id'] ?? '').toString();
            final userId = (row['user_id'] ?? '').toString();
            final user = collectorUserMap[userId] ?? <String, dynamic>{};
            final name = (user['full_name'] ?? 'Collector').toString();
            final profileUrl = (user['profile_url'] ?? '').toString();
            final mobileNumber = (user['mobile_number'] ?? '').toString();
            return <String, dynamic>{
              'collectors_id': collectorId,
              'user_id': userId,
              'full_name': name,
              'profile_url': profileUrl,
              'mobile_number': mobileNumber,
            };
          })
          .where((row) => (row['collectors_id'] as String).isNotEmpty)
          .toList();

      final applicationRows = List<Map<String, dynamic>>.from(
        await _sb
            .from('applications')
            .select('user_id, status, assigned_collector')
            .eq('dayung_unit_id', widget.dayungUnitId)
            .eq('status', 'approved'),
      );

      final memberIds = <String>{};
      final assignedCollectorMap = <String, String>{};
      for (final row in applicationRows) {
        final userId = (row['user_id'] ?? '').toString();
        if (userId.isEmpty) continue;
        memberIds.add(userId);
        if (assignedCollectorMap[userId] == null) {
          assignedCollectorMap[userId] = (row['assigned_collector'] ?? '')
              .toString();
        }
      }

      final memberUsers = memberIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _sb
                  .from('users')
                  .select('id, full_name, profile_url')
                  .inFilter('id', memberIds.toList()),
            );

      final memberUserMap = {
        for (final user in memberUsers) (user['id'] ?? '').toString(): user,
      };

      _members = memberIds.map((userId) {
        final user = memberUserMap[userId] ?? <String, dynamic>{};
        return <String, dynamic>{
          'user_id': userId,
          'full_name': (user['full_name'] ?? 'Member').toString(),
          'profile_url': (user['profile_url'] ?? '').toString(),
          'status': 'approved',
          'assigned_collector': assignedCollectorMap[userId] ?? '',
        };
      }).toList();
      _members.sort(
        (a, b) =>
            a['full_name'].toString().compareTo(b['full_name'].toString()),
      );

      if (mounted) {
        setState(() {
          _collectors = _collectors;
          _members = _members;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load assignments: $e')),
        );
      }
    }
  }


  Future<void> _assignCollector(String userId, String? collectorsId) async {
    try {
      final payload = collectorsId == null || collectorsId.isEmpty
          ? {'assigned_collector': null}
          : {'assigned_collector': collectorsId};

      await _sb.from('applications').update(payload).match({
        'dayung_unit_id': widget.dayungUnitId,
        'status': 'approved',
        'user_id': userId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            collectorsId == null
                ? 'Collector unassigned.'
                : 'Member assigned to collector.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to assign collector: $e')),
        );
      }
    }
  }

  void _showCollectorSelection(Map<String, dynamic> member) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        final currentId = (member['assigned_collector'] ?? '').toString();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assign collector for ${member['full_name']}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_collectors.isEmpty)
                      const Text(
                        'No collectors found for this unit. Open Collector Manager to add collectors first.',
                        style: TextStyle(color: Colors.black54),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (currentId.isNotEmpty)
                ListTile(
                  title: const Text('Remove collector assignment'),
                  leading: const Icon(Icons.clear_rounded),
                  selected: currentId.isEmpty,
                  onTap: () {
                    Navigator.pop(context);
                    _assignCollector(member['user_id'] as String, null);
                  },
                ),
              ..._collectors.map((collector) {
                final collectorId = (collector['collectors_id'] ?? '')
                    .toString();
                final name = collector['full_name'] as String;
                return ListTile(
                  title: Text(name),
                  leading: const Icon(Icons.person_rounded),
                  trailing: collectorId == currentId
                      ? const Icon(Icons.check, color: Colors.blue)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _assignCollector(member['user_id'] as String, collectorId);
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  int get _assignedCount => _members
      .where(
        (member) => (member['assigned_collector'] ?? '').toString().isNotEmpty,
      )
      .length;

  int get _unassignedCount => _members
      .where(
        (member) => (member['assigned_collector'] ?? '').toString().isEmpty,
      )
      .length;

  List<Map<String, dynamic>> get _filteredMembers {
    var members = _members;
    if (_assignmentFilter == 'assigned') {
      members = members
          .where(
            (member) =>
                (member['assigned_collector'] ?? '').toString().isNotEmpty,
          )
          .toList();
    } else if (_assignmentFilter == 'unassigned') {
      members = members
          .where(
            (member) => (member['assigned_collector'] ?? '').toString().isEmpty,
          )
          .toList();
    }

    if (_search.isEmpty) return members;
    return members.where((member) {
      final name = (member['full_name'] ?? '').toString().toLowerCase();
      return name.contains(_search.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final assignedCount = _assignedCount;
    final unassignedCount = _unassignedCount;
    final collectorCount = _collectors.length;

    return Scaffold(
      backgroundColor: _kPageBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildPageHeader(context),
            Expanded(
              child: Container(
                color: _kPageBg,
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 18),
                      _buildSummaryRow(assignedCount, unassignedCount, collectorCount),
                      const SizedBox(height: 14),
                      _buildFilterChips(),
                      const SizedBox(height: 12),
                      _buildSearchCard(),
                      const SizedBox(height: 12),
                      _buildInstructionsCard(),
                      const SizedBox(height: 12),
                      if (_filteredMembers.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: _kCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _kBorder),
                          ),
                          child: const Text(
                            'No approved applications found for assignment.',
                            style: TextStyle(color: _kTextSub),
                          ),
                        )
                      else
                        ..._filteredMembers.map(_memberTile),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'assignCollectorsFab',
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  CollectorsManagePage(dayungUnitId: widget.dayungUnitId),
            ),
          );
          _load();
        },
        icon: const Icon(Icons.group_add_rounded),
        label: const Text('Manage Collectors'),
      ),
    );
  }

  Widget _buildPageHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kHeaderGradientStart, _kHeaderGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x22083366),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Assign Collectors',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Manage collector assignments for approved members.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                onPressed: _load,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(int assigned, int unassigned, int collectors) {
    final cardWidth = (MediaQuery.of(context).size.width - 58) / 2;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: cardWidth,
          child: _buildSummaryCard(
            title: 'Assigned',
            value: '$assigned',
            color: const Color(0xFF10B981),
          ),
        ),
        SizedBox(
          width: cardWidth,
          child: _buildSummaryCard(
            title: 'Unassigned',
            value: '$unassigned',
            color: const Color(0xFFF59E0B),
          ),
        ),
        SizedBox(
          width: cardWidth,
          child: _buildSummaryCard(
            title: 'Collectors',
            value: '$collectors',
            color: const Color(0xFF3B82F6),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search members...',
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF64748B),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: const Color(0xFFF6F7FB),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        onChanged: (value) => setState(() => _search = value.trim()),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          _filterChip('All', 'all'),
          _filterChip('Assigned', 'assigned'),
          _filterChip('Unassigned', 'unassigned'),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _assignmentFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _assignmentFilter = value;
        });
      },
      selectedColor: const Color(0xFF0D47A1).withValues(alpha: 0.12),
      backgroundColor: const Color(0xFFF3F4F6),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF0D47A1) : const Color(0xFF374151),
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildInstructionsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Text(
        'Assign each approved application to one of the collectors in this unit.',
        style: TextStyle(color: Colors.black87, height: 1.4),
      ),
    );
  }

  Widget _memberTile(Map<String, dynamic> member) {
    final collectorId = (member['assigned_collector'] ?? '').toString();
    final collectorName = collectorId.isNotEmpty
        ? _collectors
                  .firstWhere(
                    (collector) =>
                        (collector['collectors_id'] ?? '').toString() ==
                        collectorId,
                    orElse: () => <String, dynamic>{},
                  )['full_name']
                  ?.toString() ??
              'Collector'
        : 'Unassigned';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        onTap: () => _showCollectorSelection(member),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundImage: (member['profile_url'] ?? '').toString().isNotEmpty
              ? NetworkImage(member['profile_url'] as String)
              : null,
          backgroundColor: const Color(0xFF0D47A1).withValues(alpha: 0.12),
          child: (member['profile_url'] ?? '').toString().isEmpty
              ? Text(
                  member['full_name']?.toString().isNotEmpty == true
                      ? member['full_name'][0].toUpperCase()
                      : 'M',
                  style: const TextStyle(
                    color: Color(0xFF0D47A1),
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        title: Text(
          member['full_name']?.toString() ?? 'Member',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Status: ${member['status']}',
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 2),
            Text(
              'Collector: $collectorName',
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: () => _showCollectorSelection(member),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D47A1),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Assign'),
        ),
      ),
    );
  }

}
