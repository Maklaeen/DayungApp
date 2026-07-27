import 'dart:typed_data';
import 'package:capstone_app/Providers/membership_qualification_provider.dart';
import 'package:capstone_app/Secretary/secretary_ui.dart';
import 'package:pdfx/pdfx.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart' as provider;
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF1E40AF);
const kPrimaryLight = Color(0xFF3B82F6);
const kAccentDark = Color(0xFF059669);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);
const kDanger = Color(0xFFEF4444);
const double kEdge = 16;

class SecretaryApplicationsPage extends StatefulWidget {
  const SecretaryApplicationsPage({super.key});

  @override
  State<SecretaryApplicationsPage> createState() =>
      _SecretaryApplicationsPageState();
}

Map<String, dynamic> buildMembershipPaymentPayload({
  required String userId,
  required int dayungUnitId,
  required double amount,
  String? createdAt,
}) {
  final now = createdAt ?? DateTime.now().toIso8601String();
  return {
    'user_id': userId,
    'amount': amount,
    'status': 'unpaid',
    'dayung_unit_id': dayungUnitId,
    'created_at': now,
    'paid_at': null,
    'collected_by': null,
    'datepaidamount': null,
    'userdeceased': null,
    'deceased_name': null,
    'message': null,
    'claim_id': null,
    'is_due': null,
    'due_date': null,
    'type': 'membership fee',
  };
}

double parseMembershipAmount(dynamic value) {
  final cleaned = value?.toString().replaceAll(RegExp(r'[^0-9.-]'), '') ?? '';
  return double.tryParse(cleaned) ?? 0.0;
}

class _SecretaryApplicationsPageState extends State<SecretaryApplicationsPage> {
  final _supabase = Supabase.instance.client;

  String _filter = 'pending'; // pending | approved | rejected
  bool _loading = true;
  List<Map<String, dynamic>> _apps = [];
  Set<String> _deceasedUserIds = {};
  String _searchQuery = '';
  String? _error;

  RealtimeChannel? _channel;
  int? _currentUnitId;
  String _inferType(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.pdf')) return 'pdf';
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpg';
    return 'unknown';
  }

  @override
  void initState() {
    super.initState();
    // Delay to let Provider be available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _currentUnitId = context.read<DayungUnitProvider>().currentUnitId;
      _fetchApplications(forUnitId: _currentUnitId);
      if (_currentUnitId != null) _subscribeRealtime(unitId: _currentUnitId!);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newId = context.watch<DayungUnitProvider>().currentUnitId;
    if (newId != _currentUnitId) {
      _currentUnitId = newId;
      if (mounted) setState(() => _apps = []); // clear stale
      _fetchApplications(forUnitId: newId);
      _resubscribe(unitId: newId);
    }
  }

  @override
  void dispose() {
    try {
      _channel?.unsubscribe();
      if (_channel != null) {
        Supabase.instance.client.removeChannel(_channel!); // ensure detached
      }
    } catch (_) {}
    _channel = null;
    super.dispose();
  }

  void _resubscribe({int? unitId}) {
    try {
      _channel?.unsubscribe();
      if (_channel != null) {
        Supabase.instance.client.removeChannel(_channel!);
      }
    } catch (_) {}
    _channel = null;
    if (unitId != null) _subscribeRealtime(unitId: unitId);
  }

