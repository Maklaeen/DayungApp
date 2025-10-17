import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class DeathNoticeDetail extends StatefulWidget {
  final int? noticeId;
  final int? dayungUnitId;

  // Optional prefilled values (legacy/direct)
  final String? name;
  final String? date; // date_of_death
  final String? birthDate;
  final double? latitude;
  final double? longitude;
  final String? barangay;

  const DeathNoticeDetail({
    Key? key,
    required String name,
    required String date,
    this.birthDate,
    this.latitude,
    this.longitude,
    this.barangay,
  }) : noticeId = null,
       dayungUnitId = null,
       name = name,
       date = date,
       super(key: key);

  const DeathNoticeDetail.byNoticeId({
    Key? key,
    required this.noticeId,
    this.dayungUnitId,
    this.name,
    this.date,
    this.birthDate,
    this.latitude,
    this.longitude,
    this.barangay,
  }) : super(key: key);

  @override
  State<DeathNoticeDetail> createState() => _DeathNoticeDetailState();
}

class _DeathNoticeDetailState extends State<DeathNoticeDetail> {
  final _sb = Supabase.instance.client;

  // Fetched/derived fields
  String? _fName;
  String? _fDateOfDeath; // ISO
  String? _fBirthDate; // ISO
  double? _fLat;
  double? _fLng;
  String? _fBarangay;
  int? _fStoredAge; // snapshot age from death_notices if present

  String? _locationName;
  // ignore: unused_field
  GoogleMapController? _mapController;

  bool _loading = false;
  String? _error;
  bool _membersLoading = false;
  List<Map<String, dynamic>> _paidMembers = [];
  List<Map<String, dynamic>> _unpaidMembers = [];

  @override
  void initState() {
    super.initState();
    _hydrateFromPassedProps();
    _loadIfNeeded();
    _fetchMembersForNotice();
  }

  Future<void> _fetchMembersForNotice() async {
    if (widget.noticeId == null || widget.dayungUnitId == null) return;
    setState(() => _membersLoading = true);

    final sb = Supabase.instance.client;

    // 1) Approved members in this dayung unit
    final appsRes = await sb
        .from('applications')
        .select('user_id')
        .eq('dayung_unit_id', widget.dayungUnitId as Object)
        .eq('status', 'approved');

    final approvedIds = List<Map<String, dynamic>>.from(
      appsRes,
    ).map((e) => e['user_id'].toString()).toSet();

    // 2) Payments for this death notice in this dayung unit
    final paysRes = await sb
        .from('payments')
        .select('user_id,status,dayung_unit_id')
        .eq('death_notice_id', widget.noticeId as Object)
        .eq('dayung_unit_id', widget.dayungUnitId as Object);

    final pays = List<Map<String, dynamic>>.from(paysRes);

    final paidIds = pays
        .where((p) => p['status'] == 'paid')
        .map((p) => p['user_id'].toString())
        .where(approvedIds.contains)
        .toSet();

    final pendingIds = pays
        .where((p) => p['status'] == 'pending')
        .map((p) => p['user_id'].toString())
        .where(approvedIds.contains)
        .toSet();

    // 3) Fetch user details for each set
    Future<List<Map<String, dynamic>>> loadUsers(Set<String> ids) async {
      if (ids.isEmpty) return [];
      final res = await sb
          .from('users')
          .select('id, full_name')
          .inFilter('id', ids.toList())
          .order('full_name', ascending: true);
      return List<Map<String, dynamic>>.from(res);
    }

    final paid = await loadUsers(paidIds);
    final unpaid = await loadUsers(pendingIds);

    setState(() {
      _paidMembers = paid;
      _unpaidMembers = unpaid;
      _membersLoading = false;
    });
  }

  void _hydrateFromPassedProps() {
    _fName = widget.name;
    _fDateOfDeath = widget.date;
    _fBirthDate = widget.birthDate;
    _fLat = widget.latitude;
    _fLng = widget.longitude;
    _fBarangay = widget.barangay;
  }

