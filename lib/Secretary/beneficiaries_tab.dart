import 'package:flutter/material.dart';
import 'package:capstone_app/Secretary/secretary_ui.dart';
import 'package:capstone_app/utils/supabase_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Modern palette (reuse from beneficiary.dart)
const Color kBg = Color(0xFFFAFAF7);
const Color kText = Color(0xFF1F2937);
const Color kSubText = Color(0xFF4B5563);
const Color kAccent = Color(0xFF0D47A1);
const Color kPrimary = Color(0xFF0D47A1);
const Color kWarn = Color(0xFFF57C00);
const Color kDanger = Color(0xFFC62828);
const Color kSuccess = Color(0xFF10B981);
const Color kCardBg = Color(0xFFFFFFFF);

class SecretaryBeneficiariesTab extends StatefulWidget {
  final int dayungUnitId;
  const SecretaryBeneficiariesTab({super.key, required this.dayungUnitId});

  @override
  State<SecretaryBeneficiariesTab> createState() =>
      _SecretaryBeneficiariesTabState();
}

class _SecretaryBeneficiariesTabState extends State<SecretaryBeneficiariesTab> {
  int _selectedTab = 0;
  Map<String, dynamic> _users = {};
  Map<String, List<dynamic>> _pendingByUser = {};
  Map<String, List<dynamic>> _activeByUser = {};
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchBeneficiaries();
  }

  Future<void> _fetchBeneficiaries() async {
    setState(() => _loading = true);
    final supabase = Supabase.instance.client;
    try {
      final apps = await supabase
          .from('applications')
          .select('user_id')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'approved');
      final memberUserIds = (apps as List<dynamic>)
          .map((e) => (e as Map)['user_id'])
          .where((v) => v != null && v.toString().trim().isNotEmpty)
          .map((v) => v.toString())
          .toSet();

      // 2. Get officials from dayung_units
      final unit = await supabase
          .from('dayung_units')
          .select('president_id, secretary_id, treasurer_id, collector_id')
          .eq('id', widget.dayungUnitId)
          .maybeSingle();
      if (unit != null) {
        for (final key in [
          'president_id',
          'secretary_id',
          'treasurer_id',
          'collector_id',
        ]) {
          final id = unit[key];
          if (id != null && id.toString().trim().isNotEmpty) {
            memberUserIds.add(id.toString());
          }
        }
      }

      // 3. Get collectors from dayung_collectors
      final collectors = await supabase
          .from('dayung_collectors')
          .select('user_id')
          .eq('dayung_unit_id', widget.dayungUnitId);
      for (final c in collectors as List<dynamic>) {
        final id = (c as Map)['user_id'];
        if (id != null && id.toString().trim().isNotEmpty) {
          memberUserIds.add(id.toString());
        }
      }

      final allUserIds = memberUserIds.toList();

      // 4. Get user names
      Map<String, dynamic> usersMap = {};
      if (allUserIds.isNotEmpty) {
        final usersData = await supabase
            .from('users')
            .select('id, full_name')
            .inFilter('id', allUserIds);

        for (final user in usersData as List<dynamic>) {
          final m = user as Map<String, dynamic>;
          usersMap[m['id'].toString()] = (m['full_name'] ?? 'Unknown User')
              .toString();
        }
      }

      // 5. Get beneficiaries for these users in this unit
      final beneficiariesData = await supabase
          .from('beneficiaries')
          .select(
            'id, user_id, full_name, relationship, dob, status, birth_certificate, marital_status, valid_id',
          )
          .eq('dayung_unit_id', widget.dayungUnitId)
          .inFilter('status', ['Approved', 'Pending'])
          .order('full_name', ascending: true);

      // Group beneficiaries by user and status
      final pendingByUser = <String, List<dynamic>>{};
      final activeByUser = <String, List<dynamic>>{};
      for (final raw in beneficiariesData as List<dynamic>) {
        final b = raw as Map<String, dynamic>;
        final uid = (b['user_id'] ?? '').toString();
        if (uid.isEmpty) continue;
        final status = (b['status'] ?? '').toString();
        if (status == 'Pending') {
          pendingByUser.putIfAbsent(uid, () => []).add(b);
        } else if (status == 'Approved') {
          activeByUser.putIfAbsent(uid, () => []).add(b);
        }
      }

      if (!mounted) return;
      setState(() {
        _users = usersMap;
        _pendingByUser = pendingByUser;
        _activeByUser = activeByUser;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching beneficiaries: $e')),
      );
    }
  }

  Future<void> _approveBeneficiary(dynamic id) async {
    final supabase = Supabase.instance.client;
    try {
      await supabase
          .from('beneficiaries')
          .update({'status': 'Approved', 'eligible_to_claim': true})
          .eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Beneficiary approved!')));
      await _fetchBeneficiaries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error approving: $e')));
    }
  }

  Map<String, List<dynamic>> _filteredGrouped(
    Map<String, List<dynamic>> grouped,
  ) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return grouped;

    final filtered = <String, List<dynamic>>{};
    for (final entry in grouped.entries) {
      final userName = (_users[entry.key] ?? '').toString().toLowerCase();
      final items = entry.value.where((raw) {
        final item = Map<String, dynamic>.from(raw as Map);
        final fullName = (item['full_name'] ?? '').toString().toLowerCase();
        final relationship = (item['relationship'] ?? '')
            .toString()
            .toLowerCase();
        final maritalStatus = (item['marital_status'] ?? '')
            .toString()
            .toLowerCase();
        return userName.contains(query) ||
            fullName.contains(query) ||
            relationship.contains(query) ||
            maritalStatus.contains(query);
      }).toList();

      if (items.isNotEmpty) {
        filtered[entry.key] = items;
      }
    }
    return filtered;
  }

  int get _activeCount =>
      _activeByUser.values.fold(0, (sum, items) => sum + items.length);

  int get _pendingCount =>
      _pendingByUser.values.fold(0, (sum, items) => sum + items.length);

  Widget _overviewStat({
    required IconData icon,
    required String label,
    required String value,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: tone, size: 16),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: kText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: kSubText,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _overviewStat(
                icon: Icons.check_circle_rounded,
                label: 'Active',
                value: '$_activeCount',
                tone: kSuccess,
              ),
              _overviewStat(
                icon: Icons.schedule_rounded,
                label: 'Pending',
                value: '$_pendingCount',
                tone: kWarn,
              ),
              _overviewStat(
                icon: Icons.people_alt_rounded,
                label: 'Members',
                value: '${_users.length}',
                tone: kAccent,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: kBg,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kAccent),
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          if (_searchQuery.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => setState(() => _searchQuery = ''),
              icon: const Icon(Icons.filter_alt_off_rounded),
              label: const Text('Reset search'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _groupedList(
    Map<String, List<dynamic>> grouped, {
    bool isPending = false,
  }) {
    if (grouped.isEmpty) {
      final hasSearch = _searchQuery.trim().isNotEmpty;
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          _buildToolbarCard(),
          Card(
            margin: const EdgeInsets.fromLTRB(8, 16, 8, 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined, size: 48, color: kSubText),
                  const SizedBox(height: 16),
                  Text(
                    hasSearch
                        ? 'No matching beneficiaries found'
                        : isPending
                        ? 'No pending beneficiaries found'
                        : 'No active beneficiaries found',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: kText,
                      fontFamily: 'Montserrat',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasSearch
                        ? 'Try a different search keyword or clear the active filter.'
                        : isPending
                        ? 'No pending beneficiaries have been recorded yet'
                        : 'No active beneficiaries have been recorded yet',
                    style: const TextStyle(
                      fontSize: 14,
                      color: kSubText,
                      fontFamily: 'OpenSans',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (hasSearch) ...[
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _searchQuery = ''),
                      icon: const Icon(Icons.filter_alt_off_rounded),
                      label: const Text('Reset search'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }

    final sortedUserIds = grouped.keys.toList()
      ..sort(
        (a, b) => (_users[a] ?? '').toString().compareTo(
          (_users[b] ?? '').toString(),
        ),
      );

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: sortedUserIds.length + 1,
      itemBuilder: (context, idx) {
        if (idx == 0) {
          return _buildToolbarCard();
        }

        final userId = sortedUserIds[idx - 1];
        final userName = _users[userId] ?? 'Unknown User';
        final beneficiaries = grouped[userId]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: kAccent.withValues(alpha: 0.1),
                    child: const Icon(Icons.person_rounded, color: kAccent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      userName.toString(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: kAccent,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...beneficiaries.map(
              (b) => _beneficiaryCard(
                Map<String, dynamic>.from(b as Map),
                isPending: isPending,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _beneficiaryCard(Map b, {bool isPending = false}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: () => _showBeneficiaryDetails(b),
        leading: CircleAvatar(
          backgroundColor: kAccent.withValues(alpha: 0.1),
          child: const Icon(Icons.person_rounded, color: kAccent),
        ),
        title: Text(
          b['full_name'] ?? '',
          style: const TextStyle(fontWeight: FontWeight.bold, color: kText),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Relationship: ${b['relationship'] ?? ''}',
              style: const TextStyle(color: kSubText),
            ),
            if (b['dob'] != null)
              Text(
                'DOB: ${b['dob']}',
                style: const TextStyle(color: kSubText, fontSize: 12),
              ),
            if (b['marital_status'] != null)
              Text(
                'Marital Status: ${b['marital_status']}',
                style: const TextStyle(color: kSubText, fontSize: 12),
              ),
            if (b['status'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: b['status'] == 'Approved'
                        ? kSuccess.withValues(alpha: 0.12)
                        : b['status'] == 'Rejected'
                        ? kDanger.withValues(alpha: 0.12)
                        : kWarn.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    b['status'],
                    style: TextStyle(
                      color: b['status'] == 'Approved'
                          ? kSuccess
                          : b['status'] == 'Rejected'
                          ? kDanger
                          : kWarn,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (b['birth_certificate'] != null &&
                b['birth_certificate'].toString().isNotEmpty)
              const Icon(Icons.picture_as_pdf, color: kAccent),
            if (b['valid_id'] != null && b['valid_id'].toString().isNotEmpty)
              const Icon(Icons.credit_card, color: kAccent),
          ],
        ),
      ),
    );
  }

  void _showBeneficiaryDetails(Map item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            decoration: const BoxDecoration(
              color: kCardBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SecretarySheetHeader(
                  title: item['full_name'] ?? 'Beneficiary Details',
                  subtitle:
                      (item['relationship'] ?? 'Review beneficiary information')
                          .toString(),
                  onClose: () => Navigator.pop(context),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: kBg,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: kAccent.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _detailRow('Date of Birth', item['dob']),
                              _detailRow(
                                'Marital Status',
                                item['marital_status'],
                              ),
                              _detailRow('Status', item['status']),
                              const SizedBox(height: 10),
                              if (item['birth_certificate'] != null &&
                                  item['birth_certificate']
                                      .toString()
                                      .isNotEmpty)
                                _fileSection(
                                  context,
                                  label: 'Birth Certificate',
                                  url: item['birth_certificate'],
                                ),
                              if (item['valid_id'] != null &&
                                  item['valid_id'].toString().isNotEmpty)
                                _fileSection(
                                  context,
                                  label: 'Valid ID',
                                  url: item['valid_id'],
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            if (item['status'] == 'Pending') ...[
                              Expanded(
                                child: FilledButton.icon(
                                  icon: const Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Approve'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: kSuccess,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size.fromHeight(46),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () async {
                                    final userName =
                                        _users[item['user_id']] ??
                                        'this member';
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text(
                                          'Approve Beneficiary',
                                        ),
                                        content: Text(
                                          "Do you want to approve this beneficiary for the member of '$userName'?",
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(true),
                                            child: const Text('Approve'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      Navigator.pop(context);
                                      _approveBeneficiary(item['id']);
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                label: const Text('Close'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(46),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _fileSection(
    BuildContext context, {
    required String label,
    required String url,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: kBg,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          leading: label == 'Valid ID'
              ? const Icon(Icons.credit_card, color: kAccent)
              : const Icon(Icons.picture_as_pdf, color: kAccent),
          title: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, color: kText),
          ),
          trailing: TextButton(
            child: const Text(
              'View',
              style: TextStyle(color: kAccent, fontWeight: FontWeight.w600),
            ),
            onPressed: () async {
              final resolved = await resolveSupabaseStorageUrl(url);
              if (resolved == null) return;

              if (storageLooksLikePdf(resolved)) {
                await launchUrl(
                  Uri.parse(resolved),
                  mode: LaunchMode.externalApplication,
                );
                return;
              }

              if (!context.mounted) return;
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) {
                  final height = MediaQuery.of(context).size.height * 0.85;
                  return Container(
                    height: height,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      children: [
                        SecretarySheetHeader(
                          title: label,
                          subtitle: 'Review the uploaded document.',
                          onClose: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                color: kBg,
                                child: InteractiveViewer(
                                  child: Image.network(
                                    resolved,
                                    fit: BoxFit.contain,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Center(
                                              child: Text(
                                                'Could not load image',
                                              ),
                                            ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontFamily: 'Montserrat',
              color: kText,
            ),
          ),
          Expanded(
            child: Text(
              value ?? '',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'OpenSans', color: kSubText),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeGrouped = _filteredGrouped(_activeByUser);
    final pendingGrouped = _filteredGrouped(_pendingByUser);
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            const SecretaryPageHeader(
              title: 'Manage Beneficiaries',
              icon: Icons.family_restroom_rounded,
              usePaymentStyle: true,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Card(
                  color: kCardBg,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      // Modern Tab Bar inside the card
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.filter_list_rounded,
                              size: 16,
                              color: kSubText,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _NavTab(
                                    label: 'Active',
                                    icon: Icons.check_circle_rounded,
                                    selected: _selectedTab == 0,
                                    onTap: () =>
                                        setState(() => _selectedTab = 0),
                                  ),
                                  _NavTab(
                                    label: 'Pending',
                                    icon: Icons.schedule_rounded,
                                    selected: _selectedTab == 1,
                                    onTap: () =>
                                        setState(() => _selectedTab = 1),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, thickness: 1),
                      // List
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () async => _fetchBeneficiaries(),
                          color: kAccent,
                          child: _loading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: kAccent,
                                  ),
                                )
                              : (_selectedTab == 0
                                    ? _groupedList(
                                        activeGrouped,
                                        isPending: false,
                                      )
                                    : _groupedList(
                                        pendingGrouped,
                                        isPending: true,
                                      )),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? kAccent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? kAccent : kSubText),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? kAccent : kSubText,
                fontFamily: 'Montserrat',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
