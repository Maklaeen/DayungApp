import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geocoding/geocoding.dart';

const Color kBg = Color(0xFFFAFAF7);
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
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
      // Fetch approved claims (no join)
      final claims = await supabase
          .from('claims')
          .select('*')
          .eq('status', 'Approved')
          .eq('dayung_unit_id', widget.dayungUnitId);

      // Fetch death notices to filter out already set deceased
      final deathNotices = await supabase
          .from('death_notices')
          .select('user_id, beneficiary_id')
          .eq('dayung_unit_id', widget.dayungUnitId);

      final deceasedUserIds = deathNotices
          .where((n) => n['user_id'] != null)
          .map((n) => n['user_id'].toString())
          .toSet();
      final deceasedBeneficiaryIds = deathNotices
          .where((n) => n['beneficiary_id'] != null)
          .map((n) => n['beneficiary_id'].toString())
          .toSet();

      // For each claim, fetch user and beneficiary info
      List<Map<String, dynamic>> claimsWithDetails = [];
      for (final claim in claims) {
        Map<String, dynamic>? user;
        if (claim['user_id'] != null) {
          user = await supabase
              .from('users')
              .select('full_name, dob, is_deceased, date_of_death')
              .eq('id', claim['user_id'])
              .maybeSingle();
        }
        Map<String, dynamic>? beneficiary;
        if (claim['beneficiary_id'] != null) {
          beneficiary = await supabase
              .from('beneficiaries')
              .select('full_name, dob, status, user_id')
              .eq('id', claim['beneficiary_id'])
              .maybeSingle();
        }
        // Filter out already set deceased
        final isBeneficiary = claim['beneficiary_id'] != null;
        if (isBeneficiary) {
          if (!deceasedBeneficiaryIds.contains(
            claim['beneficiary_id'].toString(),
          )) {
            claimsWithDetails.add({
              ...claim,
              'users': user,
              'beneficiaries': beneficiary,
            });
          }
        } else {
          if (!deceasedUserIds.contains(claim['user_id'].toString())) {
            claimsWithDetails.add({
              ...claim,
              'users': user,
              'beneficiaries': beneficiary,
            });
          }
        }
      }

      setState(() {
        _approvedClaims = claimsWithDetails;
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(color: kPrimaryDark),
        title: const Text(
          'Set Deceased',
          style: TextStyle(
            color: kPrimaryDark,
            fontWeight: FontWeight.w800,
            fontSize: 22,
            fontFamily: 'Montserrat',
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search member or beneficiary',
                      prefixIcon: const Icon(Icons.search, color: kPrimaryDark),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: kPrimary.withOpacity(.2)),
                      ),
                    ),
                    style: const TextStyle(fontSize: 18, color: kNeutralText),
                    onChanged: _filter,
                  ),
                ),
                Expanded(
                  child: filteredClaims.isEmpty
                      ? const Center(
                          child: Text(
                            "No approved claims to process.",
                            style: TextStyle(
                              fontSize: 16,
                              color: kSubtleText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredClaims.length,
                          itemBuilder: (_, i) {
                            final c = filteredClaims[i];
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

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isBeneficiary
                                      ? Colors.purple
                                      : kPrimary,
                                  child: Icon(
                                    Icons.person,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 17,
                                    color: kNeutralText,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Type: ${isBeneficiary ? "Beneficiary" : "Member"}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: kSubtleText,
                                      ),
                                    ),
                                    if (dob != null)
                                      Text(
                                        'Date of Birth: ${_formatDate(dob)}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: kSubtleText,
                                        ),
                                      ),
                                    if (dod != null)
                                      Text(
                                        'Date of Death: ${_formatDate(dod)}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: kSubtleText,
                                        ),
                                      ),
                                    if (age != null)
                                      Text(
                                        'Age: $age',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: kSubtleText,
                                        ),
                                      ),
                                    if (deathCert != null &&
                                        deathCert.toString().isNotEmpty)
                                      TextButton.icon(
                                        icon: const Icon(
                                          Icons.picture_as_pdf,
                                          color: kPrimaryDark,
                                        ),
                                        label: const Text(
                                          'View Death Certificate',
                                        ),
                                        onPressed: () async {
                                          final url = deathCert.toString();
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
                                      ),
                                  ],
                                ),
                                trailing: ElevatedButton(
                                  onPressed: () => _setDeceased(c),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kPrimary,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Set Deceased'),
                                ),
                              ),
                            );
                          },
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
          'dob': _dateOnly(dob), // store DOB snapshot
          'deceased_age': computedAge, // store computed age
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
          'dob': _dateOnly(dob), // store DOB snapshot
          'deceased_age': computedAge, // store computed age
        });
      }

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
