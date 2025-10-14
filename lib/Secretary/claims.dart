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
      // Pass the last known unit id so we don't lose context
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
    // Watch for global Dayung switches
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

    // Only show spinner on full reload, not simple tab switch (optional)
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

      final tagged = await supabase
          .from('claims')
          .select(
            'id, user_id, title, description, status, date_submitted, '
            'death_certificate_url, beneficiary_id, date_of_death, dayung_unit_id',
          )
          .eq('status', statusTitle)
          .eq('dayung_unit_id', unitId)
          .order('date_submitted', ascending: false);

      final taggedList = List<Map<String, dynamic>>.from(tagged);

      List<Map<String, dynamic>> legacyList = [];
      if (allowedUserIds.isNotEmpty) {
        final legacy = await supabase
            .from('claims')
            .select(
              'id, user_id, title, description, status, date_submitted, '
              'death_certificate_url, beneficiary_id, date_of_death, dayung_unit_id',
            )
            .eq('status', statusTitle)
            .isFilter('dayung_unit_id', null)
            .inFilter('user_id', allowedUserIds)
            .order('date_submitted', ascending: false);
        legacyList = List<Map<String, dynamic>>.from(legacy);
      }

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
        deathIso.isEmpty)
      return null;
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

      // If approved, stop here. Finalize in deathnotice.dart via "Set Deceased".
      // Remove automatic users/beneficiaries update and death_notices insert here.

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
      backgroundColor: const Color(0xFFFAFAF7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,

        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: _searchField(),
              ),
              TabBar(
                controller: _tabController,
                // ...unchanged tab styling...
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
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          _loading
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
                              "No $currentStatus claims",
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

  Widget _infoBox(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        msg,
        style: const TextStyle(
          fontSize: 13,
          fontFamily: 'OpenSans',
          fontWeight: FontWeight.w600,
          color: kSubtleText,
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
      borderRadius: BorderRadius.circular(kRadius), // kCardRadius -> kRadius
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(
            kRadius,
          ), // kCardRadius -> kRadius
          border: Border.all(color: color.withOpacity(.35), width: 1.2),
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
            // ...status, title, desc, etc...
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
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
                          fontFamily: 'Montserrat',
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  '#${claim['id']}',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'OpenSans',
                    fontWeight: FontWeight.w600,
                    color: kSubtleText.withOpacity(.65),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'OpenSans',
                  height: 1.3,
                  color: kSubtleText,
                ),
              ),
            ],
            // --- INSERT THE FUTUREBUILDER HERE ---
            const SizedBox(height: 10),
            FutureBuilder<Map<String, dynamic>>(
              future: getDeceasedInfo(claim),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final deceased = snapshot.data!;
                final dob = (deceased['dob'] ?? '').toString();
                final dod = (deceased['date_of_death'] ?? '').toString();
                final age = _computeAge(dob, dod);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Deceased: ${deceased['name']}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kNeutralText,
                      ),
                    ),
                    if (dob.isNotEmpty)
                      Text(
                        'Date of Birth: $dob',
                        style: const TextStyle(
                          fontSize: 13,
                          color: kSubtleText,
                        ),
                      ),
                    if (dod.isNotEmpty)
                      Text(
                        'Date of Death: $dod',
                        style: const TextStyle(
                          fontSize: 13,
                          color: kSubtleText,
                        ),
                      ),
                    if (age != null)
                      Text(
                        'Age at death: $age years',
                        style: const TextStyle(
                          fontSize: 13,
                          color: kSubtleText,
                        ),
                      ),

                    const SizedBox(height: 18),
                    if ((claim['death_certificate_url'] ?? '')
                        .toString()
                        .isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.visibility),
                        label: const Text('View Death Certificate'),
                        onPressed: () async {
                          final url = claim['death_certificate_url'].toString();
                          // --- Image/PDF viewer logic here ---
                          if (url.endsWith('.jpg') ||
                              url.endsWith('.jpeg') ||
                              url.endsWith('.png')) {
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
                          } else if (url.endsWith('.pdf')) {
                            if (await canLaunchUrl(Uri.parse(url))) {
                              await launchUrl(
                                Uri.parse(url),
                                mode: LaunchMode.externalApplication,
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Could not open PDF file.'),
                                ),
                              );
                            }
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
                  ],
                );
              },
            ),
            // --- END FUTUREBUILDER ---
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
                      fontWeight: FontWeight.w600,
                      color: kSubtleText,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Colors.black38,
                ),
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

    // Since this page is already scoped to the selected unit, just read it from provider
    final dayungName =
        context.read<DayungUnitProvider>().dayungUnit ?? 'Dayung';

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
              const SizedBox(height: 18), // <-- Insert here
              FutureBuilder<Map<String, dynamic>>(
                future: getDeceasedInfo(claim),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final deceased = snapshot.data!;
                  final dob = (deceased['dob'] ?? '').toString();
                  final dod = (deceased['date_of_death'] ?? '').toString();
                  final age = _computeAge(dob, dod);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deceased: ${deceased['name']}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: kNeutralText,
                        ),
                      ),
                      if (dob.isNotEmpty) const SizedBox(height: 4),
                      if (dob.isNotEmpty)
                        Text(
                          'Date of Birth: $dob',
                          style: const TextStyle(
                            fontSize: 13,
                            color: kSubtleText,
                          ),
                        ),
                      if (dod.isNotEmpty)
                        Text(
                          'Date of Death: $dod',
                          style: const TextStyle(
                            fontSize: 13,
                            color: kSubtleText,
                          ),
                        ),
                      if (age != null)
                        Text(
                          'Age at death: $age years',
                          style: const TextStyle(
                            fontSize: 13,
                            color: kSubtleText,
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),

              if ((claim['death_certificate_url'] ?? '').toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.visibility),
                    label: const Text('View Death Certificate'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () async {
                      final url = claim['death_certificate_url'].toString();
                      final isImage =
                          url.endsWith('.jpg') ||
                          url.endsWith('.jpeg') ||
                          url.endsWith('.png');
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
                        // Download PDF to local file
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
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    tooltip: 'Close',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      } else {
                        // Fallback: open in browser
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
