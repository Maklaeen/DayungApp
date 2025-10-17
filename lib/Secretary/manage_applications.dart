import 'dart:typed_data';
import 'package:pdfx/pdfx.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:url_launcher/url_launcher.dart';

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

class _SecretaryApplicationsPageState extends State<SecretaryApplicationsPage> {
  final _supabase = Supabase.instance.client;

  String _filter = 'pending'; // pending | approved | rejected
  bool _loading = true;
  List<Map<String, dynamic>> _apps = [];
  Set<String> _deceasedUserIds = {};

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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.92;
        return SizedBox(
          height: height,
          child: Column(
            children: [
              // Header with Back/Close
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_downward),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Text(
                        'Death certificate',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48), // balance the back button space
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Builder(
                  builder: (_) {
                    if (kind == 'png' || kind == 'jpg') {
                      // Show image with pinch-zoom
                      return InteractiveViewer(
                        child: Image.network(
                          uri.toString(),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const Center(child: Text('Failed to load image')),
                        ),
                      );
                    }
                    if (kind == 'pdf') {
                      // Load PDF bytes then render with Pdfx
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
                          return _PdfViewer(bytes: bytes);
                        },
                      );
                    }
                    // Unknown type -> suggest external
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Unsupported file type. Open in browser?'),
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
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.92;
        return SizedBox(
          height: height,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_downward),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Text(
                        'Deceased details',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(),
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

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          unitName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (name.isNotEmpty) Text('Name: $name'),
                        if (type.isNotEmpty) Text('Type: $type'),
                        if (dob != null && dob.isNotEmpty)
                          Text('Birthday: $dob'),
                        if (age != null && age.isNotEmpty) Text('Age: $age'),
                        if (dod != null && dod.isNotEmpty)
                          Text('Date of death: $dod'),
                        if (loc.isNotEmpty) Text('Location: $loc'),
                        if (cert.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.picture_as_pdf),
                              label: const Text('Open death certificate'),
                              onPressed: () => _openCertificateViewer(cert),
                            ),
                          ),
                      ],
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

    setState(() => _loading = true);
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
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Load failed: ${e.message}')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unexpected error loading applications')),
      );
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
      await _supabase.rpc(
        'approve_application',
        params: {'p_application_id': applicationId},
      );
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

  @override
  Widget build(BuildContext context) {
    final dayungName =
        context.watch<DayungUnitProvider>().dayungUnit ?? 'Dayung';
    return Scaffold(
      backgroundColor: kCardBg,
      body: SafeArea(
        child: Column(
          children: [
            // Modern App Bar
            Container(
              padding: const EdgeInsets.fromLTRB(8, 36, 20, 28),
              decoration: const BoxDecoration(
                color: kPrimaryDark,
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
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.assignment_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Applications',
                      style: TextStyle(
                        fontSize: 22,
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
            // Navigation Tabs
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                onRefresh: () => _fetchApplications(forUnitId: _currentUnitId),
                color: kPrimary,
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
                                'Loading applications...',
                                style: TextStyle(
                                  color: kSubText,
                                  fontSize: 16,
                                  fontFamily: 'OpenSans',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _apps.isEmpty
                    ? Center(
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
                                Icons.inbox_rounded,
                                size: 48,
                                color: kSubText,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No applications found',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: kText,
                                  fontFamily: 'Montserrat',
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'No applications match the selected filter',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: kSubText,
                                  fontFamily: 'OpenSans',
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _apps.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            final app = _apps[i];
                            final user = app['users'] as Map<String, dynamic>?;
                            final status = (app['status'] ?? '').toString();
                            final appliedAt = DateTime.tryParse(
                              app['applied_at']?.toString() ?? '',
                            );
                            final userIdStr = (app['user_id'] ?? '').toString();
                            final deceasedElsewhere = _deceasedUserIds.contains(
                              userIdStr,
                            );

                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: kCardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: kBorderColor.withOpacity(0.3),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: kPrimary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      (user?['full_name'] ?? 'M')[0]
                                          .toString()
                                          .toUpperCase(),
                                      style: const TextStyle(
                                        color: kPrimary,
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
                                        Text(
                                          user?['full_name'] ?? 'Member',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            color: kText,
                                            fontFamily: 'Montserrat',
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          dayungName,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: kSubText,
                                            fontFamily: 'OpenSans',
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (appliedAt != null)
                                          Text(
                                            'Applied: ${appliedAt.toLocal().toString().split(' ')[0]}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: kSubText,
                                              fontFamily: 'OpenSans',
                                            ),
                                          ),
                                        if (deceasedElsewhere)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Row(
                                              children: const [
                                                Icon(
                                                  Icons.warning_amber_rounded,
                                                  size: 16,
                                                  color: Colors.red,
                                                ),
                                                SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    'This user is marked as deceased in other dayung.',
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (deceasedElsewhere)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            child: OutlinedButton.icon(
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
                                          ),
                                      ],
                                    ),
                                  ),
                                  _buildActions(
                                    status,
                                    app['id'] as int,
                                    deceasedElsewhere,
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
        ),
      ),
    );
  }

  Widget _buildActions(
    String status,
    int applicationId, [
    bool deceasedElsewhere = false,
  ]) {
    if (status == 'pending') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Reject',
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => _reject(applicationId),
          ),
          IconButton(
            tooltip: 'Approve',
            icon: const Icon(Icons.check_circle, color: Colors.green),
            onPressed: () =>
                _approve(applicationId, deceasedElsewhere: deceasedElsewhere),
          ),
        ],
      );
    }
    if (status == 'approved') {
      return const Icon(Icons.verified, color: Colors.green);
    }
    if (status == 'rejected') {
      return const Icon(Icons.cancel, color: Colors.redAccent);
    }
    return Text(status);
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
  const _PdfViewer({super.key, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return _PdfViewerInner(bytes: bytes);
  }
}

class _PdfViewerInner extends StatefulWidget {
  final Uint8List bytes;
  const _PdfViewerInner({super.key, required this.bytes});

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
