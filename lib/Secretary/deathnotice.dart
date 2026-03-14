import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:capstone_app/Secretary/secretary_ui.dart';
import 'package:capstone_app/utils/supabase_storage.dart';
import 'package:capstone_app/utils/input_safety.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geocoding/geocoding.dart';

const Color kPrimary = Color(0xFF3B82F6);
const Color kPrimaryDark = Color(0xFF1E40AF);
const Color kAccent = Color(0xFF10B981);
const Color kWarn = Color(0xFFF59E0B);
const Color kDanger = Color(0xFFEF4444);
const Color kBg = Color(0xFFF8FAFC);
const Color kCardBg = Color(0xFFFFFFFF);
const Color kSubText = Color(0xFF6B7280);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);

class CreateDeathNoticePage extends StatefulWidget {
  final int dayungUnitId;
  const CreateDeathNoticePage({super.key, required this.dayungUnitId});

  @override
  State<CreateDeathNoticePage> createState() => _CreateDeathNoticePageState();
}

class _CreateDeathNoticePageState extends State<CreateDeathNoticePage> {
  final supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _approvedClaims = [];
  bool _loading = true;
  String _search = '';
  String? _error;
  String? _submittingClaimKey;

  int get _memberClaimCount =>
      _approvedClaims.where((claim) => claim['beneficiary_id'] == null).length;

  int get _beneficiaryClaimCount =>
      _approvedClaims.where((claim) => claim['beneficiary_id'] != null).length;

  List<Map<String, dynamic>> get _visibleClaims {
    if (_search.isEmpty) return _approvedClaims;

    final query = _search.toLowerCase();
    return _approvedClaims.where((claim) {
      final isBeneficiary = claim['beneficiary_id'] != null;
      final name = isBeneficiary
          ? (claim['beneficiaries']?['full_name'] ?? '')
          : (claim['users']?['full_name'] ?? '');
      final submitted = (claim['date_submitted'] ?? '').toString();
      return name.toLowerCase().contains(query) ||
          submitted.toLowerCase().contains(query);
    }).toList();
  }

