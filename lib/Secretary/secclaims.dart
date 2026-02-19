import 'dart:io';

import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:photo_view/photo_view.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

// Old palette (kept so old logic/widgets compile)
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kWarn = Color(0xFFF57C00);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);
const double kRadius = 18;

// Extra tones used by new UI
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);

class SecretaryClaimsPage extends StatefulWidget {
  const SecretaryClaimsPage({super.key});
  @override
  State<SecretaryClaimsPage> createState() => _SecretaryClaimsPageState();
}

class _SecretaryClaimsPageState extends State<SecretaryClaimsPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late TabController _tabController;

  Map<String, Map<String, dynamic>> _userMap = {};
  List<Map<String, dynamic>> _claims = [];
  bool _loading = true;
  bool _updating = false;

  final List<String> _tabs = ["Pending", "Approved", "Rejected"];
  String _search = '';
  final _searchCtrl = TextEditingController();
  int? _lastUnitId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      _fetchClaims(forUnitId: _lastUnitId, tabSwitch: true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = context.read<DayungUnitProvider>().currentUnitId;
      _lastUnitId = id;
      _fetchClaims(forUnitId: id);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentId = context.watch<DayungUnitProvider>().currentUnitId;
    if (currentId != _lastUnitId) {
      _lastUnitId = currentId;
      _fetchClaims(forUnitId: currentId);
    }
  }

  Future<void> _fetchClaims({int? forUnitId, bool tabSwitch = false}) async {
    final unitId =
        forUnitId ??
        _lastUnitId ??
        context.read<DayungUnitProvider>().currentUnitId;

    if (unitId == null) {
      if (mounted) {
        setState(() {
          _claims = [];
          _userMap = {};
          _loading = false;
        });
      }
      return;
    }

    _lastUnitId = unitId;

    if (!tabSwitch) {
      if (mounted) setState(() => _loading = true);
    }

    try {
      // Approved members of this unit
      final apps = await supabase
          .from('applications')
          .select('user_id, user:users(id, full_name, profile_url)')
          .eq('dayung_unit_id', unitId)
          .eq('status', 'approved');

      final appsList = List<Map<String, dynamic>>.from(apps);
      final allowedUserIds = <String>[];
      final userMap = <String, Map<String, dynamic>>{};
      for (final r in appsList) {
        final uid = (r['user_id'] ?? '').toString();
        if (uid.isEmpty) continue;
        allowedUserIds.add(uid);
        final u = (r['user'] as Map?)?.cast<String, dynamic>() ?? const {};
        userMap[uid] = {
          'full_name': (u['full_name'] ?? '').toString(),
          'profile_url': (u['profile_url'] ?? '').toString(),
          'dayung_unit_id': unitId,
        };
      }

      final statusTitle = _tabs[_tabController.index];

      // New scheme: claims tagged with unit
      final tagged = await supabase
          .from('claims')
          .select(
            'id, user_id, title, description, status, date_submitted, '
            'death_certificate_url, beneficiary_id, date_of_death, dayung_unit_id, claimedmoney', // <— added
          )
          .eq('status', statusTitle)
          .eq('dayung_unit_id', unitId)
          .order('date_submitted', ascending: false);

      final taggedList = List<Map<String, dynamic>>.from(tagged);

      // Legacy: claims without dayung_unit_id but by members of this unit
      List<Map<String, dynamic>> legacyList = [];
      if (allowedUserIds.isNotEmpty) {
        final legacy = await supabase
            .from('claims')
            .select(
              'id, user_id, title, description, status, date_submitted, '
              'death_certificate_url, beneficiary_id, date_of_death, dayung_unit_id, claimedmoney', // <— added
            )
            .eq('status', statusTitle)
            .isFilter('dayung_unit_id', null)
            .inFilter('user_id', allowedUserIds)
            .order('date_submitted', ascending: false);
        legacyList = List<Map<String, dynamic>>.from(legacy);
      }

      // Merge
      final merged = <String, Map<String, dynamic>>{};
      for (final c in legacyList) {
        merged[c['id'].toString()] = c;
      }
      for (final c in taggedList) {
        merged[c['id'].toString()] = c;
      }

      if (!mounted) return;
      setState(() {
        _claims = merged.values.toList()
          ..sort(
            (a, b) => DateTime.parse(
              b['date_submitted'].toString(),
            ).compareTo(DateTime.parse(a['date_submitted'].toString())),
          );
        _userMap = userMap;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredClaims {
    if (_search.trim().isEmpty) return _claims;
    final q = _search.toLowerCase();
    final dayungName = (context.read<DayungUnitProvider>().dayungUnit ?? '')
        .toLowerCase();
    return _claims.where((c) {
      final userInfo = _userMap[(c['user_id'] ?? '').toString()];
      final submitter = (userInfo?['full_name'] ?? '').toString().toLowerCase();
      return (c['title'] ?? '').toString().toLowerCase().contains(q) ||
          (c['description'] ?? '').toString().toLowerCase().contains(q) ||
          (c['id'] ?? '').toString().toLowerCase().contains(q) ||
          submitter.contains(q) ||
          dayungName.contains(q);
    }).toList();
  }

  Future<Map<String, dynamic>> getDeceasedInfo(
    Map<String, dynamic> claim,
  ) async {
    final sb = Supabase.instance.client;
    final claimDod = (claim['date_of_death'] ?? '').toString();

    if (claim['beneficiary_id'] != null) {
      final b = await sb
          .from('beneficiaries')
          .select('full_name, dob')
          .eq('id', claim['beneficiary_id'])
          .maybeSingle();
      return {
        'name': b?['full_name'] ?? 'Beneficiary',
        'dob': b?['dob'] ?? '',
        'date_of_death': claimDod,
        'type': 'beneficiary',
      };
    } else {
      final u = await sb
          .from('users')
          .select('full_name, dob, date_of_death')
          .eq('id', claim['user_id'])
          .maybeSingle();
      return {
        'name': u?['full_name'] ?? 'Member',
        'dob': u?['dob'] ?? '',
        'date_of_death': claimDod.isNotEmpty
            ? claimDod
            : (u?['date_of_death'] ?? ''),
        'type': 'member',
      };
    }
  }

  int? _computeAge(String? birthIso, String? deathIso) {
    if (birthIso == null ||
        birthIso.isEmpty ||
        deathIso == null ||
        deathIso.isEmpty) {
      return null;
    }
    final b =
        DateTime.tryParse(birthIso) ??
        DateTime.tryParse('${birthIso}T00:00:00');
    final d =
        DateTime.tryParse(deathIso) ??
        DateTime.tryParse('${deathIso}T00:00:00');
    if (b == null || d == null) return null;
    int age = d.year - b.year;
    final hadBirthday =
        (d.month > b.month) || (d.month == b.month && d.day >= b.day);
    return hadBirthday ? age : age - 1;
  }

  Future<void> _updateStatus(String claimId, String newStatusTitleCase) async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      await supabase
          .from('claims')
          .update({'status': newStatusTitleCase})
          .eq('id', claimId);
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
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      case 'pending':
      default:
        return Icons.schedule;
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

  // ===== Claimed money helpers =====
  bool _isClaimed(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v == 1;
    final s = v?.toString().toLowerCase().trim();
    if (s == null) return false;
    return s == 'yes' || s == 'true' || s == '1';
  }

  dynamic _storeClaimedValue(bool value, dynamic existingColumnValue) {
    // Preserve schema: if existing is bool -> write bool, else write "yes"/"no"
    if (existingColumnValue is bool) return value;
    return value ? 'yes' : 'no';
  }

  Future<void> _updateClaimed(
    String claimId,
    bool newValue,
    dynamic existingColumnValue,
  ) async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      final storeVal = _storeClaimedValue(newValue, existingColumnValue);
      await supabase.from('claims').update({'claimedmoney': storeVal}).eq('id', claimId);
      await _fetchClaims();
    } catch (e) {
      debugPrint("Error updating claimedmoney: $e");
    } finally {
      if (mounted) setState(() => _updating = false);
    }
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
    final dayungName =
        context.watch<DayungUnitProvider>().dayungUnit ?? 'Dayung';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          Column(
            children: [
              // Header with search (new UI style)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 50, 20, 12),
                child: _searchField(),
              ),
              // Tab Bar (new UI style)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: false,
                  tabAlignment: TabAlignment.fill,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    fontFamily: 'Montserrat',
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                    fontFamily: 'Montserrat',
                  ),
                  labelColor: kPrimary,
                  unselectedLabelColor: kSubtleText,
                  indicator: const UnderlineTabIndicator(
                    borderSide: BorderSide(color: kPrimary, width: 2),
                  ),
                  tabs: _tabs.map((t) {
                    final active = t == currentStatus;
                    return Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _statusIcon(t),
                            size: 12,
                            color: active ? kPrimary : kSubtleText,
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              t,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                fontFamily: 'Montserrat',
                                color: active ? kPrimary : kSubtleText,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              // Current Dayung banner (read-only, from provider)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.home_work_outlined,
                        size: 16,
                        color: kSubtleText,
                      ),
                      const SizedBox(width: 8),
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
                ),
              ),
              // List content
              Expanded(
                child: _loading
                    ? Center(
                        child: Container(
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
                              CircularProgressIndicator(
                                color: kPrimary,
                                strokeWidth: 3,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Loading claims...',
                                style: TextStyle(
                                  color: kSubtleText,
                                  fontSize: 16,
                                  fontFamily: 'OpenSans',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : (claims.isEmpty
                          ? SingleChildScrollView(
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
                                      _statusIcon(currentStatus),
                                      size: 48,
                                      color: _statusColor(
                                        currentStatus,
                                      ).withOpacity(0.6),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      "No claims found",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: kNeutralText,
                                        fontFamily: 'Montserrat',
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      "No claims for the selected status in this Dayung",
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: kSubtleText,
                                        fontFamily: 'OpenSans',
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                              itemCount: claims.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) => _claimCard(claims[i]),
                            )),
              ),
            ],
          ),

          // Updating overlay (keep as overlay)
          if (_updating)
            Positioned(
              left: 0,
              right: 0,
              bottom: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: kPrimary,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: kPrimary.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
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
                          fontSize: 14,
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

  Widget _searchField() {
    return TextField(
      controller: _searchCtrl,
      onChanged: (v) => setState(() => _search = v),
      style: const TextStyle(color: Colors.black87, fontSize: 14),
      decoration: InputDecoration(
        hintText: "Search title, member, dayung...",
        hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
        prefixIcon: const Icon(Icons.search, color: Colors.grey),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: kPrimary, width: 2),
        ),
        suffixIcon: _search.isEmpty
            ? null
            : IconButton(
                tooltip: "Clear",
                icon: const Icon(Icons.close, color: Colors.grey),
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
    final title = (claim['title'] ?? 'Untitled').toString();
    final date = _formatDate(claim['date_submitted']);
    final desc = (claim['description'] ?? '').toString().trim();
    final claimed = _isClaimed(claim['claimedmoney']); // <— existing

    return InkWell(
      onTap: () => _showDetail(claim),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(.2), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withOpacity(.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_statusIcon(status), size: 12, color: color),
                      const SizedBox(width: 4),
                      Text(
                        status[0].toUpperCase() + status.substring(1),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Montserrat',
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                // Only show claimed chip for Approved
                if (status.toLowerCase() == 'approved') ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (claimed ? kAccent : Colors.grey).withOpacity(.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: (claimed ? kAccent : Colors.grey).withOpacity(.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          claimed ? Icons.payments : Icons.money_off,
                          size: 12,
                          color: claimed ? kAccent : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          claimed ? 'Claimed' : 'Not claimed',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Montserrat',
                            color: claimed ? kAccent : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  '#${claim['id'].toString().substring(0, 8)}...',
                  style: TextStyle(
                    fontSize: 9,
                    fontFamily: 'OpenSans',
                    fontWeight: FontWeight.w500,
                    color: kSubtleText.withOpacity(.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Title
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFamily: 'Montserrat',
                color: kNeutralText,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Description
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                desc,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'OpenSans',
                  color: kSubtleText,
                ),
              ),
            ],
            const SizedBox(height: 6),
            // Deceased line
            FutureBuilder<Map<String, dynamic>>(
              future: getDeceasedInfo(claim),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final deceased = snapshot.data!;
                return Text(
                  'Deceased: ${deceased['name']}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: kNeutralText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
            const SizedBox(height: 6),
            // Date row
            Row(
              children: [
                Icon(Icons.schedule, size: 12, color: kSubtleText),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    date,
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'OpenSans',
                      fontWeight: FontWeight.w500,
                      color: kSubtleText,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Colors.black38,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(Map<String, dynamic> claim) {
    final status = (claim['status'] ?? '').toString();
    final color = _statusColor(status);
    final userId = (claim['user_id'] ?? '').toString();
    final userInfo = _userMap[userId];
    final submitter = (userInfo?['full_name'] ?? 'Member').toString();
    final dayungName =
        context.read<DayungUnitProvider>().dayungUnit ?? 'Dayung';
    final claimed = _isClaimed(claim['claimedmoney']); // <— existing

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.8,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                offset: Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(_statusIcon(status), size: 28, color: color),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            submitter,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dayungName,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withOpacity(0.3)),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        (claim['title'] ?? 'Untitled').toString(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Description
                      if ((claim['description'] ?? '')
                          .toString()
                          .trim()
                          .isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Text(
                            claim['description'],
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey.shade700,
                              height: 1.5,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      // Meta details
                      //_buildInfoRow(Icons.fingerprint, 'ID', '#${claim['id']}'),
                      _buildInfoRow(
                        Icons.schedule,
                        'Submitted',
                        _formatDate(claim['date_submitted']),
                      ),
                      _buildInfoRow(
                        Icons.person_outline,
                        'Submitter',
                        submitter,
                      ),
                      _buildInfoRow(Icons.business, 'Dayung', dayungName),
                      // Only show Claimed Money row for Approved
                      if (status.toLowerCase() == 'approved')
                        _buildInfoRow(
                          Icons.attach_money,
                          'Claimed Money',
                          claimed ? 'Yes' : 'No',
                        ),
                      const SizedBox(height: 20),
                      // Deceased Info with age
                      FutureBuilder<Map<String, dynamic>>(
                        future: getDeceasedInfo(claim),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const SizedBox.shrink();
                          final deceased = snapshot.data!;
                          final dob = (deceased['dob'] ?? '').toString();
                          final dod = (deceased['date_of_death'] ?? '')
                              .toString();
                          final age = _computeAge(dob, dod);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInfoRow(
                                Icons.account_circle,
                                'Deceased',
                                deceased['name'],
                              ),
                              if (dob.isNotEmpty)
                                _buildInfoRow(Icons.cake, 'Date of Birth', dob),
                              if (dod.isNotEmpty)
                                _buildInfoRow(
                                  Icons.event,
                                  'Date of Death',
                                  dod,
                                ),
                              if (age != null)
                                _buildInfoRow(
                                  Icons.hourglass_bottom,
                                  'Age',
                                  '$age years',
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      // Death Certificate Button
                      if ((claim['death_certificate_url'] ?? '').toString().isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.description, size: 20),
                            label: const Text('View Death Certificate'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () async {
                              final url = claim['death_certificate_url'].toString();
                              final isImage = url.endsWith('.jpg') || url.endsWith('.jpeg') || url.endsWith('.png');
                              final isPdf = url.endsWith('.pdf');

                              if (isImage) {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => Dialog(
                                    backgroundColor: Colors.black,
                                    insetPadding: const EdgeInsets.all(12),
                                    child: PhotoView(
                                      imageProvider: NetworkImage(url),
                                      backgroundDecoration: const BoxDecoration(
                                        color: Colors.black,
                                      ),
                                      minScale: PhotoViewComputedScale.contained,
                                      maxScale: PhotoViewComputedScale.covered * 3,
                                    ),
                                  ),
                                );
                              } else if (isPdf) {
                                final tempDir = await getTemporaryDirectory();
                                final filePath = '${tempDir.path}/death_cert.pdf';
                                final response = await http.get(Uri.parse(url));
                                final file = File(filePath);
                                await file.writeAsBytes(response.bodyBytes);

                                showDialog(
                                  context: context,
                                  builder: (ctx) => Dialog(
                                    backgroundColor: Colors.black,
                                    insetPadding: const EdgeInsets.all(12),
                                    child: Stack(
                                      children: [
                                        PhotoView(
                                          imageProvider: NetworkImage(url),
                                          backgroundDecoration: const BoxDecoration(
                                            color: Colors.black,
                                          ),
                                          minScale: PhotoViewComputedScale.contained,
                                          maxScale: PhotoViewComputedScale.covered * 3,
                                        ),
                                        Positioned(
                                          top: 12,
                                          right: 12,
                                          child: IconButton(
                                            icon: const Icon(Icons.close, color: Colors.white, size: 24),
                                            onPressed: () => Navigator.of(ctx).pop(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              } else {
                                if (await canLaunchUrl(Uri.parse(url))) {
                                  await launchUrl(
                                    Uri.parse(url),
                                    mode: LaunchMode.externalApplication,
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Could not open file.'),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      // Add this block below for valid_ids_url
                      if ((claim['valid_ids_url'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.credit_card, size: 20),
                              label: const Text('View Valid IDs'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () async {
                                final url = claim['valid_ids_url'].toString();
                                final isImage = url.endsWith('.jpg') || url.endsWith('.jpeg') || url.endsWith('.png');
                                final isPdf = url.endsWith('.pdf');

                                if (isImage) {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => Dialog(
                                      backgroundColor: Colors.black,
                                      insetPadding: const EdgeInsets.all(12),
                                      child: PhotoView(
                                        imageProvider: NetworkImage(url),
                                        backgroundDecoration: const BoxDecoration(
                                          color: Colors.black,
                                        ),
                                        minScale: PhotoViewComputedScale.contained,
                                        maxScale: PhotoViewComputedScale.covered * 3,
                                      ),
                                    ),
                                  );
                                } else if (isPdf) {
                                  final tempDir = await getTemporaryDirectory();
                                  final filePath = '${tempDir.path}/valid_ids.pdf';
                                  final response = await http.get(Uri.parse(url));
                                  final file = File(filePath);
                                  await file.writeAsBytes(response.bodyBytes);

                                  showDialog(
                                    context: context,
                                    builder: (ctx) => Dialog(
                                      backgroundColor: Colors.black,
                                      insetPadding: const EdgeInsets.all(12),
                                      child: Stack(
                                        children: [
                                          PhotoView(
                                            imageProvider: NetworkImage(url),
                                            backgroundDecoration: const BoxDecoration(
                                              color: Colors.black,
                                            ),
                                            minScale: PhotoViewComputedScale.contained,
                                            maxScale: PhotoViewComputedScale.covered * 3,
                                          ),
                                          Positioned(
                                            top: 12,
                                            right: 12,
                                            child: IconButton(
                                              icon: const Icon(Icons.close, color: Colors.white, size: 24),
                                              onPressed: () => Navigator.of(ctx).pop(),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                } else {
                                  if (await canLaunchUrl(Uri.parse(url))) {
                                    await launchUrl(
                                      Uri.parse(url),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Could not open file.'),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ),
                        ),
                      if (status.toLowerCase() == 'approved')
                        Padding(
                          padding: const EdgeInsets.only(top: 10.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _updating
                                  ? null
                                  : () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text(claimed ? 'Mark as Not Claimed?' : 'Mark as Claimed?'),
                                        content: Text(
                                          claimed
                                              ? 'Are you sure you want to mark this claim as NOT claimed?'
                                              : 'Are you sure you want to mark this claim as claimed?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(ctx).pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () => Navigator.of(ctx).pop(true),
                                            child: const Text('Confirm'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      _updateClaimed(claim['id'].toString(), !claimed, claim['claimedmoney']);
                                      Navigator.pop(context);
                                    }
                                  },
                              icon: Icon(claimed ? Icons.money_off : Icons.payments),
                              label: Text(claimed ? 'Mark Not Claimed' : 'Mark Claimed'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                side: BorderSide(color: claimed ? Colors.grey : kAccent),
                                foregroundColor: claimed ? Colors.grey.shade800 : kAccent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              // Actions
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: _bottomSheetActions(status, claim),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: Colors.grey.shade700),
          ),
          const SizedBox(width: 12),
          Text(
            '$label:',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomSheetActions(String status, Map<String, dynamic> claim) {
    final sLower = status.toLowerCase();
    final id = claim['id'].toString();
    final claimed = _isClaimed(claim['claimedmoney']); // <— existing

    if (sLower == 'pending') {
      // Only Approve/Reject in Pending
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _updating
                  ? null
                  : () async {
                  // Prompt for amount before approving
                  final TextEditingController amountController = TextEditingController();
                  final parentContext = context;
                  final fullName = _userMap[claim['user_id']?.toString()]?['full_name'] ?? 'Member';

                  // Fetch secretary_id before showing the dialog
                  final unit = await supabase
                      .from('dayung_units')
                      .select('secretary_id')
                      .eq('id', claim['dayung_unit_id'])
                      .maybeSingle();
                  final secretaryId = unit?['secretary_id'];

                  final result = await showDialog<double>(
                    context: parentContext,
                    builder: (dialogContext) => AlertDialog(
                      title: Text('Contribution Amount for $fullName'),
                      content: TextField(
                        controller: amountController,
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          prefixIcon: Padding(
                            padding: EdgeInsets.only(left: 12, right: 8), // <-- Not a const constructor
                            child: Text('₱', style: TextStyle(fontSize: 20)),
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, null),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            final amount = double.tryParse(amountController.text);
                            if (amount == null) {
                              ScaffoldMessenger.of(parentContext).showSnackBar(
                                const SnackBar(content: Text('Please enter a valid amount.')),
                              );
                              return;
                            }
                            Navigator.pop(dialogContext, amount);
                          },
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  );

                  if (result != null) {
                    showDialog(
                      context: parentContext,
                      barrierDismissible: false,
                      builder: (_) => const Center(child: CircularProgressIndicator()),
                    );
                    try {
                      // Save set_amount
                      await supabase.from('set_amount').insert({
                        'userdeceased': claim['user_id'],
                        'payment_id': claim['id'],
                        'amount': result,
                        'secretary_id': secretaryId,
                        'dayung_unit_id': claim['dayung_unit_id'],
                      });

                      // Prepare death_notices data (same as before)
                      final userId = claim['user_id'];
                      final beneficiaryId = claim['beneficiary_id'];
                      final deathCert = claim['death_certificate_url'];
                      final dayungId = claim['dayung_unit_id'];
                      final dod = claim['date_of_death'];
                      final deceasedType = beneficiaryId != null ? 'beneficiary' : 'member';

                      // Fetch user/beneficiary info for name/dob
                      Map<String, dynamic>? user;
                      Map<String, dynamic>? ben;
                      if (beneficiaryId != null) {
                        ben = await supabase
                            .from('beneficiaries')
                            .select('full_name, dob, user_id')
                            .eq('id', beneficiaryId)
                            .maybeSingle();
                      } else {
                        user = await supabase
                            .from('users')
                            .select('full_name, dob')
                            .eq('id', userId)
                            .maybeSingle();
                      }
                      final name = beneficiaryId != null
                          ? (ben?['full_name'] ?? '')
                          : (user?['full_name'] ?? '');
                      final dob = beneficiaryId != null
                          ? (ben?['dob'])
                          : (user?['dob']);
                      final computedAge = (() {
                        if (dob == null || dod == null) return null;
                        final b = DateTime.tryParse(dob.toString());
                        final d = DateTime.tryParse(dod.toString());
                        if (b == null || d == null) return null;
                        var age = d.year - b.year;
                        if (d.month < b.month || (d.month == b.month && d.day < b.day)) age--;
                        return age;
                      })();

                      // Optionally, fetch vigil location/barangay if needed
                      final barangay = null;
                      final latitude = null;
                      final longitude = null;

                      // Insert into death_notices
                      await supabase.from('death_notices').insert({
                        if (beneficiaryId != null) 'beneficiary_id': beneficiaryId,
                        'user_id': beneficiaryId != null ? (ben?['user_id'] ?? userId) : userId,
                        'name': name,
                        'date_of_death': dod?.toString().split('T').first,
                        'death_certificate_url': deathCert,
                        'dayung_unit_id': dayungId,
                        'deceased_type': deceasedType,
                        'barangay': barangay,
                        'latitude': latitude,
                        'longitude': longitude,
                        'dob': dob?.toString().split('T').first,
                        if (computedAge != null) 'deceased_age': computedAge,
                      });

                      // --- ADD THIS BLOCK ---
                      final approvedApplications = await supabase
                          .from('applications')
                          .select('user_id')
                          .eq('dayung_unit_id', claim['dayung_unit_id'])
                          .eq('status', 'approved');

                      final now = DateTime.now().toIso8601String();
                      final notificationBody =
                          '$fullName passed away. Amount: ₱${result.toStringAsFixed(2)}';

                      // Insert notification for each approved user
                      for (final app in List<Map<String, dynamic>>.from(approvedApplications)) {
                        await supabase.from('notifications').insert({
                          'recipient_id': app['user_id'],
                          'body': notificationBody,
                          'type': 'announcement',
                          'title': 'Payment Reminder',
                          'dayung_unit_id': claim['dayung_unit_id'],
                          'read_at': null,
                          'created_at': now,
                          'sender_id': secretaryId,
                        });
                      }

                      // Insert into payments table for each member who needs to pay
                      for (final app in List<Map<String, dynamic>>.from(approvedApplications)) {
                        await supabase.from('payments').insert({
                          'user_id': app['user_id'],
                          'userdeceased': claim['user_id'],
                          'dayung_unit_id': claim['dayung_unit_id'],
                          'amount': result,
                          'status': 'unpaid',
                          'created_at': now,
                        });
                      }
                      // --- END BLOCK ---

                      Navigator.of(parentContext, rootNavigator: true).pop(); // Close loading
                      // Now approve the claim
                      _updateStatus(id, 'Approved');
                      Navigator.pop(context);
                    } catch (e) {
                      Navigator.of(parentContext, rootNavigator: true).pop(); // Close loading
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        SnackBar(content: Text('Failed to save amount: $e')),
                      );
                    }
                  }
                },
              icon: const Icon(Icons.check_circle, size: 20),
              label: const Text("Approve"),
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _updating
                  ? null
                  : () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Reject Claim?'),
                        content: const Text('Are you sure you want to reject this claim?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Reject'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      _updateStatus(id, 'Rejected');
                      Navigator.pop(context);
                    }
                  },
              icon: const Icon(Icons.cancel, size: 20),
              label: const Text("Reject"),
              style: ElevatedButton.styleFrom(
                backgroundColor: kDanger,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      );
    }

  

   // Rejected: remove Set Pending button, show nothing or SizedBox
    return const SizedBox.shrink();
  }
}
