import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:capstone_app/utils/input_safety.dart';
import 'package:capstone_app/utils/supabase_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:photo_view/photo_view.dart';
import 'package:flutter/services.dart';
import 'package:capstone_app/utils/theme_surface.dart';

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

List<Map<String, dynamic>> filterPaymentRecipientsForDeceasedClaim({
  required List<Map<String, dynamic>> approvedApplications,
  required List<Map<String, dynamic>> membershipFeePayments,
  required String? deceasedUserId,
}) {
  final blockedUserIds = <String>{};

  for (final payment in membershipFeePayments) {
    final userId = (payment['user_id'] ?? '').toString();
    final status = (payment['status'] ?? '').toString().toLowerCase();
    final type = (payment['type'] ?? '').toString().toLowerCase();
    if (userId.isEmpty) continue;
    if (type == 'membership fee' && status == 'unpaid') {
      blockedUserIds.add(userId);
    }
  }

  return approvedApplications.where((app) {
    final appUserId = (app['user_id'] ?? '').toString();
    if (appUserId.isEmpty) return false;
    if (deceasedUserId != null && appUserId == deceasedUserId) return false;
    return !blockedUserIds.contains(appUserId);
  }).toList();
}

class SecretaryClaimsPage extends StatefulWidget {
  const SecretaryClaimsPage({super.key});
  @override
  State<SecretaryClaimsPage> createState() => _SecretaryClaimsPageState();
}