  void _clearSearch() {
    if (_search.isEmpty) return;
    _searchController.clear();
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final value = _searchController.text;
      if (value == _search) return;
      setState(() => _search = value);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fetchApprovedClaims();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchApprovedClaimsFallback() async {
    final approvedApplications = await supabase
        .from('applications')
        .select('user_id')
        .eq('dayung_unit_id', widget.dayungUnitId)
        .eq('status', 'approved')
        .timeout(const Duration(seconds: 8));

    final allowedUserIds = <String>{
      for (final app in List<Map<String, dynamic>>.from(approvedApplications))
        if (app['user_id'] != null) app['user_id'].toString(),
    }.toList();

    final tagged = await supabase
        .from('claims')
        .select(
          'id, user_id, title, description, status, date_submitted, '
          'death_certificate_url, beneficiary_id, date_of_death, dayung_unit_id, '
          'claimedmoney, vigil_latitude, vigil_longitude, vigil_barangay',
        )
        .eq('status', 'Approved')
        .eq('dayung_unit_id', widget.dayungUnitId)
        .order('date_submitted', ascending: false)
        .timeout(const Duration(seconds: 8));

    List<Map<String, dynamic>> legacyList = [];
    if (allowedUserIds.isNotEmpty) {
      final legacy = await supabase
          .from('claims')
          .select(
            'id, user_id, title, description, status, date_submitted, '
            'death_certificate_url, beneficiary_id, date_of_death, dayung_unit_id, '
            'claimedmoney, vigil_latitude, vigil_longitude, vigil_barangay',
          )
          .eq('status', 'Approved')
          .isFilter('dayung_unit_id', null)
          .inFilter('user_id', allowedUserIds)
          .order('date_submitted', ascending: false)
          .timeout(const Duration(seconds: 8));
      legacyList = List<Map<String, dynamic>>.from(legacy);
    }

    final merged = <String, Map<String, dynamic>>{};
    for (final claim in legacyList) {
      merged[claim['id'].toString()] = claim;
    }
    for (final claim in List<Map<String, dynamic>>.from(tagged)) {
      merged[claim['id'].toString()] = claim;
    }
    return merged.values.toList();
  }

  Future<Map<String, dynamic>> _resolveVigilLocation(
    Map<String, dynamic> claim,
  ) async {
    // Prefer submitter-provided vigil location
    final lat = claim['vigil_latitude'];
    final lng = claim['vigil_longitude'];
    final brgy = claim['vigil_barangay'];
    if (lat != null && lng != null) {
      return {
        'latitude': _toDouble(lat),
        'longitude': _toDouble(lng),
        'barangay': brgy,
      };
    }

    // Fallback: geocode the member address
    String? memberId = claim['user_id']?.toString();
    if (claim['beneficiary_id'] != null && memberId == null) {
      final ben = await supabase
          .from('beneficiaries')
          .select('user_id')
          .eq('id', claim['beneficiary_id'])
          .maybeSingle();
      memberId = ben?['user_id']?.toString();
    }
    if (memberId != null) {
      final u = await supabase
          .from('users')
          .select('address')
          .eq('id', memberId)
          .maybeSingle();
      final addr = (u?['address'] ?? '').toString().trim();
      if (addr.isNotEmpty) {
        try {
          final locs = await locationFromAddress(
            addr,
          ).timeout(const Duration(seconds: 6));
          if (locs.isNotEmpty) {
            final pms = await placemarkFromCoordinates(
              locs.first.latitude,
              locs.first.longitude,
            ).timeout(const Duration(seconds: 6));
            final barangay =
                (pms.isNotEmpty && (pms.first.subLocality?.isNotEmpty ?? false))
                ? pms.first.subLocality
                : null;
            return {
              'latitude': locs.first.latitude,
              'longitude': locs.first.longitude,
              'barangay': brgy ?? barangay,
            };
          }
        } on TimeoutException {
          return {'latitude': null, 'longitude': null, 'barangay': brgy};
        } catch (_) {}
      }
    }
    return {'latitude': null, 'longitude': null, 'barangay': brgy};
  }

  Future<void> _fetchApprovedClaims() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      List<Map<String, dynamic>> claims;
      try {
        final res = await supabase
            .rpc(
              'sec_list_approved_claims',
              params: {'p_unit_id': widget.dayungUnitId},
            )
            .timeout(const Duration(seconds: 8));
        claims = List<Map<String, dynamic>>.from(res);
      } on TimeoutException {
        claims = await _fetchApprovedClaimsFallback();
      } catch (_) {
        claims = await _fetchApprovedClaimsFallback();
      }

      final userIds = <String>{
        for (final c in claims)
          if (c['user_id'] != null) c['user_id'].toString(),
      }.toList();
      final benIds = <String>{
        for (final c in claims)
          if (c['beneficiary_id'] != null) c['beneficiary_id'].toString(),
      }.toList();

      final results = await Future.wait([
        supabase
            .from('death_notices')
            .select('user_id, beneficiary_id, deceased_type')
            .eq('dayung_unit_id', widget.dayungUnitId)
            .timeout(const Duration(seconds: 8)),
        userIds.isEmpty
            ? Future.value(<Map<String, dynamic>>[])
            : supabase
                  .from('users')
                  .select('id, full_name, dob, is_deceased, date_of_death')
                  .inFilter('id', userIds)
                  .timeout(const Duration(seconds: 8)),
        benIds.isEmpty
            ? Future.value(<Map<String, dynamic>>[])
            : supabase
                  .from('beneficiaries')
                  .select('id, full_name, dob, status, user_id')
                  .inFilter('id', benIds)
                  .timeout(const Duration(seconds: 8)),
      ]);

      final notices = results[0];

      // Separate sets by type to avoid hiding member claims when a beneficiary has a notice
      final deceasedMemberUserIds = {
        for (final n in List<Map<String, dynamic>>.from(notices))
          if ((n['deceased_type'] ?? '') == 'member' && n['user_id'] != null)
            n['user_id'].toString(),
      };
      final deceasedBenIds = {
        for (final n in List<Map<String, dynamic>>.from(notices))
          if ((n['deceased_type'] ?? '') == 'beneficiary' &&
              n['beneficiary_id'] != null)
            n['beneficiary_id'].toString(),
      };

      final userMap = <String, Map<String, dynamic>>{};
      for (final u in List<Map<String, dynamic>>.from(results[1])) {
        userMap[(u['id'] ?? '').toString()] = u;
      }

      final benMap = <String, Map<String, dynamic>>{};
      for (final b in List<Map<String, dynamic>>.from(results[2])) {
        benMap[(b['id'] ?? '').toString()] = b;
      }

      // 4) Assemble list with corrected skip logic
      final out = <Map<String, dynamic>>[];
      for (final c in claims) {
        final isBen = c['beneficiary_id'] != null;
        if (isBen) {
          final id = c['beneficiary_id']?.toString();
          if (id != null && deceasedBenIds.contains(id)) {
            continue; // only skip if that beneficiary already has a notice
          }
          out.add({
            ...c,
            'users': userMap[c['user_id']?.toString()],
            'beneficiaries': benMap[id],
          });
        } else {
          final uid = c['user_id']?.toString();
          if (uid != null && deceasedMemberUserIds.contains(uid)) {
            continue; // only skip if the MEMBER already has a member-type notice
          }
          out.add({...c, 'users': userMap[uid], 'beneficiaries': null});
        }
      }

      if (!mounted) return;
      setState(() {
        _approvedClaims = out;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load Create Death data: $e';
      });
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to load Create Death data: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredClaims = _visibleClaims;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            const SecretaryPageHeader(
              title: 'Create Death Notice',
              subtitle:
                  'Review approved claims and create verified death notices in one flow.',
              icon: Icons.person_off_rounded,
              usePaymentStyle: true,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchApprovedClaims,
                child: _loading
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        children: [
                          _buildToolbarCard(filteredClaims.length),
                          _buildEmptyState(
                            icon: Icons.hourglass_top_rounded,
                            title: 'Loading approved claims...',
                            message:
                                'Preparing the latest claims that are ready for death notice processing.',
                          ),
                        ],
                      )
                    : _error != null
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        children: [
                          _buildToolbarCard(filteredClaims.length),
                          _buildEmptyState(
                            icon: Icons.error_outline_rounded,
                            title: 'Could not load claim queue',
                            message: _error!,
                            action: OutlinedButton.icon(
                              onPressed: _fetchApprovedClaims,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Retry fetch'),
                            ),
                          ),
                        ],
                      )
                    : filteredClaims.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        children: [
                          _buildToolbarCard(filteredClaims.length),
                          _buildEmptyState(
                            icon: _search.isEmpty
                                ? Icons.assignment_turned_in_outlined
                                : Icons.search_off_rounded,
                            title: _search.isEmpty
                                ? 'No approved claims to process'
                                : 'No matching claims found',
                            message: _search.isEmpty
                                ? 'Approved claims will appear here when they are ready for a death notice.'
                                : 'Try another search term or clear the current filter.',
                            action: _search.isEmpty
                                ? null
                                : OutlinedButton.icon(
                                    onPressed: _clearSearch,
                                    icon: const Icon(
                                      Icons.filter_alt_off_rounded,
                                    ),
                                    label: const Text('Reset search'),
                                  ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        itemCount: filteredClaims.length + 1,
                        itemBuilder: (_, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _buildToolbarCard(filteredClaims.length),
                            );
                          }

                          final c = filteredClaims[i - 1];
                          final claimKey = _claimKey(c);
                          final isSubmitting = _submittingClaimKey == claimKey;
                          final isBeneficiary = c['beneficiary_id'] != null;
                          final deceased = isBeneficiary
                              ? c['beneficiaries']
                              : c['users'];
                          final name = deceased?['full_name'] ?? '';
                          final dob = deceased?['dob'];
                          final dod = c['date_of_death'];
                          final deathCert = c['death_certificate_url'];
                          final age = (dob != null && dod != null)
                              ? _calculateAge(
                                  DateTime.parse(dob),
                                  DateTime.parse(dod),
                                )
                              : null;
                          final submitted = _formatDate(
                            c['date_submitted'] ?? c['created_at'],
                          );
                          final tone = isBeneficiary
                              ? const Color(0xFF7C3AED)
                              : kPrimary;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: kCardBg,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: kPrimary.withValues(alpha: 0.08),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundColor: tone.withValues(
                                        alpha: 0.12,
                                      ),
                                      child: Icon(
                                        Icons.person_rounded,
                                        color: tone,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 18,
                                              color: kPrimaryDark,
                                              fontFamily: 'Montserrat',
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Submitted: $submitted',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: kSubText,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tone.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        isBeneficiary
                                            ? 'Beneficiary'
                                            : 'Member',
                                        style: TextStyle(
                                          color: tone,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    _infoPill(
                                      Icons.cake_rounded,
                                      'DOB: ${_formatDate(dob)}',
                                    ),
                                    _infoPill(
                                      Icons.event_rounded,
                                      'Date of Death: ${_formatDate(dod)}',
                                    ),
                                    if (age != null)
                                      _infoPill(
                                        Icons.badge_rounded,
                                        'Age: $age',
                                      ),
                                  ],
                                ),
                                if (deathCert != null &&
                                    deathCert.toString().isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  TextButton.icon(
                                    icon: const Icon(
                                      Icons.picture_as_pdf_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('View death certificate'),
                                    onPressed: () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      final url =
                                          await resolveSupabaseStorageUrl(
                                            deathCert.toString(),
                                            client: supabase,
                                          );
                                      if (!mounted) return;
                                      if (url == null) {
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Could not open file.',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
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
                                            content: Text(
                                              'Could not open file.',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: kPrimaryDark,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: isSubmitting
                                        ? null
                                        : () => _showAmountDialogAndSetDeceased(
                                            c,
                                          ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: kPrimary,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size.fromHeight(46),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    icon: isSubmitting
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.check_circle_rounded,
                                            size: 18,
                                          ),
                                    label: Text(
                                      isSubmitting
                                          ? 'Saving...'
                                          : 'Create death notice',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarCard(int filteredCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kPrimary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _overviewStat(
                icon: Icons.description_rounded,
                label: 'Total',
                value: '${_approvedClaims.length}',
                tone: kPrimary,
              ),
              _overviewStat(
                icon: Icons.person_off_rounded,
                label: 'Members',
                value: '$_memberClaimCount',
                tone: kPrimaryDark,
              ),
              _overviewStat(
                icon: Icons.family_restroom_rounded,
                label: 'Beneficiaries',
                value: '$_beneficiaryClaimCount',
                tone: const Color(0xFF7C3AED),
              ),
              _overviewStat(
                icon: Icons.search_rounded,
                label: 'Shown',
                value: '$filteredCount',
                tone: kAccent,
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search member, beneficiary, or date submitted',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: _clearSearch,
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            style: const TextStyle(fontSize: 15, color: kNeutralText),
          ),
        ],
      ),
    );
  }

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
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: tone),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: kNeutralText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tone,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kPrimary.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: kPrimaryDark),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: kNeutralText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kPrimary.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 38, color: kPrimary),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kPrimaryDark,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: kSubText),
          ),
          if (action != null) ...[const SizedBox(height: 14), action],
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    final d = date is DateTime ? date : DateTime.parse(date.toString());
    return DateFormat('yyyy-MM-dd').format(d);
  }

  String? _dateOnly(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return DateFormat('yyyy-MM-dd').format(v);
    final s = v.toString();
    return s.contains('T') ? s.split('T').first : s;
  }

  int _calculateAge(DateTime dob, DateTime dod) {
    int age = dod.year - dob.year;
    if (dod.month < dob.month ||
        (dod.month == dob.month && dod.day < dob.day)) {
      age--;
    }
    return age;
  }

  int? _ageFromDobDod(dynamic dob, dynamic dod) {
    if (dob == null || dod == null) return null;
    final b = DateTime.tryParse(dob.toString());
    final d = DateTime.tryParse(dod.toString());
    if (b == null || d == null) return null;
    var age = d.year - b.year;
    if (d.month < b.month || (d.month == b.month && d.day < b.day)) age--;
    return age;
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  String _claimKey(Map<String, dynamic> claim) {
    if (claim['beneficiary_id'] != null) {
      return 'beneficiary:${claim['beneficiary_id']}';
    }
    return 'member:${claim['user_id']}';
  }

  Future<Map<String, dynamic>> _setDeceased(Map<String, dynamic> claim) async {
    final messenger = ScaffoldMessenger.of(context);
    final isBeneficiary = claim['beneficiary_id'] != null;
    final dod = claim['date_of_death'];
    final deathCert = claim['death_certificate_url'];
    final dayungId = claim['dayung_unit_id'] ?? widget.dayungUnitId;

    final Map<String, dynamic>? user = claim['users'] as Map<String, dynamic>?;
    final Map<String, dynamic>? ben =
        claim['beneficiaries'] as Map<String, dynamic>?;

    final String name = isBeneficiary
        ? (ben?['full_name'] ?? '')
        : (user?['full_name'] ?? '');
    final dynamic dob = isBeneficiary
        ? (ben != null ? ben['dob'] : null)
        : user?['dob'];
    final int? computedAge = _ageFromDobDod(dob, dod);

    if (name.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Missing full name. Please check the record.'),
        ),
      );
      throw StateError('Missing full name. Please check the record.');
    }

    try {
      final vigil = await _resolveVigilLocation(claim);
      final barangay = vigil['barangay'];
      final latitude = vigil['latitude'];
      final longitude = vigil['longitude'];

      if (isBeneficiary) {
        final bId = claim['beneficiary_id'];
        await supabase
            .from('beneficiaries')
            .update({'status': 'Deceased', 'eligible_to_claim': false})
            .eq('id', bId);

        final notice = await supabase
            .from('death_notices')
            .insert({
              'beneficiary_id': bId,
              'user_id': ben?['user_id'] ?? claim['user_id'],
              'name': name,
              'date_of_death': _dateOnly(dod),
              'death_certificate_url': deathCert,
              'dayung_unit_id': dayungId,
              'deceased_type': 'beneficiary',
              'barangay': barangay,
              'latitude': latitude,
              'longitude': longitude,
              'dob': _dateOnly(dob),
              'deceased_age': computedAge,
            })
            .select('id')
            .single();

        try {
          await supabase
              .from('claims')
              .update({'status': 'Approved'})
              .eq('id', (claim['id'] ?? '').toString());
        } catch (_) {}

        return Map<String, dynamic>.from(notice);
      } else {
        final uId = claim['user_id'];
        await supabase
            .from('users')
            .update({'is_deceased': true, 'date_of_death': _dateOnly(dod)})
            .eq('id', uId);

        final notice = await supabase
            .from('death_notices')
            .insert({
              'user_id': uId,
              'name': name,
              'date_of_death': _dateOnly(dod),
              'death_certificate_url': deathCert,
              'dayung_unit_id': dayungId,
              'deceased_type': 'member',
              'barangay': barangay,
              'latitude': latitude,
              'longitude': longitude,
              'dob': _dateOnly(dob),
              'deceased_age': computedAge,
            })
            .select('id')
            .single();

        try {
          await supabase
              .from('claims')
              .update({'status': 'Approved'})
              .eq('id', (claim['id'] ?? '').toString());
        } catch (_) {}

        return Map<String, dynamic>.from(notice);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
      rethrow;
    }
  }

  Future<void> _showAmountDialogAndSetDeceased(
    Map<String, dynamic> claim,
  ) async {
    final TextEditingController amountController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final isBeneficiary = claim['beneficiary_id'] != null;
    final userId = isBeneficiary
        ? (claim['beneficiaries']?['user_id'] ?? claim['user_id'])
        : claim['user_id'];
    final beneficiaryId = claim['beneficiary_id'];
    final paymentId = claim['id'];
    final fullName = isBeneficiary
        ? (claim['beneficiaries']?['full_name'] ?? '')
        : (claim['users']?['full_name'] ?? '');

    // Fetch secretary_id before showing the dialog
    final unit = await supabase
        .from('dayung_units')
        .select('secretary_id')
        .eq('id', widget.dayungUnitId)
        .maybeSingle();
    final secretaryId = unit?['secretary_id'];
    if (!mounted) return;

    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) {
        final bottomInset = MediaQuery.of(dialogContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Set contribution amount',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: kPrimaryDark,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Create the death notice for $fullName and set the amount that members need to contribute.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: kSubText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: kPrimary.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: kPrimary.withValues(alpha: 0.12),
                            child: Icon(
                              isBeneficiary
                                  ? Icons.family_restroom_rounded
                                  : Icons.person_off_rounded,
                              color: kPrimary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fullName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: kNeutralText,
                                    fontFamily: 'Montserrat',
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isBeneficiary
                                      ? 'Beneficiary claim'
                                      : 'Member claim',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: kSubText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        LengthLimitingTextInputFormatter(12),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Contribution amount',
                        hintText: '0.00',
                        prefixIcon: const Icon(Icons.payments_rounded),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext, null),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
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
                            style: FilledButton.styleFrom(
                              backgroundColor: kPrimary,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Save amount'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (result != null) {
      if (!mounted) return;
      final claimKey = _claimKey(claim);
      setState(() => _submittingClaimKey = claimKey);
      try {
        final notice = await _setDeceased(claim);
        final deathNoticeId = notice['id'];

        await supabase.from('set_amount').insert({
          'userdeceased': userId,
          'payment_id': paymentId,
          'beneficiary_id': beneficiaryId,
          'amount': result,
          'secretary_id': secretaryId,
          'dayung_unit_id': widget.dayungUnitId,
        });

        // Fetch all approved applications for the unit
        final approvedApplications = await supabase
            .from('applications')
            .select('user_id')
            .eq('dayung_unit_id', widget.dayungUnitId)
            .eq('status', 'approved');

        final now = DateTime.now().toIso8601String();
        final notificationBody =
            '$fullName passed away. Amount: ₱${result.toStringAsFixed(2)}';
        final recipients = <String>{
          for (final app in List<Map<String, dynamic>>.from(
            approvedApplications,
          ))
            if (app['user_id'] != null) app['user_id'].toString(),
        }.toList();

        final notificationRows = recipients
            .map(
              (recipientId) => {
                'recipient_id': recipientId,
                'body': notificationBody,
                'type': 'announcement',
                'title': 'Payment Reminder',
                'dayung_unit_id': widget.dayungUnitId,
                'read_at': null,
                'created_at': now,
                'sender_id': secretaryId,
              },
            )
            .toList();
        final paymentRows = recipients
            .map(
              (recipientId) => {
                'user_id': recipientId,
                'userdeceased': userId,
                'beneficiary_id': beneficiaryId,
                'death_notice_id': deathNoticeId,
                'dayung_unit_id': widget.dayungUnitId,
                'amount': result,
                'status': 'unpaid',
                'created_at': now,
              },
            )
            .toList();

        if (notificationRows.isNotEmpty) {
          await supabase.from('notifications').insert(notificationRows);
        }
        if (paymentRows.isNotEmpty) {
          await supabase.from('payments').insert(paymentRows);
        }

        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Death notice created and contribution records added.',
            ),
          ),
        );
        await _fetchApprovedClaims();
      } catch (e) {
        if (!mounted) return;
        final errorText = '$e';
        if (!errorText.startsWith('Error: ')) {
          messenger.showSnackBar(
            SnackBar(content: Text('Failed to save amount: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _submittingClaimKey = null);
        }
      }
    }
  }
}

