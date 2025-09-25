import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

// Shared palette (aligns with dashboard.dart)
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kWarn = Color(0xFFF57C00);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);
const double kRadius = 18;

class SecretaryClaimsPage extends StatefulWidget {
  const SecretaryClaimsPage({super.key});
  @override
  State<SecretaryClaimsPage> createState() => _SecretaryClaimsPageState();
}

class _SecretaryClaimsPageState extends State<SecretaryClaimsPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late TabController _tabController;

  // Data
  Map<String, Map<String, dynamic>> _userMap = {};
  List<Map<String, dynamic>> _claims = [];
  List<Map<String, dynamic>> _dayungUnits = []; // [{id: int, name: String}]
  Map<int, String> _dayungNameMap = {};
  bool _loading = true;
  bool _updating = false;
  bool _loadingDayungs = true;

  // Filters / state
  final List<String> _tabs = ["Pending", "Approved", "Rejected"];
  int? _selectedDayungId; // null = All
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      _fetchClaims();
    });
    _initLoad();
  }

  Future<void> _initLoad() async {
    await _loadManagedDayungs();
    await _fetchClaims();
  }

  Future<void> _loadManagedDayungs() async {
    setState(() => _loadingDayungs = true);
    try {
      final secretaryId = supabase.auth.currentUser?.id;
      if (secretaryId == null) {
        setState(() {
          _dayungUnits = [];
          _dayungNameMap = {};
          _loadingDayungs = false;
        });
        return;
      }
      final rows = await supabase
          .from('dayung_units')
          .select('id,name')
          .eq('secretary_id', secretaryId)
          .order('name');

      final list = List<Map<String, dynamic>>.from(rows);
      final nameMap = <int, String>{};
      for (final r in list) {
        final id = r['id'];
        if (id is int) {
          nameMap[id] = (r['name'] ?? 'Dayung').toString();
        }
      }
      setState(() {
        _dayungUnits = list;
        _dayungNameMap = nameMap;
        _loadingDayungs = false;
      });
    } catch (e) {
      setState(() {
        _dayungUnits = [];
        _dayungNameMap = {};
        _loadingDayungs = false;
      });
    }
  }

  Future<void> _fetchClaims() async {
    setState(() => _loading = true);
    try {
      if (_loadingDayungs) {
        await _loadManagedDayungs();
      }

      // Managed dayung ids
      final managedIds = _dayungUnits
          .map((e) => e['id'])
          .whereType<int>()
          .toList();

      if (managedIds.isEmpty) {
        setState(() {
          _claims = [];
          _userMap = {};
          _loading = false;
        });
        return;
      }

      // Limit to a specific dayung if selected
      final targetIds = _selectedDayungId != null
          ? <int>[_selectedDayungId!]
          : managedIds;

      // 1. Fetch members (no join needed)
      // Using inFilter; if your SDK lacks it, replace with .filter('dayung_unit_id', 'in', '(1,2,3)')
      final memberRows = await supabase
          .from('users')
          .select('id, full_name, profile_url, dayung_unit_id')
          .inFilter('dayung_unit_id', targetIds);

      final membersList = List<Map<String, dynamic>>.from(memberRows);
      final allowedUserIds = <String>[];
      final userMap = <String, Map<String, dynamic>>{};

      for (final m in membersList) {
        final uid = (m['id'] ?? '').toString();
        if (uid.isEmpty) continue;
        allowedUserIds.add(uid);
        userMap[uid] = {
          'full_name': m['full_name'] ?? '',
          'profile_url': m['profile_url'] ?? '',
          'dayung_unit_id': m['dayung_unit_id'],
        };
      }

      if (allowedUserIds.isEmpty) {
        setState(() {
          _claims = [];
          _userMap = {};
          _loading = false;
        });
        return;
      }

      final statusTitle = _tabs[_tabController.index]; // "Pending" etc.

      // 2. Fetch claims for those user_ids (no join)
      var claimQuery = supabase
          .from('claims')
          .select('id, user_id, title, description, status, date_submitted')
          .eq('status', statusTitle)
          .inFilter('user_id', allowedUserIds)
          .order('date_submitted', ascending: false);

      final data = await claimQuery;
      final claimList = List<Map<String, dynamic>>.from(data);

      setState(() {
        _claims = claimList;
        _userMap = userMap;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error fetching claims: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(String claimId, String newStatusTitleCase) async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      // Use match() instead of eq()
      await supabase
          .from('claims')
          .update({'status': newStatusTitleCase})
          .match({'id': claimId});
      await _fetchClaims();
    } catch (e) {
      debugPrint("Error updating status: $e");
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'approved':
        return kAccent;
      case 'rejected':
        return kDanger;
      case 'pending':
      default:
        return kWarn;
    }
  }

  IconData _statusIcon(String s) {
    switch (s.toLowerCase()) {
      case 'approved':
        return Icons.verified;
      case 'rejected':
        return Icons.cancel_outlined;
      case 'pending':
      default:
        return Icons.pending_actions;
    }
  }

  String _formatDate(dynamic v) {
    if (v == null) return '';
    try {
      final dt = DateTime.parse(v.toString()).toLocal();
      return DateFormat('MMM d, yyyy • h:mm a').format(dt);
    } catch (_) {
      return v.toString();
    }
  }

  List<Map<String, dynamic>> get _filteredClaims {
    if (_search.trim().isEmpty) return _claims;
    final q = _search.toLowerCase();
    return _claims.where((c) {
      final userInfo = _userMap[(c['user_id'] ?? '').toString()];
      final submitter = (userInfo?['full_name'] ?? '').toString().toLowerCase();
      final dayungId = userInfo?['dayung_unit_id'];
      final dayungName = (dayungId is int)
          ? (_dayungNameMap[dayungId] ?? '')
          : '';
      return (c['title'] ?? '').toString().toLowerCase().contains(q) ||
          (c['description'] ?? '').toString().toLowerCase().contains(q) ||
          (c['id'] ?? '').toString().toLowerCase().contains(q) ||
          submitter.contains(q) ||
          dayungName.toLowerCase().contains(q);
    }).toList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentStatus = _tabs[_tabController.index];
    final claims = _filteredClaims;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF7),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        titleSpacing: 0,

        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(148),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: _searchField(),
              ),
              TabBar(
                controller: _tabController,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  fontFamily: 'Montserrat',
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  fontFamily: 'Montserrat',
                ),
                labelColor: kPrimaryDark,
                unselectedLabelColor: kSubtleText,
                indicator: UnderlineTabIndicator(
                  borderSide: BorderSide(
                    color: kPrimaryDark.withOpacity(.9),
                    width: 3,
                  ),
                  insets: const EdgeInsets.symmetric(horizontal: 28),
                ),
                tabs: _tabs.map((t) {
                  final active = t == currentStatus;
                  return Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _statusIcon(t),
                          size: 18,
                          color: active ? _statusColor(t) : kSubtleText,
                        ),
                        const SizedBox(width: 6),
                        Text(t),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              _dayungFilterBar(),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          _loading || _loadingDayungs
              ? ListView(
                  padding: const EdgeInsets.only(top: 40),
                  children: [_skeletonCard(), _skeletonCard(), _skeletonCard()],
                )
              : (claims.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 120),
                          Icon(
                            _statusIcon(currentStatus),
                            size: 54,
                            color: _statusColor(currentStatus).withOpacity(.6),
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: Text(
                              _dayungUnits.isEmpty
                                  ? "No managed Dayung units"
                                  : "No $currentStatus claims",
                              style: const TextStyle(
                                fontSize: 16,
                                fontFamily: 'OpenSans',
                                fontWeight: FontWeight.w600,
                                color: kNeutralText,
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: claims.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (_, i) => _claimCard(claims[i]),
                      )),
          if (_updating)
            Positioned(
              left: 0,
              right: 0,
              bottom: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.75),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        "Updating...",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontFamily: 'OpenSans',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dayungFilterBar() {
    if (_dayungUnits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            "No Dayung units assigned",
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'OpenSans',
              fontWeight: FontWeight.w600,
              color: kSubtleText,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.filter_alt, size: 18, color: kPrimaryDark),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                isExpanded: true,
                value: _selectedDayungId,
                borderRadius: BorderRadius.circular(16),
                icon: const Icon(Icons.expand_more),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text(
                      "All Dayungs",
                      style: TextStyle(
                        fontFamily: 'OpenSans',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ..._dayungUnits.map((d) {
                    return DropdownMenuItem<int?>(
                      value: d['id'] as int,
                      child: Text(
                        (d['name'] ?? 'Dayung').toString(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'OpenSans',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }),
                ],
                onChanged: (v) {
                  setState(() => _selectedDayungId = v);
                  _fetchClaims();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchCtrl,
      onChanged: (v) => setState(() => _search = v),
      decoration: InputDecoration(
        hintText: "Search title, member, dayung...",
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.grey.shade100,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: kPrimaryDark, width: 1.6),
        ),
        suffixIcon: _search.isEmpty
            ? null
            : IconButton(
                tooltip: "Clear",
                icon: const Icon(Icons.close),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _search = '');
                },
              ),
      ),
    );
  }

  Widget _claimCard(Map<String, dynamic> claim) {
    final status = (claim['status'] ?? '').toString();
    final color = _statusColor(status);
    final id = (claim['id'] ?? '').toString();
    final title = (claim['title'] ?? 'Untitled').toString();
    final desc = (claim['description'] ?? '').toString();
    final date = _formatDate(claim['date_submitted']);

    final userId = (claim['user_id'] ?? '').toString();
    final userInfo = _userMap[userId];
    final submitter = (userInfo?['full_name'] ?? 'Member').toString();
    final profileUrl = (userInfo?['profile_url'] ?? '').toString();
    final dayungUnitId = userInfo?['dayung_unit_id'];
    final dayungName = (dayungUnitId is int)
        ? (_dayungNameMap[dayungUnitId] ?? 'Dayung')
        : 'Dayung';

    return InkWell(
      onTap: () => _showDetail(claim),
      borderRadius: BorderRadius.circular(kRadius),
      child: Container(
        // ...existing decoration...
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(kRadius),
          border: Border.all(color: color.withOpacity(.35), width: 1.4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status + ID
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(.12),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: color.withOpacity(.45)),
                  ),
                  child: Row(
                    children: [
                      Icon(_statusIcon(status), size: 14, color: color),
                      const SizedBox(width: 4),
                      Text(
                        status[0].toUpperCase() + status.substring(1),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  "#$id",
                  style: TextStyle(
                    fontSize: 11,
                    color: kSubtleText.withOpacity(.7),
                    fontFamily: 'OpenSans',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                fontFamily: 'Montserrat',
                height: 1.15,
                color: kNeutralText,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _avatar(profileUrl, submitter, size: 30),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$submitter • $dayungName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontFamily: 'OpenSans',
                      fontWeight: FontWeight.w600,
                      color: kSubtleText.withOpacity(.9),
                    ),
                  ),
                ),
              ],
            ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                desc,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.2,
                  height: 1.3,
                  fontFamily: 'OpenSans',
                  color: kSubtleText,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: kSubtleText),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    date,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'OpenSans',
                      color: kSubtleText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _actionButtons(status, claim),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(String url, String name, {double size = 34}) {
    final initials = name.isNotEmpty
        ? name
              .trim()
              .split(RegExp(r'\s+'))
              .take(2)
              .map((e) => e[0])
              .join()
              .toUpperCase()
        : '?';
    final bg = kPrimary.withOpacity(.12);
    if (url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackAvatar(initials, size, bg),
          loadingBuilder: (c, child, prog) {
            if (prog == null) return child;
            return _fallbackAvatar(initials, size, bg);
          },
        ),
      );
    }
    return _fallbackAvatar(initials, size, bg);
  }

  Widget _fallbackAvatar(String initials, double size, Color bg) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: kPrimary.withOpacity(.4)),
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          fontFamily: 'Montserrat',
          color: kPrimaryDark,
        ),
      ),
    );
  }

  Widget _actionButtons(String status, Map<String, dynamic> claim) {
    final sLower = status.toLowerCase();
    final id = claim['id'].toString();

    Widget btn({
      required String label,
      required Color color,
      required IconData icon,
      required VoidCallback onTap,
    }) {
      return TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          foregroundColor: color,
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            fontFamily: 'Montserrat',
          ),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label),
        onPressed: _updating ? null : onTap,
      );
    }

    if (sLower == 'pending') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(
            label: "Approve",
            color: kAccent,
            icon: Icons.check_circle_outline,
            onTap: () => _updateStatus(id, 'Approved'),
          ),
          btn(
            label: "Reject",
            color: kDanger,
            icon: Icons.cancel_outlined,
            onTap: () => _updateStatus(id, 'Rejected'),
          ),
        ],
      );
    }
    if (sLower == 'approved') {
      return btn(
        label: "Set Pending",
        color: kWarn,
        icon: Icons.history_toggle_off,
        onTap: () => _updateStatus(id, 'Pending'),
      );
    }
    return btn(
      label: "Set Pending",
      color: kWarn,
      icon: Icons.history_toggle_off,
      onTap: () => _updateStatus(id, 'Pending'),
    );
  }

  void _showDetail(Map<String, dynamic> claim) {
    final status = (claim['status'] ?? '').toString();
    final color = _statusColor(status);
    final userId = (claim['user_id'] ?? '').toString();
    final userInfo = _userMap[userId];
    final submitter = (userInfo?['full_name'] ?? 'Member').toString();
    final profileUrl = (userInfo?['profile_url'] ?? '').toString();
    final dayungUnitId = userInfo?['dayung_unit_id'];
    final dayungName = (dayungUnitId is int)
        ? (_dayungNameMap[dayungUnitId] ?? 'Dayung')
        : 'Dayung';

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _avatar(profileUrl, submitter, size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      submitter,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Montserrat',
                        color: kNeutralText,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(.12),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: color.withOpacity(.45)),
                    ),
                    child: Row(
                      children: [
                        Icon(_statusIcon(status), size: 16, color: color),
                        const SizedBox(width: 4),
                        Text(
                          status,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Montserrat',
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.home_work_outlined,
                    size: 16,
                    color: kSubtleText,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      dayungName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'OpenSans',
                        fontWeight: FontWeight.w600,
                        color: kSubtleText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                (claim['title'] ?? 'Untitled').toString(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Montserrat',
                  color: kNeutralText,
                ),
              ),
              const SizedBox(height: 10),
              if ((claim['description'] ?? '').toString().trim().isNotEmpty)
                Text(
                  claim['description'],
                  style: const TextStyle(
                    fontSize: 14,
                    fontFamily: 'OpenSans',
                    height: 1.35,
                  ),
                ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _detailChip(icon: Icons.tag, label: "#${claim['id']}"),
                  _detailChip(
                    icon: Icons.access_time,
                    label: _formatDate(claim['date_submitted']),
                  ),
                  _detailChip(icon: Icons.account_circle, label: submitter),
                  _detailChip(icon: Icons.apartment, label: dayungName),
                ],
              ),
              const SizedBox(height: 22),
              _bottomSheetActions(status, claim),
            ],
          ),
        );
      },
    );
  }

  Widget _detailChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: kSubtleText),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
              color: kSubtleText,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _bottomSheetActions(String status, Map<String, dynamic> claim) {
    final sLower = status.toLowerCase();
    final id = claim['id'].toString();
    if (sLower == 'pending') {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _updating
                  ? null
                  : () {
                      _updateStatus(id, 'Approved');
                      Navigator.pop(context);
                    },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text("Approve"),
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _updating
                  ? null
                  : () {
                      _updateStatus(id, 'Rejected');
                      Navigator.pop(context);
                    },
              icon: const Icon(Icons.cancel_outlined),
              label: const Text("Reject"),
              style: ElevatedButton.styleFrom(
                backgroundColor: kDanger,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return ElevatedButton.icon(
      onPressed: _updating
          ? null
          : () {
              _updateStatus(id, 'Pending');
              Navigator.pop(context);
            },
      icon: const Icon(Icons.history_toggle_off),
      label: const Text("Set Pending"),
      style: ElevatedButton.styleFrom(
        backgroundColor: kWarn,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _skeletonCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(kRadius),
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _skelLine(140),
                  const SizedBox(height: 10),
                  _skelLine(200),
                  const SizedBox(height: 8),
                  _skelLine(160),
                  const Spacer(),
                  _skelLine(120),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skelLine(double w) {
    return Container(
      width: w,
      height: 10,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
