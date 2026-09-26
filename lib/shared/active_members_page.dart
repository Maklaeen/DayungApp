import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Clipboard copy removed; no services import needed

const Color _kPrimary = Color(0xFF0D47A1);
const Color _kPrimaryDark = Color(0xFF083366);
const Color _kNeutralText = Color(0xFF1F2937);
const Color _kSubText = Color(0xFF4B5563);
const Color _kSuccess = Color(0xFF10B981);

class ActiveMembersPage extends StatefulWidget {
  final int dayungUnitId;
  const ActiveMembersPage({super.key, required this.dayungUnitId});

  @override
  State<ActiveMembersPage> createState() => _ActiveMembersPageState();
}

class _ActiveMembersPageState extends State<ActiveMembersPage> {
  static const int _pageSize = 10;

  final _sb = Supabase.instance.client;
  bool _loading = true;
  bool _savingGroups = false;
  String? _error;
  List<Map<String, dynamic>> _members = [];
  String _search = '';
  int _pageIndex = 0;
  int? _membersPerGroup;
  List<List<Map<String, dynamic>>> _serviceGroups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _sb
          .from('payments')
          .select(
            'id, user_id, amount, paid_at, created_at, status, type, '
            'user:users!payments_user_id_fkey(id, full_name, profile_url, email)',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('type', 'membership_payment')
          .eq('status', 'paid')
          .order('paid_at', ascending: false)
          .order('created_at', ascending: false);

      final paymentRows = List<Map<String, dynamic>>.from(rows);
      final uniqueMembers = <String, Map<String, dynamic>>{};

      for (final row in paymentRows) {
        final userId = (row['user_id'] ?? '').toString().trim();
        if (userId.isEmpty) continue;

        final existing = uniqueMembers[userId];
        if (existing == null) {
          uniqueMembers[userId] = row;
          continue;
        }

        final currentPaidAt = DateTime.tryParse(
          (row['paid_at'] ?? row['created_at'] ?? '').toString(),
        );
        final existingPaidAt = DateTime.tryParse(
          (existing['paid_at'] ?? existing['created_at'] ?? '').toString(),
        );
        if (currentPaidAt != null &&
            (existingPaidAt == null || currentPaidAt.isAfter(existingPaidAt))) {
          uniqueMembers[userId] = row;
        }
      }

      final unitRow = await _sb
          .from('dayung_units')
          .select('president_id, secretary_id, treasurer_id')
          .eq('id', widget.dayungUnitId)
          .maybeSingle();

      if (unitRow != null) {
        final officerIds = <String>{};
        for (final key in ['president_id', 'secretary_id', 'treasurer_id']) {
          final value = unitRow[key];
          if (value != null) officerIds.add(value.toString().trim());
        }

        final missingOfficerIds = officerIds
            .where((id) => id.isNotEmpty && !uniqueMembers.containsKey(id))
            .toList();

        if (missingOfficerIds.isNotEmpty) {
          for (final id in missingOfficerIds) {
            final userRow = await _sb
                .from('users')
                .select('id, full_name, profile_url, email')
                .eq('id', id)
                .maybeSingle();

            if (userRow == null) continue;
            final userId = (userRow['id'] ?? '').toString().trim();
            if (userId.isEmpty) continue;
            uniqueMembers[userId] = {
              'user_id': userId,
              'paid_at': null,
              'created_at': null,
              'status': 'officer',
              'type': 'membership_payment',
              'user': userRow,
            };
          }
        }
      }

      if (mounted) {
        final membersList = uniqueMembers.values.toList();
        membersList.sort((a, b) {
          final aName = ((a['user'] as Map?)?['full_name'] ?? '')
              .toString()
              .toLowerCase();
          final bName = ((b['user'] as Map?)?['full_name'] ?? '')
              .toString()
              .toLowerCase();
          return aName.compareTo(bName);
        });

        setState(() {
          _members = membersList;
          _pageIndex = 0;
          _membersPerGroup = null;
          _serviceGroups = [];
          _loading = false;
        });
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _members;
    final q = _search.toLowerCase();
    return _members.where((r) {
      final u = r['user'] as Map?;
      final name = (u?['full_name'] ?? '').toString().toLowerCase();
      final userId = (r['user_id'] ?? '').toString().toLowerCase();
      return name.contains(q) || userId.contains(q);
    }).toList();
  }

  int get _pageCount {
    if (_filtered.isEmpty) return 1;
    return (_filtered.length / _pageSize).ceil();
  }

  List<Map<String, dynamic>> get _pagedFiltered {
    final start = _pageIndex * _pageSize;
    if (start >= _filtered.length) return const <Map<String, dynamic>>[];
    final end = (start + _pageSize).clamp(0, _filtered.length);
    return _filtered.sublist(start, end);
  }

  void _goToPreviousPage() {
    if (_pageIndex == 0) return;
    setState(() => _pageIndex -= 1);
  }

  void _goToNextPage() {
    if (_pageIndex >= _pageCount - 1) return;
    setState(() => _pageIndex += 1);
  }

  String _groupLabel(int index) {
    var value = index + 1;
    var label = '';
    while (value > 0) {
      final remainder = (value - 1) % 26;
      label = String.fromCharCode(65 + remainder) + label;
      value = (value - 1) ~/ 26;
    }
    return label;
  }

  Future<List<Map<String, dynamic>>> _loadApprovedMembersForGroups() async {
    final rows = await _sb
        .from('applications')
        .select('user_id, user:users(id, full_name, profile_url, email)')
        .eq('dayung_unit_id', widget.dayungUnitId)
        .eq('status', 'approved');

    final uniqueMembers = <String, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final userId = (row['user_id'] ?? '').toString().trim();
      if (userId.isNotEmpty) uniqueMembers[userId] = row;
    }
    return uniqueMembers.values.toList();
  }

