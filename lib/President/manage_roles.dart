import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/ui/theme/branding.dart';

// Additional colors for manage roles specific styling
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimaryLight = Color(0xFF3B82F6);
const kAccentDark = Color(0xFF059669);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);
const kDanger = Color(0xFFEF4444);
const double kEdge = 16;

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
      _unitId =
          (_units.first['id'] as int?) ?? int.tryParse('${_units.first['id']}');
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
      ..addAll(
        List<Map<String, dynamic>>.from(colRes)
            .map((e) => (e['user_id'] ?? '').toString())
            .where((s) => s.isNotEmpty),
      );
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
    await sb.from('dayung_collectors').delete().match({
      'dayung_unit_id': _unitId!,
      'user_id': userId,
    });
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
      backgroundColor: kBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom App Bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: kPrimary,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimary.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_rounded,
                        size: 24,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Back',
                    ),
                    Expanded(
                      child: Text(
                        'Manage Roles',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontFamily: 'Montserrat',
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: kPrimary,
                          strokeWidth: 3,
                        ),
                      )
                    : _units.isEmpty
                    ? Center(
                        child: Container(
                          margin: const EdgeInsets.all(20),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: kCardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: kBorderColor.withOpacity(0.3),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 15,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.admin_panel_settings_rounded,
                                size: 48,
                                color: kSubText,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No dayung units found',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: kText,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No dayung units found for your account',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: kSubText,
                                  fontFamily: 'OpenSans',
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            // Unit picker
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: kCardBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: kBorderColor.withOpacity(0.3),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 15,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: kPrimary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.location_on_rounded,
                                      color: kPrimary,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Dayung Unit:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      color: kText,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      value: _unitId,
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: kCardBg,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: kBorderColor,
                                            width: 1,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: kBorderColor,
                                            width: 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: kPrimary,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                      items: _units
                                          .map(
                                            (u) => DropdownMenuItem<int>(
                                              value:
                                                  (u['id'] as int?) ??
                                                  int.tryParse('${u['id']}'),
                                              child: Text(
                                                (u['name'] ?? 'Unit ${u['id']}')
                                                    .toString(),
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontFamily: 'OpenSans',
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) async {
                                        _unitId = v;
                                        setState(() => _loading = true);
                                        try {
                                          if (v != null) await _loadUnitData(v);
                                        } finally {
                                          if (mounted)
                                            setState(() => _loading = false);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

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
                                  const SizedBox(height: 16),
                                  _roleTile(
                                    title: 'Treasurer',
                                    currentUserId: _treasurerId,
                                    members: _members,
                                    onAssign: (id) => _setTreasurer(id),
                                    onClear: () => _setTreasurer(null),
                                  ),
                                  const SizedBox(height: 16),
                                  _collectorsTile(),
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorderColor.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 6),
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
                  color: kPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  title == 'Secretary'
                      ? Icons.admin_panel_settings_rounded
                      : Icons.account_balance_wallet_rounded,
                  color: kPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: kText,
                  fontFamily: 'Montserrat',
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: kBorderColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: kBorderColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    currentUserId == null
                        ? 'Not assigned'
                        : '${current['full_name'] ?? currentUserId} (${currentUserId.substring(0, 6)}...)',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: currentUserId == null ? kSubText : kText,
                      fontFamily: 'OpenSans',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () => _pickMember(members).then((id) {
                  if (id != null) onAssign(id);
                }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Assign',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    fontFamily: 'OpenSans',
                  ),
                ),
              ),
              if (currentUserId != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onClear,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kDanger,
                    side: BorderSide(color: kDanger, width: 1.5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Clear',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      fontFamily: 'OpenSans',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _collectorsTile() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorderColor.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 6),
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
                  color: kPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.people_rounded,
                  color: kPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Collectors',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: kText,
                  fontFamily: 'Montserrat',
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _collectors.isEmpty
                ? [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: kBorderColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: kBorderColor.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'None assigned',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: kSubText,
                          fontFamily: 'OpenSans',
                        ),
                      ),
                    ),
                  ]
                : _collectors.map((id) {
                    final user = _members.firstWhere(
                      (m) => (m['id'] ?? '').toString() == id,
                      orElse: () => const {'full_name': null},
                    );
                    final name = (user['full_name'] ?? id).toString();
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: kPrimary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: kPrimary.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: kPrimary,
                              fontFamily: 'OpenSans',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _removeCollector(id),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: kDanger.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: kDanger,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _pickMember(_members, multi: false).then((id) {
                if (id != null && !_collectors.contains(id)) {
                  _addCollector(id);
                }
              }),
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: const Text(
                'Add Collector',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  fontFamily: 'OpenSans',
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: kPrimary,
                side: BorderSide(color: kPrimary, width: 1.5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickMember(
    List<Map<String, dynamic>> members, {
    bool multi = false,
  }) async {
    final controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          decoration: const BoxDecoration(
            color: kCardBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                offset: Offset(0, -5),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: StatefulBuilder(
              builder: (ctx, setM) {
                final q = controller.text.trim().toLowerCase();
                final list = q.isEmpty
                    ? members
                    : members.where((m) {
                        final name = (m['full_name'] ?? '')
                            .toString()
                            .toLowerCase();
                        final id = (m['id'] ?? '').toString().toLowerCase();
                        return name.contains(q) || id.contains(q);
                      }).toList();
                return SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: Column(
                    children: [
                      // Handle bar
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: kBorderColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Search field
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: kBorderColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: kBorderColor.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: TextField(
                          controller: controller,
                          decoration: const InputDecoration(
                            hintText: 'Search member...',
                            hintStyle: TextStyle(
                              color: kSubText,
                              fontFamily: 'OpenSans',
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: kSubText,
                            ),
                            border: InputBorder.none,
                          ),
                          style: const TextStyle(
                            fontFamily: 'OpenSans',
                            fontWeight: FontWeight.w600,
                          ),
                          onChanged: (_) => setM(() {}),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Members list
                      Expanded(
                        child: list.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.search_off_rounded,
                                      size: 48,
                                      color: kSubText,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No members found',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: kSubText,
                                        fontFamily: 'Montserrat',
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                itemCount: list.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final u = list[i];
                                  return Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: kBorderColor.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: kBorderColor.withOpacity(0.2),
                                        width: 1,
                                      ),
                                    ),
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: kPrimary.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.person_rounded,
                                          color: kPrimary,
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(
                                        (u['full_name'] ?? 'Member').toString(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                          color: kText,
                                          fontFamily: 'Montserrat',
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        (u['id'] ?? '').toString(),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: kSubText,
                                          fontFamily: 'OpenSans',
                                        ),
                                      ),
                                      onTap: () => Navigator.pop(
                                        context,
                                        (u['id'] ?? '').toString(),
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
          ),
        );
      },
    );
  }
}
