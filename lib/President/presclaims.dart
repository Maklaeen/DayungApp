import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/utils/input_safety.dart';
import 'package:capstone_app/utils/supabase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:capstone_app/utils/theme_surface.dart';
import 'package:capstone_app/widgets/record_data_table.dart';

const kBg = Color(0xFFF8FAFC);
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimary = Color(0xFF0D47A1);
const kPrimaryDark = Color(0xFF083366);
const kAccent = Color(0xFF10B981);
const kWarn = Color(0xFFF59E0B);
const kDanger = Color(0xFFEF4444);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);

class PresidentClaimsPage extends StatefulWidget {
  final int dayungUnitId;
  const PresidentClaimsPage({super.key, required this.dayungUnitId});

  @override
  State<PresidentClaimsPage> createState() => _PresidentClaimsPageState();
}

class _PresidentClaimsPageState extends State<PresidentClaimsPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  bool _updating = false;
  String _filter = 'Pending';
  String _search = '';
  final TextEditingController _searchController = TextEditingController();
  String? _activeClaimId;
  List<Map<String, dynamic>> _claims = [];
  Map<String, Map<String, dynamic>> _userMap = {};
  Map<String, Map<String, dynamic>> _beneficiaryMap = {};

  @override
  void initState() {
    super.initState();
    _loadClaims();
  }

  Future<void> _loadClaims() async {
    if (mounted) setState(() => _loading = true);
    try {
      final apps = await _sb
          .from('applications')
          .select('user_id, user:users(id, full_name, profile_url)')
          .eq('dayung_unit_id', widget.dayungUnitId)
          .eq('status', 'approved');

      final appsList = List<Map<String, dynamic>>.from(apps);
      final allowedUserIds = <String>[];
      final userMap = <String, Map<String, dynamic>>{};
      for (final row in appsList) {
        final userId = (row['user_id'] ?? '').toString();
        if (userId.isEmpty) continue;
        allowedUserIds.add(userId);
        final user = (row['user'] as Map?)?.cast<String, dynamic>() ?? const {};
        userMap[userId] = {
          'full_name': (user['full_name'] ?? '').toString(),
          'profile_url': (user['profile_url'] ?? '').toString(),
        };
      }

      final tagged = await _sb
          .from('claims')
          .select(
            'id, user_id, title, description, status, date_submitted, '
            'death_certificate_url, beneficiary_id, date_of_death, dayung_unit_id, claimedmoney',
          )
          .eq('status', _filter)
          .eq('dayung_unit_id', widget.dayungUnitId)
          .order('date_submitted', ascending: false);

      List<Map<String, dynamic>> legacy = [];
      if (allowedUserIds.isNotEmpty) {
        final legacyRows = await _sb
            .from('claims')
            .select(
              'id, user_id, title, description, status, date_submitted, '
              'death_certificate_url, beneficiary_id, date_of_death, dayung_unit_id, claimedmoney',
            )
            .eq('status', _filter)
            .isFilter('dayung_unit_id', null)
            .inFilter('user_id', allowedUserIds)
            .order('date_submitted', ascending: false);
        legacy = List<Map<String, dynamic>>.from(legacyRows);
      }

      final merged = <String, Map<String, dynamic>>{};
      for (final claim in legacy) {
        merged[claim['id'].toString()] = claim;
      }
      for (final claim in List<Map<String, dynamic>>.from(tagged)) {
        merged[claim['id'].toString()] = claim;
      }

      final claims = merged.values.toList()
        ..sort(
          (a, b) => DateTime.parse(
            b['date_submitted'].toString(),
          ).compareTo(DateTime.parse(a['date_submitted'].toString())),
        );

      final beneficiaryIds = claims
          .map((claim) => (claim['beneficiary_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final beneficiaryMap = <String, Map<String, dynamic>>{};
      if (beneficiaryIds.isNotEmpty) {
        final beneficiaries = await _sb
            .from('beneficiaries')
            .select('id, full_name, dob, user_id')
            .inFilter('id', beneficiaryIds);
        for (final beneficiary in List<Map<String, dynamic>>.from(
          beneficiaries,
        )) {
          beneficiaryMap[(beneficiary['id'] ?? '').toString()] = beneficiary;
        }
      }

      if (!mounted) return;
      setState(() {
        _claims = claims;
        _userMap = userMap;
        _beneficiaryMap = beneficiaryMap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load claims: $e')));
    }
  }

  List<Map<String, dynamic>> get _filteredClaims {
    if (_search.trim().isEmpty) return _claims;
    final query = _search.toLowerCase();
    return _claims.where((claim) {
      final userId = (claim['user_id'] ?? '').toString();
      final beneficiaryId = (claim['beneficiary_id'] ?? '').toString();
      final submittedBy = (_userMap[userId]?['full_name'] ?? '')
          .toString()
          .toLowerCase();
      final deceasedName = beneficiaryId.isNotEmpty
          ? (_beneficiaryMap[beneficiaryId]?['full_name'] ?? '')
                .toString()
                .toLowerCase()
          : submittedBy;
      return (claim['title'] ?? '').toString().toLowerCase().contains(query) ||
          (claim['description'] ?? '').toString().toLowerCase().contains(
            query,
          ) ||
          submittedBy.contains(query) ||
          deceasedName.contains(query) ||
          (claim['id'] ?? '').toString().toLowerCase().contains(query);
    }).toList();
  }

  String _formatDate(dynamic value, {String pattern = 'MMM d, yyyy'}) {
    if (value == null) return 'N/A';
    final date = value is DateTime ? value : DateTime.tryParse('$value');
    if (date == null) return '$value';
    return DateFormat(pattern).format(date.toLocal());
  }

  String? _dateOnly(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return DateFormat('yyyy-MM-dd').format(value);
    final text = value.toString();
    return text.contains('T') ? text.split('T').first : text;
  }

  int? _ageFromDobDod(dynamic dob, dynamic dod) {
    if (dob == null || dod == null) return null;
    final birthDate = DateTime.tryParse(dob.toString());
    final deathDate = DateTime.tryParse(dod.toString());
    if (birthDate == null || deathDate == null) return null;
    var age = deathDate.year - birthDate.year;
    if (deathDate.month < birthDate.month ||
        (deathDate.month == birthDate.month && deathDate.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  bool _isClaimed(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value == 1;
    final text = value?.toString().trim().toLowerCase();
    return text == 'yes' || text == 'true' || text == '1';
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return kAccent;
      case 'rejected':
        return kDanger;
      default:
        return kWarn;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Icons.check_circle_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  String _claimType(Map<String, dynamic> claim) {
    final title = (claim['title'] ?? '').toString().trim();
    if (title.isNotEmpty) return title;
    return 'Claim';
  }

  String _submittedBy(Map<String, dynamic> claim) {
    final userId = (claim['user_id'] ?? '').toString();
    return (_userMap[userId]?['full_name'] ?? 'Unknown member').toString();
  }

  String _deceasedName(Map<String, dynamic> claim) {
    final beneficiaryId = (claim['beneficiary_id'] ?? '').toString();
    if (beneficiaryId.isNotEmpty) {
      return (_beneficiaryMap[beneficiaryId]?['full_name'] ?? 'Beneficiary')
          .toString();
    }
    return _submittedBy(claim);
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
      final row = await _sb
          .from('dayung_rules')
          .select('exactamountformembership')
          .eq('dayung_unit_id', unitId)
          .maybeSingle();

      return _formatDefaultContributionAmount(row?['exactamountformembership']);
    } catch (_) {
      return '';
    }
  }

  Future<void> _updateStatus(String claimId, String newStatus) async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      await _sb.from('claims').update({'status': newStatus}).eq('id', claimId);
      await _loadClaims();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update claim: $e')));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _approveClaim(
    Map<String, dynamic> claim,
    BuildContext sheetContext,
  ) async {
    final resolvedUnitId = int.tryParse(
      '${claim['dayung_unit_id'] ?? widget.dayungUnitId}',
    );
    final defaultAmountText = await _loadDefaultContributionAmount(
      resolvedUnitId,
    );
    final amountController = TextEditingController(text: defaultAmountText);
    final messenger = ScaffoldMessenger.of(context);
    final sheetNavigator = Navigator.of(sheetContext);
    final fullName = _deceasedName(claim);
    final actorId = _sb.auth.currentUser?.id;

    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Contribution Amount for $fullName'),
        content: TextField(
          controller: amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            LengthLimitingTextInputFormatter(12),
          ],
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixIcon: Padding(
              padding: EdgeInsets.only(left: 12, right: 8),
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
              final parsed = double.tryParse(
                AppInputSecurity.sanitizePlainText(
                  amountController.text,
                  maxLength: 12,
                ).replaceAll(',', ''),
              );
              if (parsed == null) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Please enter a valid amount.')),
                );
                return;
              }
              Navigator.pop(dialogContext, parsed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (amount == null) return;

    if (mounted) {
      setState(() {
        _updating = true;
        _activeClaimId = '${claim['id']}';
      });
    }

    try {
      final userId = claim['user_id'];
      final beneficiaryId = claim['beneficiary_id'];
      final deathCert = claim['death_certificate_url'];
      final dayungId = claim['dayung_unit_id'] ?? widget.dayungUnitId;
      final dod = claim['date_of_death'];

      await _sb.from('set_amount').insert({
        'userdeceased': userId,
        'beneficiary_id': beneficiaryId,
        'payment_id': claim['id'],
        'amount': amount,
        'dayung_unit_id': dayungId,
      });

      Map<String, dynamic>? user;
      Map<String, dynamic>? beneficiary;
      if (beneficiaryId != null) {
        beneficiary = await _sb
            .from('beneficiaries')
            .select('full_name, dob, user_id')
            .eq('id', beneficiaryId)
            .maybeSingle();
      } else {
        user = await _sb
            .from('users')
            .select('full_name, dob')
            .eq('id', userId)
            .maybeSingle();
      }

      final name = beneficiaryId != null
          ? (beneficiary?['full_name'] ?? '')
          : (user?['full_name'] ?? '');
      final dob = beneficiaryId != null
          ? (beneficiary != null ? beneficiary['dob'] : null)
          : (user != null ? user['dob'] : null);
      final computedAge = _ageFromDobDod(dob, dod);
      final notice = await _sb
          .from('death_notices')
          .insert({
            if (beneficiaryId != null) 'beneficiary_id': beneficiaryId,
            'user_id': beneficiaryId != null
                ? (beneficiary?['user_id'] ?? userId)
                : userId,
            'name': name,
            'date_of_death': _dateOnly(dod),
            'death_certificate_url': deathCert,
            'dayung_unit_id': dayungId,
            'deceased_type': beneficiaryId != null ? 'beneficiary' : 'member',
            'barangay': null,
            'latitude': null,
            'longitude': null,
            'dob': _dateOnly(dob),
            if (computedAge != null) 'deceased_age': computedAge,
          })
          .select('id')
          .single();

      final approvedApplications = await _sb
          .from('applications')
          .select('user_id')
          .eq('dayung_unit_id', dayungId)
          .eq('status', 'approved');
      final now = DateTime.now().toIso8601String();
      final recipients = <String>{
        for (final app in List<Map<String, dynamic>>.from(approvedApplications))
          if (app['user_id'] != null) app['user_id'].toString(),
      }.toList();

      if (recipients.isNotEmpty) {
        final notificationRows = recipients
            .map(
              (recipientId) => {
                'recipient_id': recipientId,
                'body':
                    '$fullName passed away. Amount: ₱${amount.toStringAsFixed(2)}',
                'type': 'announcement',
                'title': 'Payment Reminder',
                'dayung_unit_id': dayungId,
                'read_at': null,
                'created_at': now,
                'sender_id': actorId,
              },
            )
            .toList();
        final paymentRows = recipients
            .map(
              (recipientId) => {
                'user_id': recipientId,
                'userdeceased': userId,
                'beneficiary_id': beneficiaryId,
                'death_notice_id': notice['id'],
                'dayung_unit_id': dayungId,
                'amount': amount,
                'status': 'unpaid',
                'type': 'deceased_payment',
                'created_at': now,
              },
            )
            .toList();

        await _sb.from('notifications').insert(notificationRows);
        await _sb.from('payments').insert(paymentRows);
      }

      await _sb
          .from('claims')
          .update({'status': 'Approved'})
          .eq('id', claim['id']);
      await _loadClaims();
      if (!mounted) return;
      sheetNavigator.pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Claim approved and contribution records generated.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to approve claim: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
          _activeClaimId = null;
        });
      }
    }
  }

  Future<void> _openDeathCertificate(String storagePath) async {
    final messenger = ScaffoldMessenger.of(context);
    final url = await resolveSupabaseStorageUrl(storagePath, client: _sb);
    if (!mounted) return;
    if (url == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open file.')),
      );
      return;
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not open file.')),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: kSubText,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: kText, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showClaimDetails(Map<String, dynamic> claim) {
    final status = (claim['status'] ?? '').toString();
    final claimId = '${claim['id'] ?? ''}';
    final active = _activeClaimId == claimId;
    final certificatePath = (claim['death_certificate_url'] ?? '').toString();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 52,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          _statusIcon(status),
                          color: _statusColor(status),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _claimType(claim),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: kText,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _statusColor(
                                  status,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  color: _statusColor(status),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Filed by ${_submittedBy(claim)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kSubText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _deceasedName(claim),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: kPrimary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: kBorderColor),
                    ),
                    child: Column(
                      children: [
                        _detailRow(
                          'Submitted',
                          _formatDate(
                            claim['date_submitted'],
                            pattern: 'MMM d, yyyy • h:mm a',
                          ),
                        ),
                        _detailRow(
                          'Date of death',
                          _formatDate(claim['date_of_death']),
                        ),
                        _detailRow(
                          'Claimed money',
                          _isClaimed(claim['claimedmoney']) ? 'Yes' : 'No',
                        ),
                        if ((claim['description'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          _detailRow(
                            'Description',
                            (claim['description'] ?? '').toString().trim(),
                          ),
                      ],
                    ),
                  ),
                  if (certificatePath.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => _openDeathCertificate(certificatePath),
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text('View death certificate'),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (status.toLowerCase() == 'pending')
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _updating
                                ? null
                                : () async {
                                    final sheetNavigator = Navigator.of(
                                      sheetContext,
                                    );
                                    await _updateStatus(claimId, 'Rejected');
                                    if (!mounted) return;
                                    sheetNavigator.pop();
                                  },
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Reject'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kDanger,
                              side: const BorderSide(color: kDanger),
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: (_updating && active)
                                ? null
                                : () => _approveClaim(claim, sheetContext),
                            icon: (_updating && active)
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_rounded),
                            label: Text(
                              (_updating && active) ? 'Saving...' : 'Set Claim',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimary,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _filterChip(String label) {
    final selected = _filter == label;
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            if (_filter == label) return;
            setState(() => _filter = label);
            _loadClaims();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? colors.primary : colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? colors.primary : colors.outlineVariant,
              ),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _statusIcon(label),
                  size: 16,
                  color: selected ? colors.onPrimary : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? colors.onPrimary
                          : colors.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: dayungPageBackground(context),
      child: RefreshIndicator(
        onRefresh: _loadClaims,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: dayungSectionCardDecoration(context, radius: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Claims Review',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: colors.onSurface,
                                fontFamily: 'Montserrat',
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Review and manage member claims',
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.onSurfaceVariant,
                                fontFamily: 'OpenSans',
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh claims',
                        onPressed: _loading ? null : _loadClaims,
                        icon: const Icon(Icons.refresh_rounded),
                        style: IconButton.styleFrom(
                          fixedSize: const Size(48, 48),
                          backgroundColor: dayungSurface(context),
                          foregroundColor: colors.primary,
                          side: BorderSide(color: dayungBorder(context)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _filterChip('Pending'),
                      const SizedBox(width: 8),
                      _filterChip('Approved'),
                      const SizedBox(width: 8),
                      _filterChip('Rejected'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _search = value),
                    style: TextStyle(color: colors.onSurface, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search claim, deceased, or member',
                      hintStyle: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: colors.onSurfaceVariant,
                      ),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _search = '');
                              },
                              icon: Icon(
                                Icons.close_rounded,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                      filled: true,
                      fillColor: dayungSurface(context),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: dayungBorder(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: dayungBorder(context)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: colors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const DayungPageSkeleton(
                layout: DayungSkeletonLayout.list,
                padding: EdgeInsets.all(8),
                itemCount: 3,
              )
            else if (_filteredClaims.isEmpty)
              _emptyClaimsState()
            else
              _claimsTable(),
          ],
        ),
      ),
    );
  }

  Widget _emptyClaimsState() {
    final colors = Theme.of(context).colorScheme;
    final searching = _search.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: dayungSectionCardDecoration(context, radius: 18),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              searching ? Icons.search_off_rounded : Icons.inbox_rounded,
              color: colors.onSurfaceVariant,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            searching ? 'No matching claims' : 'No $_filter claims',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
              fontFamily: 'Montserrat',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            searching
                ? 'Try another search term or clear your search.'
                : 'Claims in this status will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
          ),
          if (searching) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() => _search = '');
              },
              icon: const Icon(Icons.close_rounded),
              label: const Text('Clear search'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _claimsTable() {
    final colors = Theme.of(context).colorScheme;
    return RecordDataTable(
      minWidth: 850,
      columnSpacing: 18,
      horizontalMargin: 16,
      headingRowHeight: 50,
      dataRowMinHeight: 56,
      dataRowMaxHeight: 76,
      showCheckboxColumn: false,
      headingTextStyle: TextStyle(
        color: colors.onSurface,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        fontFamily: 'Montserrat',
      ),
      dataTextStyle: TextStyle(
        color: colors.onSurface,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        fontFamily: 'OpenSans',
      ),
      columns: const [
        DataColumn(label: Text('Claim')),
        DataColumn(label: Text('Deceased')),
        DataColumn(label: Text('Filed by')),
        DataColumn(label: Text('Status')),
        DataColumn(label: Text('Submitted')),
        DataColumn(label: Text('Details')),
      ],
      rows: _filteredClaims.map((claim) {
        final status = (claim['status'] ?? '').toString();
        final claimId = '${claim['id'] ?? ''}';
        final active = _activeClaimId == claimId;
        void onTap() => _showClaimDetails(claim);

        return DataRow(
          cells: [
            DataCell(Text(_claimType(claim)), onTap: onTap),
            DataCell(Text(_deceasedName(claim)), onTap: onTap),
            DataCell(Text(_submittedBy(claim)), onTap: onTap),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _statusIcon(status),
                      size: 14,
                      color: _statusColor(status),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status,
                      style: TextStyle(
                        color: _statusColor(status),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              onTap: onTap,
            ),
            DataCell(Text(_formatDate(claim['date_submitted'])), onTap: onTap),
            DataCell(
              _updating && active
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.chevron_right_rounded, color: colors.primary),
              onTap: onTap,
            ),
          ],
        );
      }).toList(),
    );
  }
}
