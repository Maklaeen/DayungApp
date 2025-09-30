import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageRolesPagePres extends StatefulWidget {
  const ManageRolesPagePres({super.key});

  @override
  State<ManageRolesPagePres> createState() => _ManageRolesPageState();
}

class _ManageRolesPageState extends State<ManageRolesPagePres> {
  final sb = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _units = [];
  int? _unitId;

  List<Map<String, dynamic>> _members = [];
  String? _secretaryId;
  String? _treasurerId;
  final Set<String> _collectors = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    try {
      await _loadUnitsForPresident();
      if (_unitId != null) {
        await _loadUnitData(_unitId!);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadUnitsForPresident() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) {
      _units = [];
      _unitId = null;
      return;
    }
    final res = await sb
        .from('dayung_units')
        .select('id,name')
        .eq('president_id', uid)
        .order('name');
    _units = List<Map<String, dynamic>>.from(res);
    if (_units.isNotEmpty) {
      _unitId = (_units.first['id'] as int?) ?? int.tryParse('${_units.first['id']}');
    }
  }

  Future<void> _loadUnitData(int unitId) async {
    // load members of this unit
    final usersRes = await sb
        .from('users')
        .select('id, full_name, mobile_number')
        .eq('dayung_unit_id', unitId)
        .order('full_name', ascending: true);
    _members = List<Map<String, dynamic>>.from(usersRes);

    // load secretary/treasurer
    final du = await sb
        .from('dayung_units')
        .select('secretary_id, treasurer_id')
        .eq('id', unitId)
        .maybeSingle();
    _secretaryId = du?['secretary_id']?.toString();
    _treasurerId = du?['treasurer_id']?.toString();

    // load collectors
    final colRes = await sb
        .from('dayung_collectors')
        .select('user_id')
        .eq('dayung_unit_id', unitId);
    _collectors
      ..clear()
      ..addAll(List<Map<String, dynamic>>.from(colRes)
          .map((e) => (e['user_id'] ?? '').toString())
          .where((s) => s.isNotEmpty));
    setState(() {});
  }

  Future<void> _setSecretary(String? userId) async {
    if (_unitId == null) return;
    await sb
        .from('dayung_units')
        .update({'secretary_id': userId})
        .eq('id', _unitId!);
    _secretaryId = userId;
    setState(() {});
    _snack('Secretary updated.');
  }

  Future<void> _setTreasurer(String? userId) async {
    if (_unitId == null) return;
    await sb
        .from('dayung_units')
        .update({'treasurer_id': userId})
        .eq('id', _unitId!);
    _treasurerId = userId;
    setState(() {});
    _snack('Treasurer updated.');
  }

  Future<void> _addCollector(String userId) async {
    if (_unitId == null) return;
    await sb.from('dayung_collectors').insert({
      'dayung_unit_id': _unitId!,
      'user_id': userId,
      'added_by': sb.auth.currentUser?.id,
    });
    _collectors.add(userId);
    setState(() {});
    _snack('Collector added.');
  }

  Future<void> _removeCollector(String userId) async {
    if (_unitId == null) return;
    await sb
        .from('dayung_collectors')
        .delete()
        .match({'dayung_unit_id': _unitId!, 'user_id': userId});
    _collectors.remove(userId);
    setState(() {});
    _snack('Collector removed.');
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Roles'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _units.isEmpty
              ? const Center(child: Text('No dayung units found for your account'))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Unit picker
                      Row(
                        children: [
                          const Text(
                            'Dayung Unit:',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _unitId,
                              items: _units
                                  .map((u) => DropdownMenuItem<int>(
                                        value: (u['id'] as int?) ??
                                            int.tryParse('${u['id']}'),
                                        child: Text(
                                          (u['name'] ?? 'Unit ${u['id']}').toString(),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (v) async {
                                _unitId = v;
                                setState(() => _loading = true);
                                try {
                                  if (v != null) await _loadUnitData(v);
                                } finally {
                                  if (mounted) setState(() => _loading = false);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Expanded(
                        child: ListView(
                          children: [
                            _roleTile(
                              title: 'Secretary',
                              currentUserId: _secretaryId,
                              members: _members,
                              onAssign: (id) => _setSecretary(id),
                              onClear: () => _setSecretary(null),
                            ),
                            const SizedBox(height: 10),
                            _roleTile(
                              title: 'Treasurer',
                              currentUserId: _treasurerId,
                              members: _members,
                              onAssign: (id) => _setTreasurer(id),
                              onClear: () => _setTreasurer(null),
                            ),
                            const SizedBox(height: 10),
                            _collectorsTile(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _roleTile({
    required String title,
    required String? currentUserId,
    required List<Map<String, dynamic>> members,
    required Future<void> Function(String userId) onAssign,
    required Future<void> Function() onClear,
  }) {
    final current = members.firstWhere(
      (m) => (m['id'] ?? '').toString() == (currentUserId ?? ''),
      orElse: () => const {'id': null, 'full_name': null},
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    currentUserId == null
                        ? 'Not assigned'
                        : '${current['full_name'] ?? currentUserId} (${currentUserId!.substring(0, 6)}...)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => _pickMember(members).then((id) {
                    if (id != null) onAssign(id);
                  }),
                  child: const Text('Assign'),
                ),
                const SizedBox(width: 6),
                if (currentUserId != null)
                  TextButton(
                    onPressed: onClear,
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _collectorsTile() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Collectors',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: -6,
              children: _collectors.isEmpty
                  ? [const Text('None assigned')]
                  : _collectors.map((id) {
                      final user = _members.firstWhere(
                        (m) => (m['id'] ?? '').toString() == id,
                        orElse: () => const {'full_name': null},
                      );
                      final name = (user['full_name'] ?? id).toString();
                      return Chip(
                        label: Text(name, overflow: TextOverflow.ellipsis),
                        deleteIcon: const Icon(Icons.close),
                        onDeleted: () => _removeCollector(id),
                      );
                    }).toList(),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _pickMember(_members, multi: false).then((id) {
                  if (id != null && !_collectors.contains(id)) {
                    _addCollector(id);
                  }
                }),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add Collector'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickMember(List<Map<String, dynamic>> members,
      {bool multi = false}) async {
    final controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape:
          const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 10,
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          child: StatefulBuilder(builder: (ctx, setM) {
            final q = controller.text.trim().toLowerCase();
            final list = q.isEmpty
                ? members
                : members.where((m) {
                    final name = (m['full_name'] ?? '').toString().toLowerCase();
                    final id = (m['id'] ?? '').toString().toLowerCase();
                    return name.contains(q) || id.contains(q);
                  }).toList();
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                children: [
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: 'Search member',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setM(() {}),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: list.isEmpty
                        ? const Center(child: Text('No members found'))
                        : ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final u = list[i];
                              return ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.person)),
                                title: Text((u['full_name'] ?? 'Member').toString(),
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text((u['id'] ?? '').toString()),
                                onTap: () => Navigator.pop(context, (u['id'] ?? '').toString()),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}