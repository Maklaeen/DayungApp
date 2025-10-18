import 'package:flutter/material.dart';
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
  List<Map<String, dynamic>> _approvedClaims = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _fetchApprovedClaims();
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
        'latitude': (lat is num) ? lat.toDouble() : double.tryParse('$lat'),
        'longitude': (lng is num) ? lng.toDouble() : double.tryParse('$lng'),
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
          final locs = await locationFromAddress(addr);
          if (locs.isNotEmpty) {
            final pms = await placemarkFromCoordinates(
              locs.first.latitude,
              locs.first.longitude,
            );
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
        } catch (_) {}
      }
    }
    return {'latitude': null, 'longitude': null, 'barangay': brgy};
  }

  Future<void> _fetchApprovedClaims() async {
    setState(() => _loading = true);
    try {
      // 1) Fetch Approved claims for this unit via RPC (RLS-safe)
      final res = await supabase.rpc(
        'sec_list_approved_claims',
        params: {'p_unit_id': widget.dayungUnitId},
      );
      final claims = List<Map<String, dynamic>>.from(res);

      // 2) Filter out already in death_notices (unit-limited)
      final notices = await supabase
          .from('death_notices')
          .select('user_id, beneficiary_id, deceased_type') // CHANGED
          .eq('dayung_unit_id', widget.dayungUnitId);

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

      // 3) Bulk fetch user/beneficiary details for display
      final userIds = <String>{
        for (final c in claims)
          if (c['user_id'] != null) c['user_id'].toString(),
      }.toList();
      final benIds = <String>{
        for (final c in claims)
          if (c['beneficiary_id'] != null) c['beneficiary_id'].toString(),
      }.toList();

      final userMap = <String, Map<String, dynamic>>{};
      if (userIds.isNotEmpty) {
        final uRows = await supabase
            .from('users')
            .select('id, full_name, dob, is_deceased, date_of_death')
            .inFilter('id', userIds);
        for (final u in List<Map<String, dynamic>>.from(uRows)) {
          userMap[(u['id'] ?? '').toString()] = u;
        }
      }

      final benMap = <String, Map<String, dynamic>>{};
      if (benIds.isNotEmpty) {
        final bRows = await supabase
            .from('beneficiaries')
            .select('id, full_name, dob, status, user_id')
            .inFilter('id', benIds);
        for (final b in List<Map<String, dynamic>>.from(bRows)) {
          benMap[(b['id'] ?? '').toString()] = b;
        }
      }

      // 4) Assemble list with corrected skip logic
      final out = <Map<String, dynamic>>[];
      for (final c in claims) {
        final isBen = c['beneficiary_id'] != null;
        if (isBen) {
          final id = c['beneficiary_id']?.toString();
          if (id != null && deceasedBenIds.contains(id))
            continue; // only skip if that beneficiary already has a notice
          out.add({
            ...c,
            'users': userMap[c['user_id']?.toString()],
            'beneficiaries': benMap[id],
          });
        } else {
          final uid = c['user_id']?.toString();
          if (uid != null && deceasedMemberUserIds.contains(uid))
            continue; // only skip if the MEMBER already has a member-type notice
          out.add({...c, 'users': userMap[uid], 'beneficiaries': null});
        }
      }

      setState(() {
        _approvedClaims = out;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load claims: $e')));
    }
  }

  void _filter(String q) {
    setState(() {
      _search = q;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredClaims = _search.isEmpty
        ? _approvedClaims
        : _approvedClaims.where((c) {
            final isBeneficiary = c['beneficiary_id'] != null;
            final name = isBeneficiary
                ? (c['beneficiaries']?['full_name'] ?? '')
                : (c['users']?['full_name'] ?? '');
            return name.toLowerCase().contains(_search.toLowerCase());
          }).toList();

    return Scaffold(
      backgroundColor: kBg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 700;
          final horizontalPadding = isWide ? constraints.maxWidth * 0.15 : 20.0;
          final headerFontSize = isWide ? 28.0 : 20.0;

          return Column(
            children: [
              // Modern Header
              Container(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  isWide ? 60 : 32,
                  horizontalPadding,
                  isWide ? 48 : 32,
                ),
                decoration: BoxDecoration(
                  color: kPrimaryDark,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryDark.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.chevron_left_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Icon(
                      Icons.person_off_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Set Deceased',
                        style: TextStyle(
                          fontSize: headerFontSize,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontFamily: 'Montserrat',
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // Search Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        color: kPrimaryDark,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Search member or beneficiary',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            color: kNeutralText,
                          ),
                          onChanged: (q) => setState(() => _search = q),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Content
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: kPrimary),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchApprovedClaims,
                        child: filteredClaims.isEmpty
                            ? ListView(
                                children: [
                                  const SizedBox(height: 120),
                                  Center(
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          color: kSubText,
                                          size: 48,
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          "No approved claims to process.",
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: kSubtleText,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                itemCount: filteredClaims.length,
                                itemBuilder: (_, i) {
                                  final c = filteredClaims[i];
                                  final isBeneficiary =
                                      c['beneficiary_id'] != null;
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

                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    elevation: 3,
                                    color: kCardBg,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                        horizontal: 18,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              CircleAvatar(
                                                backgroundColor: isBeneficiary
                                                    ? Colors.purple.shade100
                                                    : kPrimary.withOpacity(
                                                        0.18,
                                                      ),
                                                child: Icon(
                                                  Icons.person,
                                                  color: isBeneficiary
                                                      ? Colors.purple
                                                      : kPrimary,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 18,
                                                    color: kPrimaryDark,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: isBeneficiary
                                                      ? Colors.purple.shade50
                                                      : kPrimary.withOpacity(
                                                          0.08,
                                                        ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  isBeneficiary
                                                      ? 'Beneficiary'
                                                      : 'Member',
                                                  style: TextStyle(
                                                    color: isBeneficiary
                                                        ? Colors.purple
                                                        : kPrimaryDark,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          _infoRow(
                                            Icons.cake,
                                            'DOB: ${_formatDate(dob)}',
                                          ),
                                          _infoRow(
                                            Icons.event,
                                            'Date of Death: ${_formatDate(dod)}',
                                          ),
                                          if (age != null)
                                            _infoRow(
                                              Icons.numbers,
                                              'Age: $age',
                                            ),
                                          if (deathCert != null &&
                                              deathCert.toString().isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 8.0,
                                              ),
                                              child: TextButton.icon(
                                                icon: const Icon(
                                                  Icons.picture_as_pdf,
                                                  color: kPrimaryDark,
                                                ),
                                                label: const Text(
                                                  'View Death Certificate',
                                                ),
                                                onPressed: () async {
                                                  final url = deathCert
                                                      .toString();
                                                  if (await canLaunchUrl(
                                                    Uri.parse(url),
                                                  )) {
                                                    await launchUrl(
                                                      Uri.parse(url),
                                                      mode: LaunchMode
                                                          .externalApplication,
                                                    );
                                                  } else {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
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
                                            ),
                                          const SizedBox(height: 10),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: ElevatedButton.icon(
                                              onPressed: () => _setDeceased(c),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: kPrimary,
                                                foregroundColor: Colors.white,
                                                minimumSize: const Size(
                                                  120,
                                                  40,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.check,
                                                size: 18,
                                              ),
                                              label: const Text('Set Deceased'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: kSubText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, color: kNeutralText),
            ),
          ),
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

  Future<void> _setDeceased(Map<String, dynamic> claim) async {
    final isBeneficiary = claim['beneficiary_id'] != null;
    final dod = claim['date_of_death'];
    final deathCert = claim['death_certificate_url'];
    final dayungId = claim['dayung_unit_id'];

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Missing full name. Please check the record.'),
        ),
      );
      return;
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

        await supabase.from('death_notices').insert({
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
        });
      } else {
        final uId = claim['user_id'];
        await supabase
            .from('users')
            .update({'is_deceased': true, 'date_of_death': _dateOnly(dod)})
            .eq('id', uId);

        await supabase.from('death_notices').insert({
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
        });
      }

      // NEW: mark this claim as Done
      try {
        await supabase
            .from('claims')
            .update({'status': 'Done'})
            .eq('id', (claim['id'] ?? '').toString());
      } catch (_) {}

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deceased status set and death notice created.'),
        ),
      );
      _fetchApprovedClaims();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
