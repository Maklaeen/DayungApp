import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class DeathNoticeDetail extends StatefulWidget {
  final int? noticeId;
  final int? dayungUnitId;

  // Optional prefilled values (used as optimistic UI or for legacy usage)
  final String? name;
  final String? date; // date_of_death
  final String? birthDate;
  final double? latitude;
  final double? longitude;
  final String? barangay;

  // Legacy usage: pass name/date directly (no fetch)
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

  // Preferred: fetch by noticeId
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

  String? _locationName;
  GoogleMapController? _mapController;

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _hydrateFromPassedProps();
    _loadIfNeeded();
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
      final res = await _sb
          .from('death_notices')
          .select(
            // Use explicit FK join alias to ensure users.* is fetched
            'id, name, date_of_death, barangay, latitude, longitude, user_id, '
            'user:users!death_notices_user_id_fkey(dob, date_of_death, full_name, address)',
          )
          .eq('id', widget.noticeId as Object)
          .limit(1);

      final rows = (res as List?)?.cast<Map<String, dynamic>>() ?? const [];
      if (rows.isEmpty) {
        setState(() {
          _error = 'Notice not found';
          _loading = false;
        });
        return;
      }

      final row = rows.first;
      final user = (row['user'] as Map?)?.cast<String, dynamic>();
      final userId = (row['user_id'] ?? '').toString();

      // Name: prefer notice name, then user full_name
      final noticeName = (row['name'] ?? '').toString();
      final userName = (user?['full_name'] ?? '').toString();
      _fName = noticeName.isNotEmpty
          ? noticeName
          : (userName.isNotEmpty ? userName : _fName);

      // Dates: prefer users.date_of_death, then notice.date_of_death
      final userDod = (user?['date_of_death'] ?? '').toString();
      final noticeDod = (row['date_of_death'] ?? '').toString();
      _fDateOfDeath = userDod.isNotEmpty
          ? userDod
          : (noticeDod.isNotEmpty ? noticeDod : _fDateOfDeath);

      // DOB from users.dob
      final userDob = (user?['dob'] ?? '').toString();
      _fBirthDate = userDob.isNotEmpty ? userDob : _fBirthDate;

      if ((_fBirthDate == null || _fBirthDate!.isEmpty) && userId.isNotEmpty) {
        await _hydrateFromUser(userId);
      }

      // Location fields
      _fBarangay = (row['barangay'] ?? _fBarangay)?.toString();
      // If user's address exists and barangay empty, use it as fallback text
      final userAddress = (user?['address'] ?? '').toString();
      if ((_fBarangay == null || _fBarangay!.isEmpty) &&
          userAddress.isNotEmpty) {
        _fBarangay = userAddress;
      }

      _fLat = _toDouble(row['latitude']) ?? _fLat;
      _fLng = _toDouble(row['longitude']) ?? _fLng;

      // Fallback fetch if nested join failed due to RLS or missing relation
      if ((userDob.isEmpty ||
              _fDateOfDeath == null ||
              _fDateOfDeath!.isEmpty) &&
          userId.isNotEmpty) {
        await _hydrateFromUser(userId);
      }

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

  Future<void> _hydrateFromUser(String userId) async {
    try {
      final res = await _sb
          .from('users')
          .select('dob, date_of_death, full_name, address')
          .eq('id', userId)
          .limit(1);

      final rows = (res as List?)?.cast<Map<String, dynamic>>() ?? const [];
      if (rows.isEmpty) return;

      final u = rows.first;
      final dob = (u['dob'] ?? '').toString();
      final dod = (u['date_of_death'] ?? '').toString();
      final name = (u['full_name'] ?? '').toString();
      final addr = (u['address'] ?? '').toString();

      if ((_fBirthDate == null || _fBirthDate!.isEmpty) && dob.isNotEmpty) {
        _fBirthDate = dob;
      }
      if ((_fDateOfDeath == null || _fDateOfDeath!.isEmpty) && dod.isNotEmpty) {
        _fDateOfDeath = dod;
      }
      if ((_fName == null || _fName!.isEmpty) && name.isNotEmpty) {
        _fName = name;
      }
      if ((_fBarangay == null || _fBarangay!.isEmpty) && addr.isNotEmpty) {
        _fBarangay = addr;
      }
    } catch (_) {
      // ignore; best-effort fallback
    }
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
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
        // Forward geocode to get coords so map can render
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

  String _fmtDate(String? isoOrHuman) {
    if (isoOrHuman == null || isoOrHuman.isEmpty) return '—';
    DateTime? dt = DateTime.tryParse(isoOrHuman);
    dt ??= DateTime.tryParse('${isoOrHuman}T00:00:00');

    // If not parseable, hide non-ISO human strings instead of echoing them
    if (dt == null) {
      final s = isoOrHuman.trim();
      final looksIso = RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s);
      return looksIso ? s : '—';
    }

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
    if (!hadBirthday) age -= 1;
    return age.clamp(0, 150);
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
    final scale = MediaQuery.of(context).textScaleFactor.clamp(1.0, 1.3);
    final name = _fName ?? 'Death Notice';
    final dDate = _fDateOfDeath;
    final bDate = _fBirthDate;
    final age = _computeAge(bDate, dDate);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        automaticallyImplyLeading: false,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Text(
          'Dayung',
          style: TextStyle(
            fontSize: 24 * scale,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () => Navigator.pop(context),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.arrow_back,
                                size: 28 * scale,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Replace with your asset or use an icon
                          Icon(
                            Icons.inventory_2_rounded,
                            size: 36 * scale,
                            color: Colors.black54,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'In loving\nmemory of:',
                              style: TextStyle(
                                fontSize: 28 * scale,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Name card
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 20,
                      ),
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 30,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade800,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text(
                              name,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 34 * scale,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Dates + Age
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              '${_fmtDate(bDate)} – ${_fmtDate(dDate)}',
                              style: TextStyle(
                                fontSize: 20 * scale,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (age != null)
                              Text(
                                'Aged $age years',
                                style: TextStyle(
                                  fontSize: 18 * scale,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.black54,
                                  height: 1.3,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Location
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Text(
                            'Location of Vigil:',
                            style: TextStyle(
                              fontSize: 22 * scale,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const Spacer(),
                          if (_fLat != null && _fLng != null)
                            TextButton.icon(
                              onPressed: _openInMaps,
                              icon: const Icon(Icons.directions),
                              label: const Text('Open in Maps'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          height: 80,
                          width: double.infinity,
                          color: Colors.grey.shade200,
                          child: Center(
                            child: (_fBarangay ?? '').isNotEmpty
                                ? Text(
                                    _fBarangay!,
                                    style: TextStyle(
                                      fontSize: 20 * scale,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                    textAlign: TextAlign.center,
                                  )
                                : (_fLat == null || _fLng == null)
                                ? const Text("Location unavailable")
                                : Text(
                                    _locationName ??
                                        'Lat: ${_fLat!.toStringAsFixed(4)}\n'
                                            'Lng: ${_fLng!.toStringAsFixed(4)}',
                                    style: TextStyle(
                                      fontSize: 18 * scale,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                      height: 1.3,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                          ),
                        ),
                      ),
                    ),

                    if (_fLat != null && _fLng != null) ...[
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          height: 220,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
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
                                    snippet: _fBarangay ?? _locationName ?? '',
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
                      ),
                    ],

                    const SizedBox(height: 28),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'With deepest respect and remembrance.',
                        style: TextStyle(
                          fontSize: 26 * scale,
                          fontStyle: FontStyle.italic,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}