  Future<int?> _loadActiveServiceChecklistId() async {
    final row = await _sb
        .from('service_checklist')
        .select('id')
        .eq('dayung_unit_id', widget.dayungUnitId)
        .or('is_removed.is.null,is_removed.eq.false')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row?['id'] as int?;
  }

  Future<void> _saveServiceGroups(
    int membersPerGroup,
    int serviceChecklistId,
    List<Map<String, dynamic>> approvedMembers,
  ) async {
    if (_savingGroups) return;
    setState(() => _savingGroups = true);

    try {
      final existingRows = await _sb
          .from('service_checklist_participants')
          .select('user_id, group')
          .eq('service_checklist_id', serviceChecklistId);
      final approvedById = <String, Map<String, dynamic>>{
        for (final member in approvedMembers)
          member['user_id'].toString(): member,
      };
      final groupsByLabel = <String, List<Map<String, dynamic>>>{};
      final assignedUserIds = <String>{};

      for (final row in List<Map<String, dynamic>>.from(existingRows)) {
        final userId = (row['user_id'] ?? '').toString().trim();
        final group = (row['group'] ?? '').toString().trim();
        final member = approvedById[userId];
        if (userId.isEmpty || group.isEmpty || member == null) continue;
        groupsByLabel.putIfAbsent(group, () => []).add(member);
        assignedUserIds.add(userId);
      }

      final groupLabels = groupsByLabel.keys.toList()
        ..sort((a, b) => a.compareTo(b));
      var nextGroupIndex = 0;
      while (groupsByLabel.containsKey(_groupLabel(nextGroupIndex))) {
        nextGroupIndex++;
      }

      final createdAt = DateTime.now().toIso8601String();
      final participantRows = <Map<String, dynamic>>[];
      for (final member in approvedMembers) {
        final userId = member['user_id'].toString().trim();
        if (assignedUserIds.contains(userId)) continue;

        String? targetGroup;
        for (final label in groupLabels) {
          if (groupsByLabel[label]!.length < membersPerGroup) {
            targetGroup = label;
            break;
          }
        }
        targetGroup ??= _groupLabel(nextGroupIndex++);
        groupsByLabel.putIfAbsent(targetGroup, () => []).add(member);
        if (!groupLabels.contains(targetGroup)) groupLabels.add(targetGroup);
        assignedUserIds.add(userId);
        participantRows.add({
          'service_checklist_id': serviceChecklistId,
          'user_id': member['user_id'],
          'group': targetGroup,
          'dayung_unit_id': widget.dayungUnitId,
          'created_at': createdAt,
        });
      }

      if (participantRows.isNotEmpty) {
        await _sb
            .from('service_checklist_participants')
            .insert(participantRows);
      }

      final groups =
          groupsByLabel.entries
              .where((entry) => entry.value.isNotEmpty)
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key));

