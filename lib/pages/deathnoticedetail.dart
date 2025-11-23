import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

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

  String? _fName;
  String? _fDateOfDeath;
  String? _fBirthDate;
  double? _fLat;
  double? _fLng;
  String? _fBarangay;
  int? _fStoredAge;

  double? _userLat;
  double? _userLng;
  double? _distanceMeters;
  bool _locPermissionDenied = false;

  String? _locationName;
  ml.MaplibreMapController? _mapController;
  bool _styleLoaded = false;
  ml.Circle? _vigilCircle;
  ml.Circle? _userCircle;
  ml.Line? _routeLine;

  StreamSubscription<Position>? _posSub;
  bool _autoFollow = true;
  double? _initialDistance; // baseline distance for fade
  static const double _fadeRemoveThreshold = 40; // meters (remove line)
  static const Duration _posInterval = Duration(seconds: 2);

  bool _loading = false;
  String? _error;
  bool _membersLoading = false;
  List<Map<String, dynamic>> _paidMembers = [];
  List<Map<String, dynamic>> _unpaidMembers = [];

  Future<void> _updateRouteLine() async {
    if (!_styleLoaded || _mapController == null) return;
    final hasBoth =
        _userLat != null && _userLng != null && _fLat != null && _fLng != null;
    if (!hasBoth) {
      if (_routeLine != null) {
        try {
          await _mapController!.removeLine(_routeLine!);
        } catch (_) {}
        _routeLine = null;
      }
      return;
    }
    final coords = <ml.LatLng>[
      ml.LatLng(_userLat!, _userLng!),
      ml.LatLng(_fLat!, _fLng!),
    ];
    if (_routeLine == null) {
      try {
        _routeLine = await _mapController!.addLine(
          ml.LineOptions(
            geometry: coords,
            lineColor: "#0D47A1",
            lineWidth: 4.0,
            lineOpacity: 0.75,
          ),
        );
      } catch (_) {}
    } else {
      try {
        await _mapController!.updateLine(
          _routeLine!,
          ml.LineOptions(geometry: coords),
        );
      } catch (_) {}
    }
  }

  Widget _webMap(double lat, double lng, String name) {
    return RepaintBoundary(
      key: ValueKey('web_map_${lat}_${lng}'),
      child: ml.MapLibreMap(
        styleString: 'https://demotiles.maplibre.org/style.json',
        initialCameraPosition: ml.CameraPosition(
          target: ml.LatLng(lat, lng),
          zoom: 16,
        ),
        onMapCreated: (ml.MaplibreMapController controller) async {
          _mapController = controller;
          _addSymbolsToMap();
        },
        myLocationEnabled: false,
        compassEnabled: false,
        rotateGesturesEnabled: true,
        tiltGesturesEnabled: false,
        attributionButtonMargins: const Point(6, 6),
        logoViewMargins: const Point(6, 6),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _hydrateFromPassedProps();
    _loadIfNeeded();
    _fetchMembersForNotice();
    _fetchUserLocation();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchUserLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() => _locPermissionDenied = true);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _locPermissionDenied = true);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      _userLat = pos.latitude;
      _userLng = pos.longitude;
      _computeDistance();
      _initialDistance ??= _distanceMeters;
      setState(() {});
      await _updateUserCircle();
      await _fetchRoadRoute(); // initial route
      _startLiveLocation(); // begin streaming
    } catch (_) {
      setState(() => _locPermissionDenied = true);
    }
  }

  void _startLiveLocation() {
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3, // meters
      ),
    ).listen(_onPositionUpdate, onError: (_) {});
  }

  void _onPositionUpdate(Position p) async {
    _userLat = p.latitude;
    _userLng = p.longitude;
    _computeDistance();
    if (_initialDistance == null && _distanceMeters != null) {
      _initialDistance = _distanceMeters;
    }
    if (!mounted) return;
    await _updateUserCircle();
    _updateRouteFade(); // fade/remove line
    if (_autoFollow &&
        _mapController != null &&
        _userLat != null &&
        _userLng != null) {
      _mapController!.animateCamera(
        ml.CameraUpdate.newLatLng(ml.LatLng(_userLat!, _userLng!)),
      );
    }
    setState(() {});
  }

  void _updateRouteFade() async {
    if (_routeLine == null ||
        _initialDistance == null ||
        _distanceMeters == null ||
        _mapController == null)
      return;

    final remaining = _distanceMeters!;
    if (remaining <= _fadeRemoveThreshold) {
      try {
        await _mapController!.removeLine(_routeLine!);
      } catch (_) {}
      _routeLine = null;
      return;
    }

    final ratio = (remaining / _initialDistance!).clamp(0.0, 1.0);
    // Opacity decreases as user approaches
    final opacity = (ratio * 0.85).clamp(0.15, 0.85);
    try {
      await _mapController!.updateLine(
        _routeLine!,
        ml.LineOptions(
          geometry: _routeLine!.options.geometry,
          lineColor: '#FF5722',
          lineWidth: 4.0,
          lineOpacity: opacity,
        ),
      );
    } catch (_) {}
  }

  void _toggleFollow() {
    setState(() => _autoFollow = !_autoFollow);
    if (_autoFollow) _centerOnUser();
  }

  Future<void> _fetchRoadRoute() async {
    if (_fLat == null || _fLng == null || _userLat == null || _userLng == null)
      return;

    final apiKey =
        'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjJmYTI4ZjFkODc3NzQ1ZTNiNGI3ZGIxNGI5MGFlYzI1IiwiaCI6Im11cm11cjY0In0=';
    final url =
        'https://api.openrouteservice.org/v2/directions/driving-car?api_key=$apiKey&start=${_userLng!},${_userLat!}&end=${_fLng!},${_fLat!}';

    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body);
      final coords = data['features'][0]['geometry']['coordinates'];
      final points = coords
          .map<ml.LatLng>(
            (c) => ml.LatLng(
              (c[1] is num ? c[1] : double.parse('$c[1]')),
              (c[0] is num ? c[0] : double.parse('$c[0]')),
            ),
          )
          .toList();
      await _drawRouteLine(points);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _drawRouteLine(List<ml.LatLng> pts) async {
    if (!_styleLoaded || _mapController == null || pts.isEmpty) return;
    if (_routeLine == null) {
      _routeLine = await _mapController!.addLine(
        ml.LineOptions(
          geometry: pts,
          lineColor: '#FF5722',
          lineWidth: 4.0,
          lineOpacity: 0.8,
        ),
      );
    } else {
      await _mapController!.updateLine(
        _routeLine!,
        ml.LineOptions(geometry: pts),
      );
    }
  }

  void _computeDistance() {
    if (_fLat == null || _fLng == null || _userLat == null || _userLng == null)
      return;
    _distanceMeters = Geolocator.distanceBetween(
      _userLat!,
      _userLng!,
      _fLat!,
      _fLng!,
    );
  }

  Future<void> _onMapCreated(ml.MaplibreMapController c) async {
    _mapController = c;
  }

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    await _ensureVigilCircle();
    await _updateUserCircle();
    await _fetchRoadRoute();
  }

  Future<void> _ensureVigilCircle() async {
    if (!_styleLoaded || _mapController == null) return;
    if (_fLat == null || _fLng == null) return;
    final pos = ml.LatLng(_fLat!, _fLng!);
    if (_vigilCircle == null) {
      _vigilCircle = await _mapController!.addCircle(
        ml.CircleOptions(
          geometry: pos,
          circleRadius: 10.0,
          circleColor: "#FF5722", // vigil color
          circleStrokeColor: "#FFFFFF",
          circleStrokeWidth: 2.0,
          circleOpacity: 0.95,
        ),
      );
    } else {
      await _mapController!.updateCircle(
        _vigilCircle!,
        ml.CircleOptions(geometry: pos),
      );
    }
  }

  Future<void> _updateUserCircle() async {
    if (!_styleLoaded || _mapController == null) return;
    if (_userLat == null || _userLng == null) {
      if (_userCircle != null) {
        try {
          await _mapController!.removeCircle(_userCircle!);
        } catch (_) {}
        _userCircle = null;
      }
      return;
    }
    final here = ml.LatLng(_userLat!, _userLng!);
    if (_userCircle == null) {
      _userCircle = await _mapController!.addCircle(
        ml.CircleOptions(
          geometry: here,
          circleRadius: 9.0,
          circleColor: "#0D47A1", // user color
          circleStrokeColor: "#FFFFFF",
          circleStrokeWidth: 2.0,
          circleOpacity: 0.95,
        ),
      );
    } else {
      await _mapController!.updateCircle(
        _userCircle!,
        ml.CircleOptions(geometry: here),
      );
    }
  }

  void _centerOnVigil() {
    if (_mapController == null || _fLat == null || _fLng == null) return;
    _mapController!.animateCamera(
      ml.CameraUpdate.newLatLngZoom(ml.LatLng(_fLat!, _fLng!), 16),
    );
  }

  void _centerOnUser() {
    if (_mapController == null || _userLat == null || _userLng == null) return;
    _mapController!.animateCamera(
      ml.CameraUpdate.newLatLngZoom(ml.LatLng(_userLat!, _userLng!), 16),
    );
  }

  Widget _pillChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(.55), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              fontFamily: 'Montserrat',
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDistance(double m) {
    return m >= 1000
        ? '${(m / 1000).toStringAsFixed(2)} km away'
        : '${m.toStringAsFixed(0)} m away';
  }

  void _addSymbolsToMap() async {
    if (_mapController == null || _fLat == null || _fLng == null) return;
    try {
      await _mapController!.clearSymbols();
    } catch (_) {}
    try {
      // Vigil marker
      await _mapController!.addSymbol(
        ml.SymbolOptions(
          geometry: ml.LatLng(_fLat!, _fLng!),
          iconImage: 'marker-15',
          iconSize: 1.6,
          textField: _fName ?? 'Vigil',
          textOffset: const Offset(0, 2),
        ),
      );
      // User marker
      if (_userLat != null && _userLng != null) {
        await _mapController!.addSymbol(
          ml.SymbolOptions(
            geometry: ml.LatLng(_userLat!, _userLng!),
            iconImage: 'marker-15',
            iconSize: 1.2,
            textField: 'You',
            textOffset: const Offset(0, 2),
          ),
        );
      }
    } catch (_) {}
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
    // WEB: skip geocoding plugin (unsupported). Try Nominatim reverse, else fallback.
    if (kIsWeb) {
      if (_fLat != null && _fLng != null) {
        final lat = _fLat!;
        final lng = _fLng!;
        try {
          final uri = Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng',
          );
          final resp = await http
              .get(
                uri,
                headers: {
                  // Provide a User-Agent per Nominatim usage policy.
                  'User-Agent': 'DayungApp/1.0 (contact@example.com)',
                },
              )
              .timeout(const Duration(seconds: 6));
          if (resp.statusCode == 200) {
            final data = resp.body;
            final map = data.isNotEmpty
                ? Map<String, dynamic>.from(
                    // ignore: unsafe_html
                    (jsonDecode(data) as Map<String, dynamic>),
                  )
                : {};
            final display = (map['display_name'] ?? '').toString();
            if (display.isNotEmpty) {
              _locationName = display;
              return;
            }
          }
          // Fallback to raw coordinates if reverse fails
          _locationName =
              'Lat ${lat.toStringAsFixed(5)}, Lng ${lng.toStringAsFixed(5)}';
        } catch (_) {
          _locationName =
              'Lat ${lat.toStringAsFixed(5)}, Lng ${lng.toStringAsFixed(5)}';
        }
        return;
      }
      if ((_fBarangay ?? '').trim().isNotEmpty) {
        _locationName = _fBarangay;
        return;
      }
      _locationName = 'Location unavailable';
      return;
    }

    // MOBILE / DESKTOP (plugin-supported path)
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

    if ((_fBarangay ?? '').trim().isNotEmpty) {
      _locationName = _fBarangay;
      try {
        final results = await locationFromAddress(
          _fBarangay!,
        ).timeout(const Duration(seconds: 10), onTimeout: () => []);
        if (results.isNotEmpty) {
          _fLat = results.first.latitude;
          _fLng = results.first.longitude;
        }
      } catch (_) {
        // keep text fallback
      }
      return;
    }

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
                            SizedBox(
                              height: 240,
                              width: double.infinity,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  children: [
                                    ml.MapLibreMap(
                                      key: ValueKey('map_${_fLat}_${_fLng}'),
                                      styleString:
                                          'https://api.maptiler.com/maps/basic-v2/style.json?key=ZgS5pYNNGTrRGUAnlS71',
                                      initialCameraPosition: ml.CameraPosition(
                                        target: ml.LatLng(_fLat!, _fLng!),
                                        zoom: 16,
                                      ),
                                      onMapCreated: _onMapCreated,
                                      onStyleLoadedCallback: _onStyleLoaded,
                                      myLocationEnabled: false,
                                      rotateGesturesEnabled: true,
                                      tiltGesturesEnabled: false,
                                      compassEnabled: false,
                                      attributionButtonMargins: const Point(
                                        6,
                                        6,
                                      ),
                                      logoViewMargins: const Point(6, 6),
                                    ),
                                    if (_autoFollow)
                                      Positioned(
                                        top: 16,
                                        left: 16,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(
                                              0.65,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              Icon(
                                                Icons.center_focus_strong,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Following',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13.5,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    Positioned(
                                      left: 12,
                                      bottom: 12,
                                      child: _locPermissionDenied
                                          ? _pillChip(
                                              'Location denied',
                                              Icons.location_off,
                                              Colors.red,
                                            )
                                          : (_distanceMeters != null
                                                ? _pillChip(
                                                    _formatDistance(
                                                      _distanceMeters!,
                                                    ),
                                                    Icons.route,
                                                    const Color(0xFF0D47A1),
                                                  )
                                                : _pillChip(
                                                    'Locating...',
                                                    Icons.gps_fixed,
                                                    const Color(0xFF0D47A1),
                                                  )),
                                    ),
                                    // Route button
                                    Positioned(
                                      right: 12,
                                      bottom: 12,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: const Color(
                                            0xFF0D47A1,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                        onPressed: _openRouteInMaps,
                                        icon: const Icon(
                                          Icons.directions,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Route',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Center buttons (vigil + user)
                                    Positioned(
                                      right: 12,
                                      top: 12,
                                      child: Column(
                                        children: [
                                          _CenterBtn(
                                            tooltip: 'Center on vigil',
                                            icon: Icons.location_on,
                                            enabled:
                                                _fLat != null && _fLng != null,
                                            onTap: _centerOnVigil,
                                          ),
                                          const SizedBox(height: 10),
                                          _CenterBtn(
                                            tooltip: 'Center on you',
                                            icon: Icons.my_location,
                                            enabled:
                                                _userLat != null &&
                                                _userLng != null,
                                            onTap: _centerOnUser,
                                          ),
                                          const SizedBox(height: 10),
                                          _CenterBtn(
                                            tooltip: _autoFollow
                                                ? 'Disable follow'
                                                : 'Enable follow',
                                            icon: _autoFollow
                                                ? Icons.center_focus_strong
                                                : Icons.center_focus_weak,
                                            enabled: true,
                                            onTap: _toggleFollow,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
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

  Widget _distanceChip() {
    final m = _distanceMeters!;
    final text = m >= 1000
        ? '${(m / 1000).toStringAsFixed(2)} km away'
        : '${m.toStringAsFixed(0)} m away';
    return _infoChip(text);
  }

  Widget _infoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _openRouteInMaps() async {
    if (_fLat == null || _fLng == null) return;
    final destLat = _fLat!.toStringAsFixed(6);
    final destLng = _fLng!.toStringAsFixed(6);
    String? origin;
    if (_userLat != null && _userLng != null) {
      origin =
          '${_userLat!.toStringAsFixed(6)},${_userLng!.toStringAsFixed(6)}';
    }
    final google = Uri.parse(
      origin == null
          ? 'https://www.google.com/maps/search/?api=1&query=$destLat,$destLng'
          : 'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destLat,$destLng',
    );
    final apple = Uri.parse(
      origin == null
          ? 'http://maps.apple.com/?ll=$destLat,$destLng'
          : 'http://maps.apple.com/?saddr=$origin&daddr=$destLat,$destLng',
    );
    if (await canLaunchUrl(google)) {
      await launchUrl(google, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(apple)) {
      await launchUrl(apple, mode: LaunchMode.externalApplication);
    }
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

class _CenterBtn extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _CenterBtn({
    Key? key,
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? Colors.white : Colors.grey.shade200,
      shape: const CircleBorder(),
      elevation: enabled ? 2 : 0,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Tooltip(
            message: tooltip,
            child: Icon(
              icon,
              size: 22,
              color: enabled ? const Color(0xFF0D47A1) : Colors.grey.shade400,
            ),
          ),
        ),
      ),
    );
  }
}