class _SecretaryClaimsPageState extends State<SecretaryClaimsPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  RealtimeChannel? _claimsChannel;

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
      _resubscribeRealtime(unitId: id);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentId = context.watch<DayungUnitProvider>().currentUnitId;
    if (currentId != _lastUnitId) {
      _lastUnitId = currentId;
      _resubscribeRealtime(unitId: currentId);
      _fetchClaims(forUnitId: currentId);
    }
  }

  void _resubscribeRealtime({int? unitId}) {
    try {
      _claimsChannel?.unsubscribe();
      if (_claimsChannel != null) {
        supabase.removeChannel(_claimsChannel!);
      }
    } catch (_) {}
    _claimsChannel = null;
    if (unitId != null) {
      _subscribeRealtime(unitId: unitId);
    }
  }

  void _subscribeRealtime({required int unitId}) {
    _claimsChannel = supabase.channel('secretary_claims_$unitId');

    void refreshClaims(PostgresChangePayload payload) {
      if (!mounted) return;
      final record =
          (payload.newRecord.isNotEmpty
                  ? payload.newRecord
                  : payload.oldRecord)
              as Map<String, dynamic>?;
      final recordUnitId = record?['dayung_unit_id'];
      final changedUnitId = recordUnitId is int
          ? recordUnitId
          : int.tryParse('$recordUnitId');
      if (changedUnitId != unitId) return;
      _fetchClaims(forUnitId: unitId, tabSwitch: true);
    }

    _claimsChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'claims',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'dayung_unit_id',
            value: unitId,
          ),
          callback: refreshClaims,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'dayung_unit_id',
            value: unitId,
          ),
          callback: refreshClaims,
        )
        .subscribe();
  }

  void _updateClaimLocally(String claimId, dynamic claimedValue) {
    final index = _claims.indexWhere((claim) => claim['id'].toString() == claimId);
    if (index < 0 || !mounted) return;
    final updatedClaim = Map<String, dynamic>.from(_claims[index])
      ..['claimedmoney'] = claimedValue;
    setState(() {
      _claims[index] = updatedClaim;
    });
  }

  Future<void> _fetchClaims({int? forUnitId, bool tabSwitch = false}) async {
    final unitId =
        forUnitId ??
        _lastUnitId ??
        context.read<DayungUnitProvider>().currentUnitId;

    if (unitId == null) {
      throw Exception('Invalid dayung_unit_id: $unitId');
    }

    _lastUnitId = unitId;

    if (!tabSwitch) {
      if (mounted) setState(() => _loading = true);
    }

    try {
      // Approved members of this unit
      final apps = await supabase
          .from('applications')
          .select('user_id, user:users(id, full_name, profile_url, valid_id)')
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
          'valid_id': (u['valid_id'] ?? '').toString(),
          'dayung_unit_id': unitId,
        };
      }

      final statusTitle = _tabs[_tabController.index];

      final tagged = await supabase
          .from('claims')
          .select(
            'id, user_id, title, description, status, date_submitted, death_certificate_url, beneficiary_id, date_of_death, dayung_unit_id, claimedmoney, valid_ids_url',
          )
          .eq('dayung_unit_id', unitId)
          .eq('status', statusTitle) // <-- add this line
          .order('date_submitted', ascending: false);

      final taggedList = List<Map<String, dynamic>>.from(tagged);

      List<Map<String, dynamic>> legacyList = [];
      if (allowedUserIds.isNotEmpty) {
        final legacy = await supabase
            .from('claims')
            .select(
              'id, user_id, title, description, status, date_submitted, '
              'death_certificate_url, beneficiary_id, date_of_death, dayung_unit_id, claimedmoney, valid_ids_url', // <— added
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

  String _philippinesNowIso() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final date = DateFormat('yyyy-MM-ddTHH:mm:ss').format(now);
    final milliseconds = now.millisecond.toString().padLeft(3, '0');
    final microseconds = now.microsecond.toString().padLeft(3, '0');
    return '$date.$milliseconds$microseconds+08:00';
  }

  String _formatDefaultContributionAmount(dynamic value) {
    if (value == null) return '';
    final raw = value.toString().trim();
    if (raw.isEmpty) return '';

    final cleaned = raw.replaceAll(RegExp(r'[^0-9.-]'), '');
    if (cleaned.isEmpty) return '';

    final parsed = double.tryParse(cleaned);
    return parsed == null ? raw : parsed.toStringAsFixed(2);
  }

  Future<String> _loadDefaultContributionAmount(int? unitId) async {
    if (unitId == null) return '';

    try {
      final row = await supabase
          .from('dayung_rules')
          .select('exactamountformembership')
          .eq('dayung_unit_id', unitId)
          .maybeSingle();

      return _formatDefaultContributionAmount(row?['exactamountformembership']);
    } catch (_) {
      return '';
    }
  }

  int? _resolveClaimUnitId(Map<String, dynamic> claim) {
    final claimUnitId = claim['dayung_unit_id'];
    if (claimUnitId is int) return claimUnitId;
    final parsedClaimUnitId = int.tryParse('$claimUnitId');
    return parsedClaimUnitId ??
        _lastUnitId ??
        context.read<DayungUnitProvider>().currentUnitId;
  }

  Future<void> _updateClaimed(
    String claimId,
    bool newValue,
    dynamic existingColumnValue,
    Map<String, dynamic> claim,
  ) async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      final resolvedUnitId = _resolveClaimUnitId(claim);
      if (resolvedUnitId == null) {
        throw Exception('Unable to resolve dayung_unit_id for claim $claimId');
      }

      final storeVal = _storeClaimedValue(newValue, existingColumnValue);
      final claimedAt = _philippinesNowIso();
      final paymentUpdate = <String, dynamic>{
        'is_due': newValue,
        'due_date': newValue ? claimedAt : null,
        'is_claimed': newValue,
      };

      await supabase
          .from('claims')
          .update({'claimedmoney': storeVal})
          .eq('id', claimId);
      _updateClaimLocally(claimId, storeVal);

      await supabase
          .from('payments')
          .update(paymentUpdate)
          .eq('dayung_unit_id', resolvedUnitId)
          .eq('userdeceased', (claim['user_id'] ?? '').toString());

      await _fetchClaims();
    } catch (e) {
      debugPrint("Error updating claimedmoney: $e");
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  void dispose() {
    try {
      _claimsChannel?.unsubscribe();
      if (_claimsChannel != null) {
        supabase.removeChannel(_claimsChannel!);
      }
    } catch (_) {}
    _claimsChannel = null;
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
      backgroundColor: dayungPageBackground(context),
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
                              color: kBorderColor.withValues(alpha: 0.3),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
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
                                    color: kBorderColor.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.05,
                                      ),
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
                                      ).withValues(alpha: 0.6),
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
                        color: kPrimary.withValues(alpha: 0.3),
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

    return InkWell(
      onTap: () => _showDetail(claim),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
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
                Icon(_statusIcon(status), color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: kNeutralText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  date,
                  style: const TextStyle(
                    fontSize: 12,
                    color: kSubtleText,
                  ),
                ),
              ],
            ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 13,
                  color: kSubtleText,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 6),
            FutureBuilder<Map<String, dynamic>>(
              future: getDeceasedInfo(claim),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final deceased = snapshot.data!;
                return Text(
                  'Deceased: ${deceased['name']}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: kSubtleText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              },
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
                        color: color.withValues(alpha: 0.1),
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
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
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
                              final messenger = ScaffoldMessenger.of(context);
                              final raw = claim['death_certificate_url']
                                  .toString();
                              // Debug log raw value
                              debugPrint('Death Certificate RAW: $raw');
                              final url = await resolveSupabaseStorageUrl(
                                raw,
                                client: supabase,
                              );
                              // Debug log resolved URL
                              debugPrint('Death Certificate RESOLVED URL: $url');
                              if (!mounted) return;
                              if (url == null) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Could not open file.'),
                                  ),
                                );
                                return;
                              }
                              final isImage = storageLooksLikeImage(url);
                              final isPdf = storageLooksLikePdf(url);
                              if (isImage) {
                                showDialog(
                                  context: context,
                                  barrierDismissible: true,
                                  builder: (ctx) => Dialog(
                                    backgroundColor: Colors.transparent,
                                    insetPadding: const EdgeInsets.all(16),
                                    child: Stack(
                                      children: [
                                        Container(
                                          width: 350,
                                          height: 350,
                                          decoration: BoxDecoration(
                                            color: Colors.black,
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(16),
                                            child: PhotoView(
                                              imageProvider: NetworkImage(url),
                                              backgroundDecoration: const BoxDecoration(
                                                color: Colors.black,
                                              ),
                                              minScale: PhotoViewComputedScale.contained,
                                              maxScale: PhotoViewComputedScale.covered * 3,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          child: GestureDetector(
                                            onTap: () => Navigator.of(ctx).pop(),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.7),
                                                shape: BoxShape.circle,
                                              ),
                                              margin: const EdgeInsets.all(8),
                                              padding: const EdgeInsets.all(6),
                                              child: const Icon(Icons.close, color: Colors.white, size: 26),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              } else if (isPdf) {
                                final fileUri = Uri.parse(url);
                                await launchUrl(
                                  fileUri,
                                  mode: LaunchMode.externalApplication,
                                );
                              } else {
                                final fileUri = Uri.parse(url);
                                if (await canLaunchUrl(fileUri)) {
                                  await launchUrl(
                                    fileUri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                } else {
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Could not open file.'),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ),

                      // Valid ID Button (should be directly below Death Certificate)
                      if ((claim['valid_ids_url'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.credit_card, size: 20),
                              label: const Text('View Valid ID'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final raw = claim['valid_ids_url'].toString();
                                debugPrint('Valid ID RAW: $raw');
                                final url = await resolveSupabaseStorageUrl(
                                  raw,
                                  client: supabase,
                                );
                                debugPrint('Valid ID RESOLVED URL: $url');
                                if (!mounted) return;
                                if (url == null) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('Could not open file. (raw: $raw)'),
                                    ),
                                  );
                                  return;
                                }
                                final isImage = storageLooksLikeImage(url);
                                final isPdf = storageLooksLikePdf(url);
                                if (isImage) {
                                  showDialog(
                                    context: context,
                                    barrierDismissible: true,
                                    builder: (ctx) => Dialog(
                                      backgroundColor: Colors.transparent,
                                      insetPadding: const EdgeInsets.all(16),
                                      child: Stack(
                                        children: [
                                          Container(
                                            width: 350,
                                            height: 350,
                                            decoration: BoxDecoration(
                                              color: Colors.black,
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(16),
                                              child: PhotoView(
                                                imageProvider: NetworkImage(url),
                                                backgroundDecoration: const BoxDecoration(
                                                  color: Colors.black,
                                                ),
                                                minScale: PhotoViewComputedScale.contained,
                                                maxScale: PhotoViewComputedScale.covered * 3,
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 0,
                                            right: 0,
                                            child: GestureDetector(
                                              onTap: () => Navigator.of(ctx).pop(),
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withValues(alpha: 0.7),
                                                  shape: BoxShape.circle,
                                                ),
                                                margin: const EdgeInsets.all(8),
                                                padding: const EdgeInsets.all(6),
                                                child: const Icon(Icons.close, color: Colors.white, size: 26),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                } else if (isPdf) {
                                  final fileUri = Uri.parse(url);
                                  await launchUrl(
                                    fileUri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                } else {
                                  final fileUri = Uri.parse(url);
                                  if (await canLaunchUrl(fileUri)) {
                                    await launchUrl(
                                      fileUri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  } else {
                                    if (!mounted) return;
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text('Could not open file. (resolved: $url, raw: $raw)'),
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
                                      final navigator = Navigator.of(context);
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: Text(
                                            claimed
                                                ? 'Mark as Not Claimed?'
                                                : 'Mark as Claimed?',
                                          ),
                                          content: Text(
                                            claimed
                                                ? 'Are you sure you want to mark this claim as NOT claimed?'
                                                : 'Are you sure you want to mark this claim as claimed?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(false),
                                              child: const Text('Cancel'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(true),
                                              child: const Text('Confirm'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await _updateClaimed(
                                          claim['id'].toString(),
                                          !claimed,
                                          claim['claimedmoney'],
                                          claim,
                                        );
                                        if (!mounted) return;
                                        navigator.pop();
                                      }
                                    },
                              icon: Icon(
                                claimed ? Icons.money_off : Icons.payments,
                              ),
                              label: Text(
                                claimed ? 'Mark Not Claimed' : 'Mark Claimed',
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                side: BorderSide(
                                  color: claimed ? Colors.grey : kAccent,
                                ),
                                foregroundColor: claimed
                                    ? Colors.grey.shade800
                                    : kAccent,
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
                      final unitId = int.tryParse('${claim['dayung_unit_id']}');
                      if (!mounted) return;
                      final messenger = ScaffoldMessenger.of(context);
                      final rootNavigator = Navigator.of(
                        context,
                        rootNavigator: true,
                      );
                      final sheetNavigator = Navigator.of(context);
                      final fullName =
                          _userMap[claim['user_id']
                              ?.toString()]?['full_name'] ??
                          'Member';
                      final defaultAmount = await _loadDefaultContributionAmount(unitId);
                      final TextEditingController amountController =
                          TextEditingController(text: defaultAmount);

                      // Fetch secretary_id before showing the dialog
                      final unit = await supabase
                          .from('dayung_units')
                          .select('secretary_id')
                          .eq('id', claim['dayung_unit_id'])
                          .maybeSingle();
                      final secretaryId = unit?['secretary_id'];
                      if (!mounted) return;

                      final result = await showDialog<double>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: Text('Contribution Amount for $fullName'),
                          content: TextField(
                            controller: amountController,
                            keyboardType: TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'),
                              ),
                              LengthLimitingTextInputFormatter(12),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Amount',
                              prefixIcon: Padding(
                                padding: EdgeInsets.only(
                                  left: 12,
                                  right: 8,
                                ), // <-- Not a const constructor
                                child: Text(
                                  '₱',
                                  style: TextStyle(fontSize: 20),
                                ),
                              ),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, null),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                final amount = double.tryParse(
                                  AppInputSecurity.sanitizePlainText(
                                    amountController.text,
                                    maxLength: 12,
                                  ).replaceAll(',', ''),
                                );
                                if (amount == null) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please enter a valid amount.',
                                      ),
                                    ),
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
                        if (!mounted) return;
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) =>
                              const Center(child: CircularProgressIndicator()),
                        );
                        try {
                          await supabase
                              .from('claims')
                              .update({
                                'amount': result,
                                'secretary_id': secretaryId,
                                'datesetamount': DateTime.now()
                                    .toIso8601String(),
                                'status': 'Approved',
                              })
                              .eq('id', claim['id']);

                          final userId = claim['user_id'];
                          final beneficiaryId = claim['beneficiary_id'];
                          final deceasedType = beneficiaryId != null
                              ? 'beneficiary'
                              : 'member';
                          String deceasedName = '';
                          if (deceasedType == 'beneficiary' &&
                              beneficiaryId != null) {
                            final ben = await supabase
                                .from('beneficiaries')
                                .select('full_name')
                                .eq('id', beneficiaryId)
                                .maybeSingle();
                            deceasedName = (ben?['full_name'] ?? '').toString();
                          } else {
                            final user = await supabase
                                .from('users')
                                .select('full_name')
                                .eq('id', userId)
                                .maybeSingle();
                            deceasedName = (user?['full_name'] ?? '')
                                .toString();
                          }

                          final approvedApplications = await supabase
                              .from('applications')
                              .select('user_id')
                              .eq('dayung_unit_id', claim['dayung_unit_id'])
                              .eq('status', 'approved');

                          final approvedApplicationList =
                              List<Map<String, dynamic>>.from(
                                approvedApplications,
                              );
                          final approvedUserIds = approvedApplicationList
                              .map((app) => (app['user_id'] ?? '').toString())
                              .where((id) => id.isNotEmpty)
                              .toList();

                          List<Map<String, dynamic>> membershipFeePayments = [];
                          if (approvedUserIds.isNotEmpty) {
                            final payments = await supabase
                                .from('payments')
                                .select('user_id, status, type')
                                .eq('dayung_unit_id', claim['dayung_unit_id'])
                                .eq('type', 'membership fee')
                                .inFilter('user_id', approvedUserIds);
                            membershipFeePayments = List<Map<String, dynamic>>.from(
                              payments,
                            );
                          }

                          final deceasedUserId = userId?.toString();
                          final paymentRecipients =
                              filterPaymentRecipientsForDeceasedClaim(
                                approvedApplications: approvedApplicationList,
                                membershipFeePayments: membershipFeePayments,
                                deceasedUserId: deceasedType == 'member'
                                    ? deceasedUserId
                                    : null,
                              );

                          final now = DateTime.now().toIso8601String();
                          final notificationBody =
                              '$fullName passed away. Amount: ₱${result.toStringAsFixed(2)}';

                          // Insert notification for each approved user
                          for (final app in approvedApplicationList) {
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

                          // Insert payments with deceased_name
                          for (final app in paymentRecipients) {
                            await supabase.from('payments').insert({
                              'user_id': app['user_id'],
                              'userdeceased': claim['user_id'],
                              'deceased_name': deceasedName,
                              'dayung_unit_id': claim['dayung_unit_id'],
                              'amount': result,
                              'is_due': false,
                              'due_date': null,
                              'status': 'unpaid',
                              'type': 'deceased_payment',
                              'created_at': now,
                            });
                          }

                          rootNavigator.pop();
                          _updateStatus(id, 'Approved');
                          sheetNavigator.pop();
                        } catch (e) {
                          rootNavigator.pop();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Failed to save amount: $e'),
                            ),
                          );
                        }
                      }
                    },
                    // Approve button sa Claim Deceased Member
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
                      final navigator = Navigator.of(context);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Reject Claim?'),
                          content: const Text(
                            'Are you sure you want to reject this claim?',
                          ),
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
                        navigator.pop();
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
