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
    final scale = MediaQuery.of(context).textScaleFactor.clamp(1.0, 1.3);
    final name = _fName ?? 'Death Notice';
    final dDate = _fDateOfDeath;
    final bDate = _fBirthDate;
    final age = _fStoredAge ?? _computeAge(bDate, dDate);

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
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(
                                Icons.arrow_back,
                                size: 28,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.inventory_2_rounded,
                            size: 36,
                            color: Colors.black54,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'In loving\nmemory of:',
                              style: TextStyle(
                                fontSize: 28,
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
                              style: const TextStyle(
                                fontSize: 34,
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
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (age != null)
                              Text(
                                'Aged $age years',
                                style: const TextStyle(
                                  fontSize: 18,
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
                          const Text(
                            'Location of Vigil:',
                            style: TextStyle(
                              fontSize: 22,
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
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  )
                                : (_fLat == null || _fLng == null)
                                ? const Text("Location unavailable")
                                : Text(
                                    _locationName ??
                                        'Lat: ${_fLat!.toStringAsFixed(4)}\n'
                                            'Lng: ${_fLng!.toStringAsFixed(4)}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                      height: 1.3,
                                    ),
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
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'With deepest respect and remembrance.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontStyle: FontStyle.italic,
                          color: Colors.black87,
                        ),
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