  void _subscribeRealtime({required int unitId}) {
    _channel?.unsubscribe();
    _channel = _supabase.channel('secretary_apps_$unitId');

    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'applications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'dayung_unit_id',
        value: unitId,
      ),
      callback: (payload) {
        // Ignore events for other units (extra safety)
        final rec =
            (payload.newRecord.isNotEmpty
                    ? payload.newRecord
                    : payload.oldRecord)
                as Map<String, dynamic>?;

        final recUnitId = rec?['dayung_unit_id'];
        final recId = recUnitId is int ? recUnitId : int.tryParse('$recUnitId');
        if (recId != unitId) return;

        _fetchApplications(forUnitId: unitId);
      },
    );

    _channel!.subscribe();
  }

  List<Map<String, dynamic>> get _visibleApps {
    if (_searchQuery.trim().isEmpty) return _apps;

    final query = _searchQuery.trim().toLowerCase();
    return _apps.where((app) {
      final user = app['users'] as Map<String, dynamic>?;
      final name = (user?['full_name'] ?? '').toString().toLowerCase();
      final email = (user?['email'] ?? '').toString().toLowerCase();
      final appliedAt = (app['applied_at'] ?? '').toString().toLowerCase();
      return name.contains(query) ||
          email.contains(query) ||
          appliedAt.contains(query);
    }).toList();
  }

  int get _flaggedVisibleCount {
    return _visibleApps.where((app) {
      final userId = (app['user_id'] ?? '').toString();
      return _deceasedUserIds.contains(userId);
    }).length;
  }

  String get _filterLabel {
    switch (_filter) {
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return kSuccess;
      case 'rejected':
        return kDanger;
      default:
        return kPrimary;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'approved':
        return Icons.verified_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  String _formatAppliedDate(dynamic value) {
    final date = DateTime.tryParse('${value ?? ''}')?.toLocal();
    if (date == null) return 'Unknown date';
    final monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${monthNames[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _buildOverviewCard() {
    final statusTone = _statusColor(_filter);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorderColor),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _overviewStat(
            icon: _statusIcon(_filter),
            label: _filterLabel,
            value: '${_apps.length}',
            tone: statusTone,
          ),
          _overviewStat(
            icon: Icons.visibility_rounded,
            label: 'Showing',
            value: '${_visibleApps.length}',
            tone: kPrimaryDark,
          ),
          _overviewStat(
            icon: Icons.warning_amber_rounded,
            label: 'Flagged',
            value: '$_flaggedVisibleCount',
            tone: const Color(0xFFF59E0B),
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.14)),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverviewCard(),
          const SizedBox(height: 14),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search member, email, or application date',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kBorderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kBorderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kPrimary),
              ),
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value.trim().toLowerCase());
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_statusIcon(_filter), size: 15, color: kPrimary),
                    const SizedBox(width: 6),
                    Text(
                      '$_filterLabel applications',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: kPrimaryDark,
                      ),
                    ),
                  ],
                ),
              ),
              if (_searchQuery.isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(() => _searchQuery = ''),
                  icon: const Icon(Icons.filter_alt_off_rounded),
                  label: const Text('Reset search'),
                ),
            ],
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
        border: Border.all(color: kBorderColor),
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
              color: kText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: kSubText,
              fontFamily: 'OpenSans',
            ),
          ),
          if (action != null) ...[const SizedBox(height: 14), action],
        ],
      ),
    );
  }

  Future<Uri?> _resolveCertificateUri(String raw) async {
    if (raw.trim().isEmpty) return null;

    // If it's already a valid absolute URL, use it
    try {
      final u = Uri.parse(raw);
      if (u.hasScheme && (u.isScheme('https') || u.isScheme('http'))) {
        return u;
      }
    } catch (_) {}

    // Treat as Supabase Storage path: "bucket/path/to/file.pdf" (or with leading slash)
    final path = raw.replaceFirst(RegExp(r'^/+'), '');
    final parts = path.split('/');
    if (parts.length < 2) return null;

    final bucket = parts.first;
    final objectPath = parts.sublist(1).join('/');

    try {
      // Prefer a short-lived signed URL (works for private buckets)
      final signed = await _supabase.storage
          .from(bucket)
          .createSignedUrl(objectPath, 3600); // 1 hour

      return Uri.parse(signed);
    } catch (_) {
      // Fallback to public URL if bucket is public
      try {
        final pub = _supabase.storage.from(bucket).getPublicUrl(objectPath);
        return Uri.parse(pub);
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _openCertificateViewer(String raw) async {
    final uri = await _resolveCertificateUri(raw);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid certificate link')));
      return;
    }

    final kind = _inferType(uri.toString());
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.92;
        return Container(
          height: height,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              SecretarySheetHeader(
                title: 'Death Certificate',
                subtitle: 'Review the uploaded document for this application.',
                onClose: () => Navigator.pop(ctx),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Builder(
                    builder: (_) {
                      if (kind == 'png' || kind == 'jpg') {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            color: const Color(0xFFF8FAFC),
                            child: InteractiveViewer(
                              child: Image.network(
                                uri.toString(),
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Text('Failed to load image'),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      if (kind == 'pdf') {
                        return FutureBuilder<Uint8List>(
                          future: () async {
                            final resp = await http.get(uri);
                            if (resp.statusCode != 200) {
                              throw Exception('HTTP ${resp.statusCode}');
                            }
                            return resp.bodyBytes;
                          }(),
                          builder: (context, snap) {
                            if (snap.connectionState != ConnectionState.done) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (snap.hasError || snap.data == null) {
                              return const Center(
                                child: Text('Failed to load PDF'),
                              );
                            }
                            final bytes = snap.data!;
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                color: const Color(0xFFF8FAFC),
                                child: _PdfViewer(bytes: bytes),
                              ),
                            );
                          },
                        );
                      }
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Unsupported file type. Open in browser?',
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Open'),
                              onPressed: () async {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              },
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
        );
      },
    );
  }

  Future<void> _openDeceasedDetails(String userId) async {
    final unitId = _currentUnitId;
    if (unitId == null) return;
    try {
      List<dynamic> res;
      try {
        res = await _supabase.rpc(
          'sec_get_deceased_details',
          params: {'p_user_id': userId, 'p_exclude_unit_id': unitId},
        );
      } catch (_) {
        res = await _supabase
            .from('death_notices')
            .select(
              'id, name, date_of_death, deceased_age, dob, dayung_unit_id, deceased_type, death_certificate_url, barangay',
            )
            .eq('user_id', userId)
            .neq('dayung_unit_id', unitId)
            .or('deceased_type.is.null,deceased_type.eq.member')
            .order('date_of_death', ascending: false);
      }

      final items = List<Map<String, dynamic>>.from(res);

      final unitIds = items
          .map((e) => e['dayung_unit_id'])
          .where((v) => v != null)
          .toSet()
          .toList();
      Map<int, String> unitNames = {};
      Map<int, String> unitCities = {};
      if (unitIds.isNotEmpty) {
        final urows = await _supabase
            .from('dayung_units')
            .select('id, name, city')
            .inFilter('id', unitIds);
        for (final r in urows as List) {
          final m = Map<String, dynamic>.from(r as Map);
          final id = m['id'] is int
              ? m['id'] as int
              : int.tryParse('${m['id']}');
          if (id != null) {
            unitNames[id] = (m['name'] ?? 'Dayung').toString();
            unitCities[id] = (m['city'] ?? '').toString();
          }
        }
      }

      if (!mounted) return;
      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No deceased details found.')),
        );
        return;
      }
      _showDeceasedDetailsSheet(items, unitNames, unitCities);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load deceased details')),
      );
    }
  }

  void _showDeceasedDetailsSheet(
    List<Map<String, dynamic>> items,
    Map<int, String> unitNames,
    Map<int, String> unitCities,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.92;
        return Container(
          height: height,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              SecretarySheetHeader(
                title: 'Deceased Details',
                subtitle:
                    'Review other recorded death notices linked to this applicant.',
                onClose: () => Navigator.pop(ctx),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final n = items[i];
                    final unitId = (n['dayung_unit_id'] is int)
                        ? n['dayung_unit_id'] as int
                        : int.tryParse('${n['dayung_unit_id']}');
                    final unitName = unitId != null
                        ? (unitNames[unitId] ?? 'Dayung')
                        : 'Dayung';
                    final dod = n['date_of_death']?.toString();
                    final age = n['deceased_age']?.toString();
                    final dob = n['dob']?.toString();
                    final type = (n['deceased_type'] ?? 'member').toString();
                    final cert = (n['death_certificate_url'] ?? '').toString();
                    final name = (n['name'] ?? '').toString();
                    final cityTop = (n['city'] ?? '').toString();
                    final cityFromUnit = unitId != null
                        ? (unitCities[unitId] ?? '')
                        : '';
                    final loc =
                        [
                              n['barangay'],
                              (cityTop.isNotEmpty ? cityTop : cityFromUnit),
                            ]
                            .where(
                              (e) => (e ?? '').toString().trim().isNotEmpty,
                            )
                            .join(', ');

                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: kBorderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            unitName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: kPrimaryDark,
                              fontFamily: 'Montserrat',
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (name.isNotEmpty)
                            _sheetDetailRow(Icons.person_rounded, name),
                          if (type.isNotEmpty)
                            _sheetDetailRow(Icons.badge_rounded, type),
                          if (dob != null && dob.isNotEmpty)
                            _sheetDetailRow(Icons.cake_rounded, dob),
                          if (age != null && age.isNotEmpty)
                            _sheetDetailRow(Icons.timelapse_rounded, age),
                          if (dod != null && dod.isNotEmpty)
                            _sheetDetailRow(Icons.event_rounded, dod),
                          if (loc.isNotEmpty)
                            _sheetDetailRow(Icons.place_rounded, loc),
                          if (cert.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.picture_as_pdf_rounded),
                                label: const Text('Open death certificate'),
                                onPressed: () => _openCertificateViewer(cert),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _fetchApplications({int? forUnitId}) async {
    final unitId =
        forUnitId ??
        _currentUnitId ??
        context.read<DayungUnitProvider>().currentUnitId;

    if (unitId == null) {
      if (!mounted) return;
      setState(() {
        _apps = [];
        _loading = false;
        _deceasedUserIds = {};
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _supabase
          .from('applications')
          .select(
            // Include user_id so we can flag per user.
            'id, user_id, status, applied_at, dayung_unit_id, users(id, full_name, email, profile_url)',
          )
          .eq('dayung_unit_id', unitId) // single authoritative filter
          .eq('status', _filter)
          .order('applied_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(data).where((r) {
        final v = r['dayung_unit_id'];
        final rid = v is int ? v : int.tryParse('$v');
        return rid == unitId;
      }).toList();
      // Build deceased flags (any death_notice for the user in a different unit)
      final userIds = list
          .map((r) => r['user_id'])
          .where((id) => id != null)
          .map((id) => id.toString())
          .toSet()
          .toList();
      Set<String> deceased = {};
      if (userIds.isNotEmpty) {
        final dnRows = await _supabase
            .from('death_notices')
            .select('user_id, dayung_unit_id, deceased_type')
            .inFilter('user_id', userIds)
            .neq('dayung_unit_id', unitId) // deceased in other unit(s)
            .or(
              'deceased_type.is.null,deceased_type.eq.member',
            ); // treat null/member as member
        deceased = Set<String>.from(
          (dnRows as List)
              .map((r) => (r as Map)['user_id'])
              .where((v) => v != null)
              .map((v) => v.toString()),
        );
      }

      if (!mounted) return;
      setState(() {
        _apps = list;
        _loading = false;
        _deceasedUserIds = deceased;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Load failed: ${e.message}')));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unexpected error loading applications';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unexpected error loading applications')),
      );
    }
  }

  Future<void> _createMembershipPaymentRecord({
    required String userId,
    required int dayungUnitId,
  }) async {
    try {
      final rulesRow = await _supabase
          .from('dayung_rules')
          .select('exactamountformembership')
          .eq('dayung_unit_id', dayungUnitId)
          .maybeSingle();

      final existing = await _supabase
          .from('payments')
          .select('id')
          .eq('user_id', userId)
          .eq('dayung_unit_id', dayungUnitId)
          .eq('type', 'membership fee')
          .maybeSingle();

      if (existing != null) return;

      final amount = parseMembershipAmount(rulesRow?['exactamountformembership']);
      await _supabase.from('payments').insert(
        buildMembershipPaymentPayload(
          userId: userId,
          dayungUnitId: dayungUnitId,
          amount: amount,
        ),
      );
    } catch (_) {
      // Ignore payment insert issues so the approval flow is not blocked.
    }
  }

  Future<void> _approve(
    int applicationId, {
    required bool deceasedElsewhere,
  }) async {
    if (deceasedElsewhere) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Applicant flagged'),
          content: const Text(
            'This user is marked as deceased in other dayung. Proceed to approve?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Approve'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    try {
      final applicationRow = await _supabase
          .from('applications')
          .select('user_id, dayung_unit_id')
          .eq('id', applicationId)
          .maybeSingle();

      await _supabase.rpc(
        'approve_application',
        params: {'p_application_id': applicationId},
      );

      final userId = applicationRow?['user_id']?.toString();
      final unitId = int.tryParse('${applicationRow?['dayung_unit_id']}');
      if (userId != null && userId.isNotEmpty && unitId != null) {
        await _createMembershipPaymentRecord(userId: userId, dayungUnitId: unitId);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Application approved')));
      _fetchApplications(forUnitId: _currentUnitId);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Approve failed: ${e.message.isEmpty ? 'Check RPC/Policies' : e.message}',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unexpected error')));
    }
  }

  Future<void> _reject(int applicationId) async {
    try {
      await _supabase.rpc(
        'reject_application',
        params: {'p_application_id': applicationId},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Application rejected')));
      _fetchApplications(forUnitId: _currentUnitId);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reject failed: ${e.message.isEmpty ? 'Check RPC/Policies' : e.message}',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unexpected error')));
    }
  }

  // Fetch birth certificate URL (from applications first, then users)
  Future<String?> _getBirthCertificateUrl({
    required String userId,
    int? applicationId,
  }) async {
    if (applicationId != null) {
      try {
        final row = await _supabase
            .from('applications')
            .select('birth_certificate_url')
            .eq('id', applicationId)
            .single();
        final url = (row['birth_certificate_url'] ?? '').toString().trim();
        if (url.isNotEmpty) return url;
      } catch (_) {}
    }
    try {
      final row = await _supabase
          .from('users')
          .select('birth_certificate_url')
          .eq('id', userId)
          .single();
      final url = (row['birth_certificate_url'] ?? '').toString().trim();
      if (url.isNotEmpty) return url;
    } catch (_) {}
    return null;
  }

  // Fetch valid ID URL (from applications first, then users)
  Future<String?> _getValidIdUrl({
    required String userId,
    int? applicationId,
  }) async {
    if (applicationId != null) {
      try {
        final row = await _supabase
            .from('applications')
            .select('valid_id_url')
            .eq('id', applicationId)
            .single();
        final url = (row['valid_id_url'] ?? '').toString().trim();
        if (url.isNotEmpty) return url;
      } catch (_) {}
    }
    try {
      final row = await _supabase
          .from('users')
          .select('valid_id_url')
          .eq('id', userId)
          .single();
      final url = (row['valid_id_url'] ?? '').toString().trim();
      if (url.isNotEmpty) return url;
    } catch (_) {}
    return null;
  }

  // Fetch proof of residency URL (from applications first, then users)
  Future<String?> _getProofOfResidencyUrl({
    required String userId,
    int? applicationId,
  }) async {
    if (applicationId != null) {
      try {
        final row = await _supabase
            .from('applications')
            .select('proof_of_residency_url')
            .eq('id', applicationId)
            .single();
        final url = (row['proof_of_residency_url'] ?? '').toString().trim();
        if (url.isNotEmpty) return url;
      } catch (_) {}
    }
    try {
      final row = await _supabase
          .from('users')
          .select('proof_of_residency_url')
          .eq('id', userId)
          .single();
      final url = (row['proof_of_residency_url'] ?? '').toString().trim();
      if (url.isNotEmpty) return url;
    } catch (_) {}
    return null;
  }

  // New: open tracking sheet for a user
  Future<void> _openUserTracking({
    required String userId,
    required String userName,
    int? applicationId,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.92;
        return Container(
          height: height,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: FutureBuilder<Map<String, dynamic>>(
            future: () async {
              final userFuture = _supabase
                  .from('users')
                  .select('full_name, sex, dob, mobile_number, address')
                  .eq('id', userId)
                  .single()
                  .catchError((_) => {});
              final docsFuture = Future.wait([
                _getBirthCertificateUrl(
                  userId: userId,
                  applicationId: applicationId,
                ),
                () async {
                  try {
                    final row = await _supabase
                        .from('users')
                        .select('valid_id')
                        .eq('id', userId)
                        .single();
                    final url = (row['valid_id'] ?? '').toString().trim();
                    if (url.isNotEmpty) return url;
                  } catch (_) {}
                  return await _getValidIdUrl(
                    userId: userId,
                    applicationId: applicationId,
                  );
                }(),
                _getProofOfResidencyUrl(
                  userId: userId,
                  applicationId: applicationId,
                ),
              ]);
              final user = await userFuture;
              final docs = await docsFuture;
              return {'user': user, 'docs': docs};
            }(),
            builder: (context, snap) {
              final user = snap.data != null
                  ? (snap.data!['user'] as Map<String, dynamic>? ?? {})
                  : {};
              final docs = snap.data != null
                  ? (snap.data!['docs'] as List<String?>? ?? [])
                  : [];
              final birthUrl = docs.isNotEmpty ? docs[0] : null;
              final validIdUrl = docs.length > 1 ? docs[1] : null;
              final residencyUrl = docs.length > 2 ? docs[2] : null;
              final uploadedBirth = (birthUrl != null && birthUrl.isNotEmpty);
              final uploadedValidId =
                  (validIdUrl != null && validIdUrl.isNotEmpty);
              final uploadedResidency =
                  (residencyUrl != null && residencyUrl.isNotEmpty);

              int completed = 0;
              if (uploadedBirth) completed++;
              if (uploadedValidId) completed++;
              if (uploadedResidency) completed++;
              const total = 3;
              double progress = completed / total;

              final fullName = (user['full_name'] ?? userName ?? '').toString();
              final sex = (user['sex'] ?? '').toString();
              final dob = (user['dob'] ?? '').toString();
              final mobile = (user['mobile_number'] ?? '').toString();
              final address = (user['address'] ?? '').toString();

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [kPrimaryDark, kPrimary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 42,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Review Application',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 20,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Check applicant details and uploaded requirements before deciding.',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: kCardBg,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: kBorderColor),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 30,
                                  backgroundColor: kPrimaryLight.withValues(
                                    alpha: 0.15,
                                  ),
                                  child: Icon(
                                    Icons.person_rounded,
                                    color: kPrimary,
                                    size: 34,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        fullName.isNotEmpty
                                            ? fullName
                                            : 'No Name',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 18,
                                          color: kPrimaryDark,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      _sheetDetailRow(
                                        Icons.phone_rounded,
                                        mobile.isNotEmpty
                                            ? mobile
                                            : 'No mobile',
                                      ),
                                      _sheetDetailRow(
                                        Icons.cake_rounded,
                                        dob.isNotEmpty ? dob : 'No birthday',
                                      ),
                                      _sheetDetailRow(
                                        Icons.person_outline_rounded,
                                        sex.isNotEmpty ? sex : 'No sex',
                                      ),
                                      _sheetDetailRow(
                                        Icons.home_rounded,
                                        address.isNotEmpty
                                            ? address
                                            : 'No address',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: kBorderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Requirements Progress',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: kText,
                                    fontFamily: 'Montserrat',
                                  ),
                                ),
                                const SizedBox(height: 10),
                                LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 8,
                                  backgroundColor: kBorderColor,
                                  color: progress == 1.0 ? kSuccess : kPrimary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '$completed of $total requirements available',
                                  style: TextStyle(
                                    color: progress == 1.0
                                        ? kSuccess
                                        : kPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _TrackingStepTile(
                            stepNumber: 1,
                            title: 'Birth Certificate',
                            completed: uploadedBirth,
                            url: birthUrl,
                            onView: uploadedBirth
                                ? () => _openCertificateViewer(birthUrl)
                                : null,
                          ),
                          const SizedBox(height: 10),
                          _TrackingStepTile(
                            stepNumber: 2,
                            title: 'Valid ID',
                            completed: uploadedValidId,
                            url: validIdUrl,
                            onView: uploadedValidId
                                ? () => _openCertificateViewer(validIdUrl)
                                : null,
                          ),
                          const SizedBox(height: 10),
                          _TrackingStepTile(
                            stepNumber: 3,
                            title: 'Proof of Residency',
                            completed: uploadedResidency,
                            url: residencyUrl,
                            onView: uploadedResidency
                                ? () => _openCertificateViewer(residencyUrl)
                                : null,
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: kDanger,
                                  ),
                                  label: const Text(
                                    'Reject',
                                    style: TextStyle(color: kDanger),
                                  ),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    if (applicationId != null) {
                                      _reject(applicationId);
                                    }
                                  },
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    side: const BorderSide(color: kDanger),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  icon: const Icon(Icons.check_circle_rounded),
                                  label: const Text('Approve'),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    if (applicationId != null) {
                                      _approve(
                                        applicationId,
                                        deceasedElsewhere: _deceasedUserIds
                                            .contains(userId),
                                      );
                                    }
                                  },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: kSuccess,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size.fromHeight(48),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayungName =
        context.watch<DayungUnitProvider>().dayungUnit ?? 'Dayung';
    final visibleApps = _visibleApps;
    return Scaffold(
      backgroundColor: kCardBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700;
            final horizontalPadding = isWide
                ? constraints.maxWidth * 0.15
                : 20.0;

            return Column(
              children: [
                SecretaryPageHeader(
                  title: 'Manage Applications',
                  subtitle:
                      'Review member applications and keep approvals moving for your unit.',
                  icon: Icons.assignment_rounded,
                  usePaymentStyle: true,
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    isWide ? 28 : 28,
                    horizontalPadding,
                    24,
                  ),
                ),
                // Navigation Tabs
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.filter_list_rounded,
                        color: kSubText,
                        size: 16,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _NavTab(
                              label: 'Pending',
                              icon: Icons.schedule_rounded,
                              selected: _filter == 'pending',
                              onTap: () {
                                setState(() => _filter = 'pending');
                                _fetchApplications(forUnitId: _currentUnitId);
                              },
                            ),
                            _NavTab(
                              label: 'Approved',
                              icon: Icons.check_circle_rounded,
                              selected: _filter == 'approved',
                              onTap: () {
                                setState(() => _filter = 'approved');
                                _fetchApplications(forUnitId: _currentUnitId);
                              },
                            ),
                            _NavTab(
                              label: 'Rejected',
                              icon: Icons.cancel_rounded,
                              selected: _filter == 'rejected',
                              onTap: () {
                                setState(() => _filter = 'rejected');
                                _fetchApplications(forUnitId: _currentUnitId);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Content
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () =>
                        _fetchApplications(forUnitId: _currentUnitId),
                    color: kPrimary,
                    child: _loading
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            children: [
                              _buildToolbarCard(),
                              _buildEmptyState(
                                icon: Icons.hourglass_top_rounded,
                                title: 'Loading applications...',
                                message:
                                    'Pulling the latest application records for your unit.',
                              ),
                            ],
                          )
                        : _error != null
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            children: [
                              _buildToolbarCard(),
                              _buildEmptyState(
                                icon: Icons.error_outline_rounded,
                                title: 'Could not load applications',
                                message: _error!,
                                action: OutlinedButton.icon(
                                  onPressed: () => _fetchApplications(
                                    forUnitId: _currentUnitId,
                                  ),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Retry fetch'),
                                ),
                              ),
                            ],
                          )
                        : _apps.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            children: [
                              _buildToolbarCard(),
                              _buildEmptyState(
                                icon: Icons.inbox_rounded,
                                title: 'No applications found',
                                message:
                                    'No applications match the selected status for this dayung right now.',
                              ),
                            ],
                          )
                        : visibleApps.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            children: [
                              _buildToolbarCard(),
                              _buildEmptyState(
                                icon: Icons.search_off_rounded,
                                title: 'No matching applications',
                                message:
                                    'Try a different search keyword or reset the current search.',
                                action: OutlinedButton.icon(
                                  onPressed: () =>
                                      setState(() => _searchQuery = ''),
                                  icon: const Icon(
                                    Icons.filter_alt_off_rounded,
                                  ),
                                  label: const Text('Reset search'),
                                ),
                              ),
                            ],
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(bottom: 24),
                              itemCount: visibleApps.length + 1,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                if (i == 0) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: _buildToolbarCard(),
                                  );
                                }

                                final app = visibleApps[i - 1];
                                final user =
                                    app['users'] as Map<String, dynamic>?;
                                final status = (app['status'] ?? '').toString();
                                final userIdStr = (app['user_id'] ?? '')
                                    .toString();
                                final deceasedElsewhere = _deceasedUserIds
                                    .contains(userIdStr);
                                final statusTone = _statusColor(status);
                                final userName =
                                    (user?['full_name'] ?? 'Member').toString();
                                final userEmail =
                                    (user?['email'] ?? 'No email provided')
                                        .toString();
                                final appId = app['id'] as int;

                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: kCardBg,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: kBorderColor.withValues(
                                        alpha: 0.3,
                                      ),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.05,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: statusTone.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          userName.isNotEmpty
                                              ? userName[0].toUpperCase()
                                              : 'M',
                                          style: TextStyle(
                                            color: statusTone,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            fontFamily: 'Montserrat',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    userName,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 16,
                                                      color: kText,
                                                      fontFamily: 'Montserrat',
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 6,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: statusTone
                                                        .withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    _filterLabel,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: statusTone,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              userEmail,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: kSubText,
                                                fontFamily: 'OpenSans',
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Applied: ${_formatAppliedDate(app['applied_at'])}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: kSubText,
                                                fontFamily: 'OpenSans',
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              dayungName,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: kSubText,
                                                fontFamily: 'OpenSans',
                                              ),
                                            ),
                                            // specific objectives - riverpod
                                            Consumer(
                                              builder: (context, ref, _) {
                                                final userId = app['user_id']
                                                    .toString();
                                                final unitId =
                                                    app['dayung_unit_id']
                                                        as int;
                                                final qualification = ref.watch(
                                                  membershipQualificationProvider(
                                                    {
                                                      'userId': userId,
                                                      'unitId': unitId,
                                                    },
                                                  ),
                                                );
                                                return qualification.when(
                                                  data: (isQualified) => Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 6,
                                                        ),
                                                    child: Text(
                                                      isQualified
                                                          ? 'Qualified for membership'
                                                          : 'Not qualified',
                                                      style: TextStyle(
                                                        color: isQualified
                                                            ? kSuccess
                                                            : kDanger,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                  loading: () =>
                                                      // const CircularProgressIndicator(),
                                                      const SizedBox.shrink(),
                                                  error: (e, _) =>
                                                      Text('Error: $e'),
                                                );
                                              },
                                            ),
                                            const SizedBox(height: 12),
                                            Wrap(
                                              spacing: 10,
                                              runSpacing: 10,
                                              children: [
                                                FilledButton.icon(
                                                  onPressed: () =>
                                                      _openUserTracking(
                                                        userId: userIdStr,
                                                        userName: userName,
                                                        applicationId: appId,
                                                      ),
                                                  icon: const Icon(
                                                    Icons.visibility_rounded,
                                                    size: 18,
                                                  ),
                                                  label: Text(
                                                    status == 'pending'
                                                        ? 'Review application'
                                                        : 'View details',
                                                  ),
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor: kPrimary,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 14,
                                                          vertical: 12,
                                                        ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                                if (deceasedElsewhere)
                                                  OutlinedButton.icon(
                                                    icon: const Icon(
                                                      Icons.info_outline,
                                                    ),
                                                    label: const Text(
                                                      'View deceased details',
                                                    ),
                                                    onPressed: () =>
                                                        _openDeceasedDetails(
                                                          userIdStr,
                                                        ),
                                                  ),
                                              ],
                                            ),
                                            if (deceasedElsewhere)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 10,
                                                ),
                                                child: Row(
                                                  children: const [
                                                    Icon(
                                                      Icons
                                                          .warning_amber_rounded,
                                                      size: 16,
                                                      color: kDanger,
                                                    ),
                                                    SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        'This user is marked as deceased in another dayung.',
                                                        style: TextStyle(
                                                          color: kDanger,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sheetDetailRow(IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: kSubText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: kSubText,
                fontFamily: 'OpenSans',
              ),
            ),
          ),
        ],
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: selected ? kPrimary : kSubText),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? kPrimary : kSubText,
                  fontFamily: 'Montserrat',
                ),
              ),
            ],
          ),
          if (selected) ...[
            const SizedBox(height: 3),
            Container(
              height: 2,
              width: label.length * 6.0,
              decoration: BoxDecoration(
                color: kPrimary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PdfViewer extends StatelessWidget {
  final Uint8List bytes;
  const _PdfViewer({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return _PdfViewerInner(bytes: bytes);
  }
}

class _PdfViewerInner extends StatefulWidget {
  final Uint8List bytes;
  const _PdfViewerInner({required this.bytes});

  @override
  State<_PdfViewerInner> createState() => _PdfViewerInnerState();
}

class _PdfViewerInnerState extends State<_PdfViewerInner> {
  late final PdfControllerPinch _controller;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openData(widget.bytes),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PdfViewPinch(
      controller: _controller,
      builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
        options: const DefaultBuilderOptions(),
        documentLoaderBuilder: (_) =>
            const Center(child: CircularProgressIndicator()),
        pageLoaderBuilder: (_) =>
            const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, err) => Center(child: Text('PDF error: $err')),
      ),
    );
  }
}

// Add this widget below _NavTab class or at the end of the file
class _TrackingStepTile extends StatelessWidget {
  final int stepNumber;
  final String title;
  final bool completed;
  final String? url;
  final VoidCallback? onView;

  const _TrackingStepTile({
    required this.stepNumber,
    required this.title,
    required this.completed,
    this.url,
    this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Step circle
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: completed ? kSuccess : kBorderColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: completed ? kSuccess : kBorderColor,
              width: 2,
            ),
          ),
          child: Center(
            child: completed
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : Text(
                    '$stepNumber',
                    style: const TextStyle(
                      color: kSubText,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: completed ? kSuccess : kText,
                ),
              ),
              Text(
                completed ? 'Uploaded' : 'Not uploaded',
                style: TextStyle(
                  color: completed ? kSuccess : kDanger,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        if (completed && onView != null)
          OutlinedButton.icon(
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: const Text('View'),
            onPressed: onView,
          ),
      ],
    );
  }
}