  Future<void> _loadIfNeeded() async {
    if (widget.noticeId == null) {
      await _resolveLocation();
      setState(() => _loading = false);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1) Read from death_notices (no joins -> avoids RLS issues)
      final notice = await _sb
          .from('death_notices')
          .select(
            'id, name, dob, deceased_age, date_of_death, barangay, latitude, longitude, deceased_type, user_id, beneficiary_id',
          )
          .eq('id', widget.noticeId!)
          .maybeSingle();

      if (notice == null) {
        setState(() {
          _error = 'Notice not found';
          _loading = false;
        });
        return;
      }

      _fName = (notice['name'] ?? _fName)?.toString();
      _fBirthDate = (notice['dob'] ?? _fBirthDate)?.toString();
      _fDateOfDeath = (notice['date_of_death'] ?? _fDateOfDeath)?.toString();
      _fBarangay = (notice['barangay'] ?? _fBarangay)?.toString();
      _fLat = _toDouble(notice['latitude']) ?? _fLat;
      _fLng = _toDouble(notice['longitude']) ?? _fLng;
      _fStoredAge = _toInt(notice['deceased_age']);

      final benId = notice['beneficiary_id'];
      final userId = (notice['user_id'] ?? '').toString();

      // 2) Fallbacks: if DOB (or DOD/Name) is missing, fetch from related tables
      if ((_fBirthDate == null || _fBirthDate!.isEmpty) && benId != null) {
        try {
          final ben = await _sb
              .from('beneficiaries')
              .select('full_name, dob')
              .eq('id', benId)
              .maybeSingle();
          final benDob = (ben?['dob'] ?? '').toString();
          final benName = (ben?['full_name'] ?? '').toString();
          if ((_fBirthDate == null || _fBirthDate!.isEmpty) &&
              benDob.isNotEmpty) {
            _fBirthDate = benDob;
          }
          if ((_fName == null || _fName!.isEmpty) && benName.isNotEmpty) {
            _fName = benName;
          }
        } catch (_) {
          // ignore; RLS or not found
        }
      }

      if ((_fBirthDate == null || _fBirthDate!.isEmpty) && userId.isNotEmpty) {
        try {
          final u = await _sb
              .from('users')
              .select('full_name, dob, date_of_death, address')
              .eq('id', userId)
              .maybeSingle();
          final uDob = (u?['dob'] ?? '').toString();
          final uDod = (u?['date_of_death'] ?? '').toString();
          final uName = (u?['full_name'] ?? '').toString();
          final addr = (u?['address'] ?? '').toString();
          if ((_fBirthDate == null || _fBirthDate!.isEmpty) &&
              uDob.isNotEmpty) {
            _fBirthDate = uDob;
          }
          if ((_fDateOfDeath == null || _fDateOfDeath!.isEmpty) &&
              uDod.isNotEmpty) {
            _fDateOfDeath = uDod;
          }
          if ((_fName == null || _fName!.isEmpty) && uName.isNotEmpty) {
            _fName = uName;
          }
          if ((_fBarangay == null || _fBarangay!.isEmpty) && addr.isNotEmpty) {
            _fBarangay = addr;
          }
        } catch (_) {
          // ignore; RLS or not found
        }
      }

      // 3) Resolve location label/coords if needed
      await _resolveLocation();

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load: $e';
        _loading = false;
      });
    }
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  Future<void> _resolveLocation() async {
    // 1) If we have coords, do reverse geocode for display name
    if (_fLat != null && _fLng != null) {
      try {
        final placemarks = await placemarkFromCoordinates(
          _fLat!,
          _fLng!,
        ).timeout(const Duration(seconds: 10), onTimeout: () => []);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = [
            if ((p.street ?? '').isNotEmpty) p.street!,
            if ((p.locality ?? '').isNotEmpty) p.locality!,
            if ((p.administrativeArea ?? '').isNotEmpty) p.administrativeArea!,
            if ((p.country ?? '').isNotEmpty) p.country!,
          ];
          _locationName = parts.isNotEmpty
              ? parts.join(', ')
              : 'Location unavailable';
        } else {
          _locationName = 'Location unavailable';
        }
      } catch (_) {
        _locationName = 'Location unavailable';
      }
      return;
    }

    // 2) If no coords but we have a barangay/address string, forward-geocode it
    if ((_fBarangay ?? '').toString().isNotEmpty) {
      _locationName = _fBarangay; // show text immediately
      try {
        final results = await locationFromAddress(
          _fBarangay!,
        ).timeout(const Duration(seconds: 10), onTimeout: () => []);
        if (results.isNotEmpty) {
          _fLat = results.first.latitude;
          _fLng = results.first.longitude;
        }
      } catch (_) {
        // keep text-only fallback
      }
      return;
    }

    // 3) Nothing available
    _locationName = 'Location unavailable';
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    DateTime? dt =
        DateTime.tryParse(iso) ?? DateTime.tryParse('${iso}T00:00:00');
    if (dt == null) return '—';
    const months = [
      '',
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
    return '${months[dt.month]} ${dt.day}, ${dt.year}';
  }

  int? _computeAge(String? birthIso, String? deathIso) {
    if (birthIso == null || deathIso == null) return null;
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
    if (!hadBirthday) age--;
    if (age < 0 || age > 150) return null;
    return age;
  }

  Future<void> _openInMaps() async {
    if (_fLat == null || _fLng == null) return;
    final lat = _fLat!.toStringAsFixed(6);
    final lng = _fLng!.toStringAsFixed(6);
    final label = Uri.encodeComponent(_fName ?? 'Vigil Location');
    final apple = Uri.parse('http://maps.apple.com/?ll=$lat,$lng&q=$label');
    final google = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    if (await canLaunchUrl(google)) {
      await launchUrl(google, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(apple)) {
      await launchUrl(apple, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final name = _fName ?? 'Death Notice';
    final dDate = _fDateOfDeath;
    final bDate = _fBirthDate;
    final age = _fStoredAge ?? _computeAge(bDate, dDate);

    return SafeArea(
      top: false,
      child: Container(
        height: screenHeight * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text(
                    'In Loving Memory',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48), // Balance the close button
                ],
              ),
            ),
            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          // Memorial Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0D47A1), Color(0xFF3B82F6)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF0D47A1,
                                  ).withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.favorite,
                                  color: Colors.white,
                                  size: 32,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'In Loving Memory Of',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  name,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Date Card
                          _buildInfoCard(
                            icon: Icons.calendar_today,
                            title: 'Date of Death',
                            value: _fmtDate(dDate),
                            subtitle: age != null ? 'Aged $age years' : null,
                          ),
                          const SizedBox(height: 16),
                          // Location Card
                          _buildInfoCard(
                            icon: Icons.location_on,
                            title: 'Vigil Location',
                            value:
                                _fBarangay ??
                                _locationName ??
                                'Location unavailable',
                            showMapButton: _fLat != null && _fLng != null,
                          ),
                          if (_fLat != null && _fLng != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              height: 200,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: GoogleMap(
                                  initialCameraPosition: CameraPosition(
                                    target: LatLng(_fLat!, _fLng!),
                                    zoom: 16,
                                  ),
                                  markers: {
                                    Marker(
                                      markerId: const MarkerId('vigil'),
                                      position: LatLng(_fLat!, _fLng!),
                                      infoWindow: InfoWindow(
                                        title: name,
                                        snippet:
                                            _fBarangay ?? _locationName ?? '',
                                      ),
                                    ),
                                  },
                                  myLocationButtonEnabled: false,
                                  zoomControlsEnabled: true,
                                  onMapCreated: (controller) {
                                    _mapController = controller;
                                  },
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          // Memorial Message
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.favorite,
                                  color: const Color(0xFF0D47A1),
                                  size: 24,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'With deepest respect and remembrance.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    String? subtitle,
    bool showMapButton = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF0D47A1), size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              if (showMapButton)
                GestureDetector(
                  onTap: _openInMaps,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D47A1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.directions, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'Maps',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }
}