Future<void> savePayment(Map<String, dynamic> paymentData) async {
  final supabase = Supabase.instance.client;

  final userId = paymentData['user_id'];
  final userDeceasedId = paymentData['userdeceased'];
  final datePaidAmount = paymentData['datepaidamount'];

  // Bilangin lahat ng payments na mas maaga o equal ang datepaidamount
  final existing = await supabase
      .from('payments')
      .select('id')
      .eq('user_id', userId)
      .eq('userdeceased', userDeceasedId)
      .lte('datepaidamount', datePaidAmount);

  final paymentNumber = (existing as List).length + 1;

  await supabase.from('payments').insert({
    ...paymentData,
    'payment_number': paymentNumber,
  });

  // Update payment status in payments table
  final allPayments = await supabase
      .from('payments')
      .select('id, amount, status')
      .eq('user_id', userId)
      .eq('userdeceased', userDeceasedId);

  double totalPaid = 0;
  double totalDue = 0;
  for (final row in allPayments) {
    if (row['status'] == 'paid') {
      totalPaid += double.tryParse(row['amount'].toString()) ?? 0;
    }
    if (row['status'] == 'unpaid') {
      totalDue += double.tryParse(row['amount'].toString()) ?? 0;
    }
  }

  // If totalPaid >= totalDue, mark all unpaid payments as 'paid'
  if (totalPaid >= totalDue && totalDue > 0) {
    await supabase
        .from('payments')
        .update({'status': 'paid'})
        .eq('user_id', userId)
        .eq('userdeceased', userDeceasedId)
        .eq('status', 'unpaid');
  }
}
