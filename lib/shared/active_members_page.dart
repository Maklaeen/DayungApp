import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:capstone_app/widgets/record_data_table.dart';
import 'package:intl/intl.dart';

const Color _kPrimary = Color(0xFF0D47A1);
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
  String _membershipFilter = 'Active';
  String _dateFilterMode = 'Year';
  int? _selectedJoinYear;
  int? _selectedJoinMonth;
  DateTime? _selectedJoinDate;
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

      final applicationRows = await _sb
          .from('applications')
          .select(
            'id, user_id, approved_at, updated_at, isRemovedInDayung, '
            'user:users(id, full_name, profile_url, email)',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'approved');
      final applicationsByUser = <String, Map<String, dynamic>>{
        for (final application in List<Map<String, dynamic>>.from(
          applicationRows,
        ))
          if ((application['user_id'] ?? '').toString().trim().isNotEmpty)
            (application['user_id'] ?? '').toString().trim(): application,
      };

      for (final entry in uniqueMembers.entries.toList()) {
        final application = applicationsByUser[entry.key];
        final member = entry.value;
        final isInactive =
            application != null && application['isRemovedInDayung'] == true;
        final membershipEndedAt =
            application != null && application['isRemovedInDayung'] == true
            ? application['updated_at']
            : null;
        final joinedAt =
            application?['approved_at'] ??
            member['paid_at'] ??
            member['created_at'];
        uniqueMembers[entry.key] = {
          ...member,
          'membership_status': isInactive ? 'Inactive' : 'Active',
          'membership_joined_at': joinedAt,
          'membership_ended_at': membershipEndedAt,
        };
      }

      for (final application in applicationsByUser.values) {
        if (application['isRemovedInDayung'] != true) continue;
        final userId = (application['user_id'] ?? '').toString().trim();
        if (userId.isEmpty || uniqueMembers.containsKey(userId)) continue;
        uniqueMembers[userId] = {
          ...application,
          'user_id': userId,
          'paid_at': null,
          'created_at': application['approved_at'],
          'type': 'membership_payment',
          'membership_status': 'Inactive',
          'membership_joined_at': application['approved_at'],
          'membership_ended_at': application['updated_at'],
        };
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
              'membership_status': 'Active',
              'membership_joined_at': null,
              'membership_ended_at': null,
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
    final q = _search.toLowerCase();
    return _members.where((r) {
      final u = r['user'] as Map?;
      final name = (u?['full_name'] ?? '').toString().toLowerCase();
      final userId = (r['user_id'] ?? '').toString().toLowerCase();
      if (_membershipFilter != 'All' &&
          (r['membership_status'] ?? 'Active') != _membershipFilter) {
        return false;
      }
      if (_search.isNotEmpty && !name.contains(q) && !userId.contains(q)) {
        return false;
      }

      final joined = _joinedDate(r);
      if (_dateFilterMode == 'Year' &&
          _selectedJoinYear != null &&
          joined?.year != _selectedJoinYear) {
        return false;
      }
      if (_dateFilterMode == 'Month' &&
          _selectedJoinMonth != null &&
          (joined?.month != _selectedJoinMonth ||
              (_selectedJoinYear != null &&
                  joined?.year != _selectedJoinYear))) {
        return false;
      }
      if (_dateFilterMode == 'Date' && _selectedJoinDate != null) {
        if (joined == null ||
            joined.year != _selectedJoinDate!.year ||
            joined.month != _selectedJoinDate!.month ||
            joined.day != _selectedJoinDate!.day) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  int get _activeMemberCount => _members
      .where((member) => (member['membership_status'] ?? 'Active') == 'Active')
      .length;

  DateTime? _joinedDate(Map<String, dynamic> member) {
    return DateTime.tryParse(
      (member['membership_joined_at'] ??
              member['paid_at'] ??
              member['created_at'] ??
              '')
          .toString(),
    )?.toLocal();
  }

  List<int> get _availableJoinYears {
    return _members
        .map(_joinedDate)
        .whereType<DateTime>()
        .map((date) => date.year)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
  }

  void _setDateMode(String mode) {
    setState(() {
      _dateFilterMode = mode;
      if (mode != 'Month') _selectedJoinMonth = null;
      if (mode != 'Date') _selectedJoinDate = null;
      _pageIndex = 0;
    });
  }

  Future<void> _chooseJoinedDate() async {
    final now = DateTime.now();
    final initialDate =
        _selectedJoinDate ?? DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1990),
      lastDate: DateTime(now.year + 1),
      helpText: 'Select membership join date',
    );
    if (!mounted || date == null) return;
    setState(() {
      _selectedJoinDate = date;
      _pageIndex = 0;
    });
  }

  Widget _buildMemberFilters() {
    final years = _availableJoinYears;
    final inactiveCount = _members.length - _activeMemberCount;
    final statusSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Membership status',
          style: TextStyle(
            color: _kNeutralText,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _statusFilterChip('Active', _activeMemberCount, _kSuccess),
            _statusFilterChip(
              'Inactive',
              inactiveCount,
              const Color(0xFFC62828),
            ),
            _statusFilterChip('All', _members.length, _kPrimary),
          ],
        ),
      ],
    );
    final dateSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Filter by date joined',
          style: TextStyle(
            color: _kNeutralText,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final mode in ['Year', 'Month', 'Date'])
              ChoiceChip(
                label: Text(mode),
                selected: _dateFilterMode == mode,
                onSelected: (_) => _setDateMode(mode),
                selectedColor: const Color(0xFFEAF2FC),
                labelStyle: TextStyle(
                  color: _dateFilterMode == mode ? _kPrimary : _kSubText,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'OpenSans',
                ),
                side: BorderSide(
                  color: _dateFilterMode == mode
                      ? _kPrimary.withValues(alpha: 0.35)
                      : const Color(0xFFD1D5DB),
                ),
              ),
            if (_dateFilterMode != 'Date')
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<int>(
                  initialValue: _selectedJoinYear ?? 0,
                  isExpanded: true,
                  decoration: _filterDropdownDecoration('Year'),
                  items: [
                    const DropdownMenuItem(value: 0, child: Text('All years')),
                    ...years.map(
                      (year) => DropdownMenuItem(
                        value: year,
                        child: Text(year.toString()),
                      ),
                    ),
                  ],
                  onChanged: (year) => setState(() {
                    _selectedJoinYear = year == null || year == 0 ? null : year;
                    _pageIndex = 0;
                  }),
                ),
              ),
            if (_dateFilterMode == 'Month')
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<int>(
                  initialValue: _selectedJoinMonth ?? 0,
                  isExpanded: true,
                  decoration: _filterDropdownDecoration('Month'),
                  items: [
                    const DropdownMenuItem(value: 0, child: Text('All months')),
                    for (var month = 1; month <= 12; month++)
                      DropdownMenuItem(
                        value: month,
                        child: Text(
                          DateFormat.MMMM().format(DateTime(2020, month)),
                        ),
                      ),
                  ],
                  onChanged: (month) => setState(() {
                    _selectedJoinMonth = month == null || month == 0
                        ? null
                        : month;
                    _pageIndex = 0;
                  }),
                ),
              ),
            if (_dateFilterMode == 'Date')
              OutlinedButton.icon(
                onPressed: _chooseJoinedDate,
                icon: const Icon(Icons.calendar_month_rounded),
                label: Text(
                  _selectedJoinDate == null
                      ? 'Choose date'
                      : DateFormat.yMMMd().format(_selectedJoinDate!),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPrimary,
                  minimumSize: const Size(0, 50),
                  side: const BorderSide(color: _kPrimary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            if (_selectedJoinYear != null ||
                _selectedJoinMonth != null ||
                _selectedJoinDate != null)
              TextButton.icon(
                onPressed: () => setState(() {
                  _selectedJoinYear = null;
                  _selectedJoinMonth = null;
                  _selectedJoinDate = null;
                  _pageIndex = 0;
                }),
                icon: const Icon(Icons.filter_alt_off_rounded),
                label: const Text('Clear date'),
              ),
          ],
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: EdgeInsets.all(isWide ? 20 : 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: _kPrimary.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 4, child: statusSection),
                    Container(
                      width: 1,
                      height: 62,
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      color: const Color(0xFFE5E7EB),
                    ),
                    Expanded(flex: 7, child: dateSection),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    statusSection,
                    const SizedBox(height: 18),
                    dateSection,
                  ],
                ),
        );
      },
    );
  }

  Widget _statusFilterChip(String status, int count, Color color) {
    final selected = _membershipFilter == status;
    return ChoiceChip(
      label: Text('$status ($count)'),
      selected: selected,
      onSelected: (_) => setState(() {
        _membershipFilter = status;
        _pageIndex = 0;
      }),
      selectedColor: color.withValues(alpha: 0.12),
      labelStyle: TextStyle(
        color: selected ? color : _kSubText,
        fontSize: 15,
        fontWeight: FontWeight.w800,
        fontFamily: 'OpenSans',
      ),
      side: BorderSide(
        color: selected
            ? color.withValues(alpha: 0.4)
            : const Color(0xFFD1D5DB),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    );
  }

  InputDecoration _filterDropdownDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
      ),
    );
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
        .eq('status', 'approved')
        .or('isRemovedInDayung.is.null,isRemovedInDayung.eq.false');

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
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: const BoxDecoration(
                color: _kPrimary,
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
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Active Members',
                      style: TextStyle(
                        fontSize: 22,
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
                      '${_filtered.length}',
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
            _buildMemberFilters(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _activeMemberCount == 0 || _savingGroups
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
                    '${_serviceGroups.length} service groups  |  $_membersPerGroup members per group  |  $_activeMemberCount active members',
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
                          Text(
                            _membershipFilter == 'Inactive'
                                ? 'No inactive members found'
                                : 'No members found',
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
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(16),
                              children: [
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    if (constraints.maxWidth < 720) {
                                      return _memberMobileRows(_pagedFiltered);
                                    }
                                    return RecordDataTable(
                                      modernStyle: true,
                                      showCheckboxColumn: false,
                                      minWidth: constraints.maxWidth > 1050
                                          ? constraints.maxWidth
                                          : 1050,
                                      dataRowMinHeight: 82,
                                      dataRowMaxHeight: 116,
                                      columns: const [
                                        DataColumn(label: Text('Member name')),
                                        DataColumn(
                                          label: Text('Date and time joined'),
                                        ),
                                        DataColumn(
                                          label: Text('Membership status'),
                                        ),
                                        DataColumn(
                                          label: Text('Membership ended'),
                                        ),
                                      ],
                                      rows: _pagedFiltered
                                          .map(_memberDataRow)
                                          .toList(),
                                    );
                                  },
                                ),
                              ],
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

  Widget _memberMobileRows(List<Map<String, dynamic>> members) {
    return Column(
      children: [
        for (var index = 0; index < members.length; index++) ...[
          _memberMobileRow(members[index]),
          if (index < members.length - 1)
            const Divider(height: 1, indent: 12, endIndent: 12),
        ],
      ],
    );
  }

  Widget _memberMobileRow(Map<String, dynamic> member) {
    final user = member['user'] as Map?;
    final name = (user?['full_name'] ?? 'Member').toString();
    final profileUrl = (user?['profile_url'] ?? '').toString();
    final joinedDate = _joinedDate(member);
    final status = (member['membership_status'] ?? 'Active').toString();
    final endedDate = DateTime.tryParse(
      (member['membership_ended_at'] ?? '').toString(),
    )?.toLocal();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _kNeutralText,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Date joined: ${joinedDate == null ? '—' : DateFormat.yMMMd().add_jm().format(joinedDate)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: _kSubText,
                    fontFamily: 'OpenSans',
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _membershipStatusBadge(status),
                    if (status == 'Inactive' && endedDate != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ended ${DateFormat.yMMMd().format(endedDate)}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: _kSubText,
                            fontFamily: 'OpenSans',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DataRow _memberDataRow(Map<String, dynamic> r) {
    final u = r['user'] as Map?;
    final name = (u?['full_name'] ?? 'Member').toString();
    final profileUrl = (u?['profile_url'] ?? '').toString();
    final joinedAt = _joinedDate(r);
    final endedAt = DateTime.tryParse(
      (r['membership_ended_at'] ?? '').toString(),
    )?.toLocal();
    final status = (r['membership_status'] ?? 'Active').toString();

    return DataRow(
      cells: [
        DataCell(
          Row(
            children: [
              CircleAvatar(
                radius: 18,
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
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: _kNeutralText,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
            ],
          ),
        ),
        DataCell(
          SizedBox(
            width: 185,
            child: Text(
              joinedAt == null
                  ? '—'
                  : DateFormat.yMMMd().add_jm().format(joinedAt),
              style: const TextStyle(color: _kNeutralText),
            ),
          ),
        ),
        DataCell(_membershipStatusBadge(status)),
        DataCell(
          SizedBox(
            width: 170,
            child: Text(
              status != 'Inactive' || endedAt == null
                  ? '—'
                  : DateFormat.yMMMd().add_jm().format(endedAt),
              style: const TextStyle(color: _kSubText),
            ),
          ),
        ),
      ],
    );
  }

  Widget _membershipStatusBadge(String status) {
    final isActive = status == 'Active';
    final color = isActive ? _kSuccess : const Color(0xFFC62828);
    final background = isActive
        ? const Color(0xFFF0FDF4)
        : const Color(0xFFFEF2F2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            status,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              fontFamily: 'OpenSans',
            ),
          ),
        ],
      ),
    );
  }
}
