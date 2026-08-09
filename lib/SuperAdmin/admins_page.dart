import 'package:capstone_app/SuperAdmin/superadmin_support.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kPrimary = Color(0xFF1E40AF);
const kCardBg = Color(0xFFFFFFFF);
const kSubText = Color(0xFF6B7280);
const kDanger = Color(0xFFDC2626);
const kSuccess = Color(0xFF059669);

class SuperAdminAdminsPage extends StatefulWidget {
  const SuperAdminAdminsPage({super.key});

  @override
  State<SuperAdminAdminsPage> createState() => _SuperAdminAdminsPageState();
}

class _SuperAdminAdminsPageState extends State<SuperAdminAdminsPage> {
  late Future<_AdminScreenData> _dataFuture;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _dataFuture = _fetchData();
  }

  Future<_AdminScreenData> _fetchData() async {
    final sb = Supabase.instance.client;

    final units = await sb
        .from('dayung_units')
        .select(
          'id, name, barangay, city, province, '
          'president_id, secretary_id, treasurer_id, '
          'president:president_id(id, full_name, email), '
          'secretary:secretary_id(id, full_name, email), '
          'treasurer:treasurer_id(id, full_name, email)',
        )
        .order('name');

    final collectorsRes = await sb
        .from('dayung_collectors')
        .select('dayung_unit_id, user_id, user:user_id(id, full_name, email)');

    final approvedApplications = List<Map<String, dynamic>>.from(
      await sb
          .from('applications')
          .select('dayung_unit_id, user_id')
          .eq('status', 'approved'),
    );

    final approvedUserIds = approvedApplications
        .map((app) => app['user_id']?.toString())
        .whereType<String>()
        .toSet();

    final approvedUsersById = <String, Map<String, dynamic>>{};
    if (approvedUserIds.isNotEmpty) {
      final approvedUsers = List<Map<String, dynamic>>.from(
        await sb
            .from('users')
            .select('id, full_name, email, role, is_deceased')
            .filter('id', 'in', approvedUserIds.toList()),
      );
      for (final user in approvedUsers) {
        final id = user['id']?.toString();
        if (id != null) {
          approvedUsersById[id] = Map<String, dynamic>.from(user);
        }
      }
    }

    final users = await sb
        .from('users')
        .select('id, full_name, email, role, is_deceased')
        .eq('is_deceased', false)
        .order('full_name');

    final selectableUsers = List<Map<String, dynamic>>.from(
      users,
    ).where((user) => (user['role'] ?? '').toString() != 'superadmin').toList();

    final collectorsByUnit = <String, List<Map<String, dynamic>>>{};
    for (final collector in collectorsRes) {
      final unitId = collector['dayung_unit_id']?.toString();
      final user = collector['user'];
      if (unitId == null || user == null) continue;
      collectorsByUnit.putIfAbsent(unitId, () => []);
      collectorsByUnit[unitId]!.add(Map<String, dynamic>.from(user as Map));
    }

    final applicantsByUnit = <String, List<Map<String, dynamic>>>{};
    for (final app in approvedApplications) {
      final unitId = app['dayung_unit_id']?.toString();
      final userId = app['user_id']?.toString();
      if (unitId == null || userId == null) continue;
      final userMap = approvedUsersById[userId];
      if (userMap == null) continue;
      if (userMap['is_deceased'] == true) continue;
      applicantsByUnit.putIfAbsent(unitId, () => []);
      if (!applicantsByUnit[unitId]!.any((u) => u['id'] == userMap['id'])) {
        applicantsByUnit[unitId]!.add(userMap);
      }
    }

    final normalizedUnits = List<Map<String, dynamic>>.from(units).map((unit) {
      unit['collectors'] = collectorsByUnit[unit['id']?.toString()] ?? [];
      return unit;
    }).toList();

    return _AdminScreenData(
      units: normalizedUnits,
      users: selectableUsers,
      applicantsByUnit: applicantsByUnit,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _dataFuture = _fetchData();
    });
  }

  Future<void> _assignRole({
    required Map<String, dynamic> unit,
    required String role,
    required Map<String, dynamic> user,
  }) async {
    final ok = await _postAction('/superadmin/assign-unit-role', {
      'dayung_unit_id': unit['id'],
      'role': role,
      'user_id': user['id'],
    });
    if (ok) await _refresh();
  }

  Future<void> _removeRole({
    required Map<String, dynamic> unit,
    required String role,
    String? userId,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Remove ${_labelForRole(role)}'),
        content: Text(
          'Do you want to remove the ${_labelForRole(role).toLowerCase()} assignment from ${unit['name']}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kDanger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final payload = <String, dynamic>{
      'dayung_unit_id': unit['id'],
      'role': role,
    };
    if (userId != null) {
      payload['user_id'] = userId;
    }

    final ok = await _postAction('/superadmin/remove-unit-role', payload);
    if (ok) await _refresh();
  }

  Future<bool> _postAction(
    String path,
    Map<String, dynamic> payload, {
    String? successMessage,
  }) async {
    try {
      await superAdminPostJson(path, payload);
      if (successMessage != null && successMessage.isNotEmpty) {
        _showSnack(successMessage);
      }
      return true;
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '').trim();
      if (message.isNotEmpty) {
        _showSnack(message);
      }
      return false;
    }
  }

  Future<Map<String, dynamic>?> _pickUser(
    String title,
    List<Map<String, dynamic>> users,
  ) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _SelectUserDialog(title: title, users: users),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _labelForRole(String role) {
    switch (role) {
      case 'president':
        return 'President';
      case 'secretary':
        return 'Secretary';
      case 'treasurer':
        return 'Treasurer';
      case 'collector':
        return 'Collector';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeBg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF18181B)
        : const Color(0xFFF8FAFC);

    return SuperAdminAccessGuard(
      title: 'Manage Admins',
      child: Scaffold(
        backgroundColor: themeBg,
        body: SafeArea(
          child: Column(
            children: [
              _AdminsHero(
                searchValue: _search,
                onSearchChanged: (value) =>
                    setState(() => _search = value.trim().toLowerCase()),
              ),
              Expanded(
                child: FutureBuilder<_AdminScreenData>(
                  future: _dataFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError || !snapshot.hasData) {
                      return _AdminsEmptyState(
                        title: 'Unable to load unit roles',
                        message:
                            snapshot.error?.toString() ?? 'Please try again.',
                        icon: Icons.error_outline_rounded,
                        actionLabel: 'Try Again',
                        onAction: _refresh,
                      );
                    }

                    final data = snapshot.data!;
                    final filteredUnits = data.units.where((unit) {
                      final unitName = (unit['name'] ?? '')
                          .toString()
                          .toLowerCase();
                      final location = [
                        unit['barangay'],
                        unit['city'],
                        unit['province'],
                      ].whereType<String>().join(' ').toLowerCase();

                      final assignedNames = [
                        ((unit['president'] as Map?)?['full_name'] ?? ''),
                        ((unit['secretary'] as Map?)?['full_name'] ?? ''),
                        ((unit['treasurer'] as Map?)?['full_name'] ?? ''),
                        ...(unit['collectors'] as List).map(
                          (collector) =>
                              (collector['full_name'] ?? '').toString(),
                        ),
                      ].join(' ').toLowerCase();

                      return unitName.contains(_search) ||
                          location.contains(_search) ||
                          assignedNames.contains(_search);
                    }).toList();

                    if (filteredUnits.isEmpty) {
                      return _AdminsEmptyState(
                        title: 'No matching units',
                        message:
                            'Try another search term to find a Dayung unit or assigned officer.',
                        icon: Icons.apartment_outlined,
                        actionLabel: 'Clear Search',
                        onAction: () async {
                          setState(() => _search = '');
                        },
                      );
                    }

                    final collectorCount = filteredUnits.fold<int>(
                      0,
                      (count, unit) =>
                          count + (unit['collectors'] as List).length,
                    );

                    return RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                        children: [
                          _AdminSummaryBar(
                            units: filteredUnits.length,
                            officers: filteredUnits.fold<int>(
                              0,
                              (count, unit) =>
                                  count +
                                  [
                                    unit['president'],
                                    unit['secretary'],
                                    unit['treasurer'],
                                  ].where((item) => item != null).length,
                            ),
                            collectors: collectorCount,
                          ),
                          const SizedBox(height: 16),
                          ...filteredUnits.map(
                            (unit) => Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _UnitRoleCard(
                                unit: unit,
                                onAssignRole: (role) async {
                                  final selected = await _pickUser(
                                    'Assign ${_labelForRole(role)}',
                                    data.applicantsByUnit[unit['id']
                                            ?.toString()] ??
                                        [],
                                  );
                                  if (selected == null) return;
                                  await _assignRole(
                                    unit: unit,
                                    role: role,
                                    user: selected,
                                  );
                                },
                                onRemoveRole: (role) =>
                                    _removeRole(unit: unit, role: role),
                                onAddCollector: () async {
                                  final selected = await _pickUser(
                                    'Add Collector',
                                    data.applicantsByUnit[unit['id']
                                            ?.toString()] ??
                                        [],
                                  );
                                  if (selected == null) return;
                                  await _assignRole(
                                    unit: unit,
                                    role: 'collector',
                                    user: selected,
                                  );
                                },
                                onRemoveCollector: (collectorId) => _removeRole(
                                  unit: unit,
                                  role: 'collector',
                                  userId: collectorId,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminScreenData {
  final List<Map<String, dynamic>> units;
  final List<Map<String, dynamic>> users;
  final Map<String, List<Map<String, dynamic>>> applicantsByUnit;

  const _AdminScreenData({
    required this.units,
    required this.users,
    required this.applicantsByUnit,
  });
}

class _AdminsHero extends StatelessWidget {
  final String searchValue;
  final ValueChanged<String> onSearchChanged;

  const _AdminsHero({required this.searchValue, required this.onSearchChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F766E), Color(0xFF0EA5E9), Color(0xFFECFEFF)],
          stops: [0, 0.6, 1],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Manage Unit Roles',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 10),
          // const Text(
          //   'Assign and replace officers with large, readable controls so role changes stay clear and safe for every Dayung unit.',
          //   style: TextStyle(
          //     fontSize: 16,
          //     height: 1.45,
          //     color: Color(0xFFE0F7FF),
          //   ),
          // ),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: TextField(
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by unit, place, or officer',
                hintStyle: const TextStyle(fontSize: 16),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searchValue.isEmpty
                    ? null
                    : const Icon(
                        Icons.check_circle_outline_rounded,
                        color: kSuccess,
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminSummaryBar extends StatelessWidget {
  final int units;
  final int officers;
  final int collectors;

  const _AdminSummaryBar({
    required this.units,
    required this.officers,
    required this.collectors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _MetricChip(label: 'Units', value: '$units', color: kPrimary),
          _MetricChip(
            label: 'Officers',
            value: '$officers',
            color: const Color(0xFF7C3AED),
          ),
          _MetricChip(
            label: 'Collectors',
            value: '$collectors',
            color: kSuccess,
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: color, fontSize: 14),
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            TextSpan(text: label),
          ],
        ),
      ),
    );
  }
}

class _UnitRoleCard extends StatelessWidget {
  final Map<String, dynamic> unit;
  final Future<void> Function(String role) onAssignRole;
  final Future<void> Function(String role) onRemoveRole;
  final Future<void> Function() onAddCollector;
  final Future<void> Function(String collectorId) onRemoveCollector;

  const _UnitRoleCard({
    required this.unit,
    required this.onAssignRole,
    required this.onRemoveRole,
    required this.onAddCollector,
    required this.onRemoveCollector,
  });

  @override
  Widget build(BuildContext context) {
    final collectors = List<Map<String, dynamic>>.from(
      unit['collectors'] as List,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (unit['name'] ?? 'Dayung Unit').toString(),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: kPrimary,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            [unit['barangay'], unit['city'], unit['province']]
                .where((part) => (part ?? '').toString().trim().isNotEmpty)
                .join(' • '),
            style: const TextStyle(fontSize: 15, color: kSubText, height: 1.35),
          ),
          const SizedBox(height: 18),
          _RoleTile(
            title: 'President',
            color: const Color(0xFF1D4ED8),
            assignee: unit['president'] as Map<String, dynamic>?,
            onAssign: () => onAssignRole('president'),
            onRemove: unit['president'] == null
                ? null
                : () => onRemoveRole('president'),
          ),
          const SizedBox(height: 12),
          _RoleTile(
            title: 'Secretary',
            color: const Color(0xFF7C3AED),
            assignee: unit['secretary'] as Map<String, dynamic>?,
            onAssign: () => onAssignRole('secretary'),
            onRemove: unit['secretary'] == null
                ? null
                : () => onRemoveRole('secretary'),
          ),
          const SizedBox(height: 12),
          _RoleTile(
            title: 'Treasurer',
            color: const Color(0xFFEA580C),
            assignee: unit['treasurer'] as Map<String, dynamic>?,
            onAssign: () => onAssignRole('treasurer'),
            onRemove: unit['treasurer'] == null
                ? null
                : () => onRemoveRole('treasurer'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Collectors',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF065F46),
                  fontFamily: 'Montserrat',
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: onAddCollector,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Add Collector'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kSuccess,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (collectors.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'No collectors assigned yet.',
                style: TextStyle(fontSize: 15, color: kSubText),
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: collectors.map((collector) {
                return _CollectorChip(
                  collector: collector,
                  onRemove: () => onRemoveCollector(collector['id'].toString()),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final String title;
  final Color color;
  final Map<String, dynamic>? assignee;
  final VoidCallback onAssign;
  final VoidCallback? onRemove;

  const _RoleTile({
    required this.title,
    required this.color,
    required this.assignee,
    required this.onAssign,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            assignee == null
                ? 'No one is assigned yet.'
                : '${assignee!['full_name'] ?? 'Assigned user'}\n${assignee!['email'] ?? ''}',
            style: const TextStyle(fontSize: 15, color: kSubText, height: 1.4),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: onAssign,
                icon: Icon(
                  assignee == null
                      ? Icons.person_add_alt_1
                      : Icons.swap_horiz_rounded,
                ),
                label: Text(assignee == null ? 'Assign' : 'Replace'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              if (onRemove != null)
                OutlinedButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  label: const Text('Remove'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kDanger,
                    side: BorderSide(color: kDanger.withValues(alpha: 0.22)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CollectorChip extends StatelessWidget {
  final Map<String, dynamic> collector;
  final VoidCallback onRemove;

  const _CollectorChip({required this.collector, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kSuccess.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                (collector['full_name'] ?? 'Collector').toString(),
                style: const TextStyle(
                  color: Color(0xFF065F46),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if ((collector['email'] ?? '').toString().isNotEmpty)
                Text(
                  collector['email'].toString(),
                  style: const TextStyle(fontSize: 12, color: kSubText),
                ),
            ],
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(18),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 18, color: kDanger),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminsEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final String actionLabel;
  final Future<void> Function() onAction;

  const _AdminsEmptyState({
    required this.title,
    required this.message,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: kPrimary),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: kSubText,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectUserDialog extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> users;

  const _SelectUserDialog({required this.title, required this.users});

  @override
  State<_SelectUserDialog> createState() => _SelectUserDialogState();
}

class _SelectUserDialogState extends State<_SelectUserDialog> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filteredUsers = widget.users.where((user) {
      final haystack = '${user['full_name'] ?? ''} ${user['email'] ?? ''}'
          .toLowerCase();
      return haystack.contains(_search);
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: kPrimary,
                  fontFamily: 'Montserrat',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: (value) =>
                    setState(() => _search = value.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search by name or email',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: filteredUsers.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No users match the current search.'),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: filteredUsers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final user = filteredUsers[index];
                          return Material(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(18),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              title: Text(
                                (user['full_name'] ?? 'No Name').toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text((user['email'] ?? '').toString()),
                              trailing: ElevatedButton(
                                onPressed: () => Navigator.pop(context, user),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimary,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Select'),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
