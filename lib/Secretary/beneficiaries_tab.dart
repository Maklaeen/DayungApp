import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:photo_view/photo_view.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchBeneficiaries();
  }

  Future<void> _fetchBeneficiaries() async {
    setState(() => _loading = true);
    final supabase = Supabase.instance.client;
    try {
      // 1. Get approved members from applications
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
          .eq('dayung_unit_id', widget.dayungUnitId.toString())
          .inFilter('status', ['Approved', 'Pending'])
          .order('full_name', ascending: true);

      final ids = {
        for (final b in (beneficiariesData as List))
          (b as Map)['user_id'].toString(),
      }.where((id) => id.isNotEmpty).toList();

      final usersData = ids.isEmpty
          ? []
          : await supabase
                .from('users')
                .select('id, full_name')
                .inFilter('id', ids);

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

  Widget _groupedList(
    Map<String, List<dynamic>> grouped, {
    bool isPending = false,
  }) {
    if (grouped.isEmpty) {
      return Center(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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
                  isPending
                      ? 'No pending beneficiaries found'
                      : 'No active beneficiaries found',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: kText,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isPending
                      ? 'No pending beneficiaries have been recorded yet'
                      : 'No active beneficiaries have been recorded yet',
                  style: const TextStyle(
                    fontSize: 14,
                    color: kSubText,
                    fontFamily: 'OpenSans',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final sortedUserIds = grouped.keys.toList()
      ..sort(
        (a, b) => (_users[a] ?? '').toString().compareTo(
          (_users[b] ?? '').toString(),
        ),
      );

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: sortedUserIds.length,
      itemBuilder: (context, idx) {
        final userId = sortedUserIds[idx];
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
                    backgroundColor: kAccent.withOpacity(0.1),
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
            ...beneficiaries
                .map(
                  (b) => _beneficiaryCard(
                    Map<String, dynamic>.from(b as Map),
                    isPending: isPending,
                  ),
                )
                .toList(),
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
          backgroundColor: kAccent.withOpacity(0.1),
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
                        ? kSuccess.withOpacity(0.12)
                        : b['status'] == 'Rejected'
                        ? kDanger.withOpacity(0.12)
                        : kWarn.withOpacity(0.12),
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
      backgroundColor: kCardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 0,
          right: 0,
          top: 0,
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 48,
                height: 6,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              // Avatar and Name
              CircleAvatar(
                radius: 36,
                backgroundColor: kAccent.withOpacity(0.12),
                child: const Icon(
                  Icons.person_rounded,
                  color: kAccent,
                  size: 40,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                item['full_name'] ?? 'Beneficiary Details',
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: kText,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              if (item['relationship'] != null)
                Text(
                  item['relationship'],
                  style: const TextStyle(
                    color: kSubText,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'OpenSans',
                  ),
                ),
              const SizedBox(height: 18),
              // Details section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: kBg,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _detailRow('Date of Birth', item['dob']),
                    _detailRow('Marital Status', item['marital_status']),
                    _detailRow('Status', item['status']),
                    const SizedBox(height: 10),
                    if (item['birth_certificate'] != null &&
                        item['birth_certificate'].toString().isNotEmpty)
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
              const SizedBox(height: 24),
              // Action buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: item['status'] == 'Pending'
                      ? MainAxisAlignment.spaceBetween
                      : MainAxisAlignment.end,
                  children: [
                    if (item['status'] == 'Pending')
                      ElevatedButton.icon(
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kSuccess,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _approveBeneficiary(item['id']);
                        },
                      ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Close'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
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
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => Dialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.network(
                          url,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Text('Could not load image'),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Close'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                ),
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
    final width = MediaQuery.of(context).size.width;
    final bool isMobile = width < 600;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Modern Curved Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 36, 20, 28),
              decoration: const BoxDecoration(
                color: kAccent,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: kAccent,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.chevron_left,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Icon(Icons.group, color: Colors.white, size: 24),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Beneficiaries',
                      style: TextStyle(
                        fontSize: 20,
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
            // Modern Tab Bar
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
                                        _activeByUser,
                                        isPending: false,
                                      )
                                    : _groupedList(
                                        _pendingByUser,
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
          color: selected ? kAccent.withOpacity(0.12) : Colors.transparent,
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