      if (!mounted) return;
      setState(() {
        _membersPerGroup = membersPerGroup;
        _serviceGroups = groups.map((entry) => entry.value).toList();
        _savingGroups = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            participantRows.isEmpty
                ? 'All approved members are already assigned to service groups.'
                : 'Added ${participantRows.length} new members without changing existing assignments.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingGroups = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save service groups: $e')),
      );
    }
  }

  Future<void> _resetServiceGroups(int serviceChecklistId) async {
    if (_savingGroups) return;
    setState(() => _savingGroups = true);

    try {
      await _sb
          .from('service_checklist_participants')
          .update({'group': 'NO GROUPS'})
          .eq('service_checklist_id', serviceChecklistId);

      if (!mounted) return;
      setState(() {
        _membersPerGroup = null;
        _serviceGroups = [];
        _savingGroups = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Service groups were reset.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingGroups = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reset service groups: $e')),
      );
    }
  }

  Future<void> _openServiceGroupDialog() async {
    if (_members.isEmpty) return;

    late final int serviceChecklistId;
    late final List<Map<String, dynamic>> approvedMembers;
    try {
      final checklistId = await _loadActiveServiceChecklistId();
      if (checklistId == null) {
        throw Exception(
          'No active service checklist was found for this Dayung unit.',
        );
      }
      serviceChecklistId = checklistId;
      approvedMembers = await _loadApprovedMembersForGroups();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load approved members: $e')),
      );
      return;
    }
    if (approvedMembers.isEmpty || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No approved members were found for this Dayung unit.',
            ),
          ),
        );
      }
      return;
    }

    final controller = TextEditingController(
      text: (_membersPerGroup ?? 5).clamp(1, approvedMembers.length).toString(),
    );
    final membersPerGroup = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Generate Service Groups',
          style: TextStyle(
            color: _kNeutralText,
            fontWeight: FontWeight.w800,
            fontFamily: 'Montserrat',
          ),
        ),
        content: StatefulBuilder(
          builder: (_, setDialogState) {
            final totalMembers = approvedMembers.length;
            final selectedCount = int.tryParse(controller.text) ?? 0;
            final canDecrease = selectedCount > 1;
            final canIncrease = selectedCount < totalMembers;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total active members: $totalMembers',
                  style: const TextStyle(
                    color: _kPrimary,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'OpenSans',
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Members Per Group',
                  style: TextStyle(
                    color: _kNeutralText,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Decrease members per group',
                      onPressed: canDecrease
                          ? () {
                              controller.text = (selectedCount - 1).toString();
                              setDialogState(() {});
                            }
                          : null,
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      color: _kPrimary,
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Increase members per group',
                      onPressed: canIncrease
                          ? () {
                              controller.text = (selectedCount + 1).toString();
                              setDialogState(() {});
                            }
                          : null,
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      color: _kPrimary,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  selectedCount > 0
                      ? 'This will create ${(totalMembers / selectedCount).ceil()} service groups.'
                      : 'Enter a number between 1 and $totalMembers.',
                  style: const TextStyle(
                    color: _kSubText,
                    fontSize: 12,
                    fontFamily: 'OpenSans',
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final shouldReset = await showDialog<bool>(
                context: dialogContext,
                builder: (confirmationContext) => AlertDialog(
                  title: const Text('Reset service groups?'),
                  content: const Text(
                    'The group value for all service checklist participants will be changed to NO GROUPS.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          Navigator.of(confirmationContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () =>
                          Navigator.of(confirmationContext).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Reset Groups'),
                    ),
                  ],
                ),
              );
              if (shouldReset != true || !mounted) return;
              Navigator.of(dialogContext).pop();
              await _resetServiceGroups(serviceChecklistId);
            },
            child: const Text('Reset Groups'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value == null ||
                  value < 1 ||
                  value > approvedMembers.length) {
                return;
              }
              Navigator.of(dialogContext).pop(value);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (membersPerGroup == null || !mounted) return;
    await _saveServiceGroups(
      membersPerGroup,
      serviceChecklistId,
      approvedMembers,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(8, 36, 20, 28),
              decoration: const BoxDecoration(
                color: _kPrimaryDark,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: IconButton(
                      tooltip: 'Back',
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.groups_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Active Members',
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
                      '${_members.length}',
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search member',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: _kPrimary,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (v) => setState(() {
                  _search = v.trim();
                  _pageIndex = 0;
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _members.isEmpty || _savingGroups
                      ? null
                      : _openServiceGroupDialog,
                  icon: const Icon(Icons.groups_rounded),
                  label: Text(
                    _savingGroups
                        ? 'Saving Service Groups...'
                        : _serviceGroups.isEmpty
                        ? 'Generate or Update Service Groups'
                        : 'Add New Members to Groups',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            if (_serviceGroups.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_serviceGroups.length} service groups  |  $_membersPerGroup members per group  |  ${_members.length} total members',
                    style: const TextStyle(
                      color: _kSubText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'OpenSans',
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _kPrimary),
                    )
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 48,
                              color: _kPrimary.withValues(alpha: 0.8),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Failed to load active members',
                              style: TextStyle(
                                color: _kNeutralText,
                                fontSize: 16,
                                fontFamily: 'Montserrat',
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: _kSubText,
                                fontSize: 12,
                                fontFamily: 'OpenSans',
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _load,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kPrimary,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 56,
                            color: _kSubText.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No active members found',
                            style: TextStyle(
                              color: _kSubText,
                              fontSize: 16,
                              fontFamily: 'Montserrat',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _pagedFiltered.length,
                              itemBuilder: (_, i) =>
                                  _memberCard(_pagedFiltered[i]),
                            ),
                          ),
                        ),
                        if (_filtered.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  onPressed: _pageIndex == 0
                                      ? null
                                      : _goToPreviousPage,
                                  icon: const Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                  ),
                                  color: _kPrimary,
                                ),
                                Text(
                                  'Page ${_pageIndex + 1} of $_pageCount',
                                  style: const TextStyle(
                                    color: _kNeutralText,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Montserrat',
                                  ),
                                ),
                                IconButton(
                                  onPressed: _pageIndex >= _pageCount - 1
                                      ? null
                                      : _goToNextPage,
                                  icon: const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                  ),
                                  color: _kPrimary,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberCard(Map<String, dynamic> r) {
    final u = r['user'] as Map?;
    final name = (u?['full_name'] ?? 'Member').toString();
    final profileUrl = (u?['profile_url'] ?? '').toString();
    final userId = (r['user_id'] ?? '').toString();
    final paidAt = (r['paid_at'] ?? r['created_at'] ?? '').toString();
    String dateStr = '';
    if (paidAt.isNotEmpty) {
      final dt = DateTime.tryParse(paidAt);
      if (dt != null) dateStr = '${dt.month}/${dt.day}/${dt.year}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 22,
          backgroundImage: profileUrl.isNotEmpty
              ? NetworkImage(profileUrl)
              : null,
          backgroundColor: _kSuccess.withValues(alpha: 0.1),
          child: profileUrl.isEmpty
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'M',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _kSuccess,
                  ),
                )
              : null,
        ),
        title: Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: _kNeutralText,
            fontFamily: 'Montserrat',
          ),
        ),
        subtitle: dateStr.isNotEmpty
            ? Text(
                'Approved: $dateStr',
                style: const TextStyle(
                  fontSize: 12,
                  color: _kSubText,
                  fontFamily: 'OpenSans',
                ),
              )
            : null,
        // trailing action removed (copy UID)
      ),
    );
  }
}
