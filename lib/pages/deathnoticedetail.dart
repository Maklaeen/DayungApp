import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:capstone_app/shared/dayung_map_error_snackbar.dart';
import 'package:capstone_app/shared/dayung_map_resize_handle.dart';
import 'package:capstone_app/shared/dayung_map_attribution.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

class DeathNoticeDetail extends StatefulWidget {
  final String? noticeId;
  final int? dayungUnitId;

  final String? name;
  final String? date;
  final String? birthDate;
  final double? latitude;
  final double? longitude;
  final String? barangay;

  const DeathNoticeDetail({
    super.key,
    required this.name,
    required this.date,
    this.birthDate,
    this.latitude,
    this.longitude,
    this.barangay,
  }) : noticeId = null,
       dayungUnitId = null,
       super();

  const DeathNoticeDetail.byNoticeId({
    super.key,
    required this.noticeId,
    this.dayungUnitId,
    this.name,
    this.date,
    this.birthDate,
    this.latitude,
    this.longitude,
    this.barangay,
  });

  static Future<void> showVigilDetails({
    required BuildContext context,
    required String? noticeId,
    required int? dayungUnitId,
    required String name,
    String? date,
    String? birthDate,
    double? latitude,
    double? longitude,
    String? barangay,
  }) {
    final media = MediaQuery.sizeOf(context);
    final detail = DeathNoticeDetail.byNoticeId(
      noticeId: noticeId,
      dayungUnitId: dayungUnitId,
      name: name,
      date: date,
      birthDate: birthDate,
      latitude: latitude,
      longitude: longitude,
      barangay: barangay,
    );

    if (media.width >= 720) {
      return showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          child: SizedBox(
            width: (media.width - 64).clamp(0, 1100),
            height: (media.height - 48).clamp(0, 900),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: detail,
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => detail,
    );
  }

  @override
  State<DeathNoticeDetail> createState() => _DeathNoticeDetailState();
}

class _DeathNoticeDetailState extends State<DeathNoticeDetail> {
  final _sb = Supabase.instance.client;
  static const _missingLocationMessage = 'No location was set by the sender.';

  String? _fName;
  String? _fDateOfDeath;
  String? _fBirthDate;
  double? _fLat;
  double? _fLng;
  String? _fBarangay;
  int? _fStoredAge;
  String? _locationWarning;

  double? _userLat;
  double? _userLng;
  double _userHeading = 0;
  double? _distanceMeters;
  bool _locPermissionDenied = false;

  String? _locationName;
  ml.MapLibreMapController? _mapController;
  final MapController _webMapController = MapController();
  bool _styleLoaded = false;
  ml.Symbol? _vigilSymbol;
  ml.Symbol? _userSymbol;
  ml.Circle? _vigilCircle;
  ml.Circle? _userCircle;
  ml.Line? _routeLine;
  List<ll.LatLng> _webRoutePoints = [];

  StreamSubscription<Position>? _posSub;
  bool _autoFollow = true;
  double? _initialDistance;
  static const double _fadeRemoveThreshold = 40;

  bool _loading = false;
  String? _error;
  double? _mapHeightOverride;

  @override
  void initState() {
    super.initState();
    _hydrateFromPassedProps();
    _loadIfNeeded();
    _fetchUserLocation();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  void _hydrateFromPassedProps() {
    _fName = widget.name;
    _fDateOfDeath = widget.date;
    _fBirthDate = widget.birthDate;
    _fLat = widget.latitude;
    _fLng = widget.longitude;
    _fBarangay = widget.barangay;
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _userLat = pos.latitude;
      _userLng = pos.longitude;
      if (pos.heading.isFinite && pos.heading >= 0) {
        _userHeading = pos.heading;
      }
      _computeDistance();
      _initialDistance ??= _distanceMeters;
      setState(() {});
      await _updateUserLocationMarker();
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
    if (p.heading.isFinite && p.heading >= 0) _userHeading = p.heading;
    _computeDistance();
    if (_initialDistance == null && _distanceMeters != null) {
      _initialDistance = _distanceMeters;
    }
    if (!mounted) return;
    await _updateUserLocationMarker();
    _updateRouteFade();
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
        _mapController == null) {
      return;
    }

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
          lineColor: '#0D47A1',
          lineWidth: 4.0,
          lineOpacity: opacity,
        ),
      );
    } catch (_) {}
  }

  Future<void> _fetchRoadRoute() async {
    if (_fLat == null ||
        _fLng == null ||
        _userLat == null ||
        _userLng == null) {
      return;
    }

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
    _webRoutePoints = pts
        .map((point) => ll.LatLng(point.latitude, point.longitude))
        .toList();
    if (!_styleLoaded || _mapController == null || pts.isEmpty) return;
    if (_routeLine == null) {
      _routeLine = await _mapController!.addLine(
        ml.LineOptions(
          geometry: pts,
          lineColor: '#0D47A1',
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
    if (_fLat == null ||
        _fLng == null ||
        _userLat == null ||
        _userLng == null) {
      return;
    }
    _distanceMeters = Geolocator.distanceBetween(
      _userLat!,
      _userLng!,
      _fLat!,
      _fLng!,
    );
  }

  Future<void> _onMapCreated(ml.MapLibreMapController c) async {
    _mapController = c;
  }

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    await _ensureVigilMarker();
    await _ensureVigilCircle();
    await _updateUserLocationMarker();
    await _fetchRoadRoute();
  }

  Future<void> _ensureVigilMarker() async {
    if (!_styleLoaded || _mapController == null) return;
    if (_fLat == null || _fLng == null) return;
    _vigilSymbol ??= await _mapController!.addSymbol(
      ml.SymbolOptions(
        geometry: ml.LatLng(_fLat!, _fLng!),
        iconImage: 'marker-15',
        iconSize: 1.6,
        iconColor: '#10B981',
        iconHaloColor: '#FFFFFF',
        iconHaloWidth: 1.5,
      ),
    );
  }

  Future<void> _ensureVigilCircle() async {
    if (!_styleLoaded || _mapController == null) return;
    if (_fLat == null || _fLng == null) return;
    final pos = ml.LatLng(_fLat!, _fLng!);
    if (_vigilCircle == null) {
      _vigilCircle = await _mapController!.addCircle(
        ml.CircleOptions(
          geometry: pos,
          circleRadius: 26.0,
          circleColor: "#2E7D32",
          circleStrokeColor: "#2E7D32",
          circleStrokeWidth: 2.0,
          circleOpacity: 0.2,
        ),
      );
    } else {
      await _mapController!.updateCircle(
        _vigilCircle!,
        ml.CircleOptions(geometry: pos),
      );
    }
  }

  Future<void> _updateUserLocationMarker() async {
    if (!_styleLoaded || _mapController == null) return;
    if (_userLat == null || _userLng == null) {
      if (_userCircle != null) {
        try {
          await _mapController!.removeCircle(_userCircle!);
        } catch (_) {}
        _userCircle = null;
      }
      if (_userSymbol != null) {
        try {
          await _mapController!.removeSymbol(_userSymbol!);
        } catch (_) {}
        _userSymbol = null;
      }
      return;
    }
    final here = ml.LatLng(_userLat!, _userLng!);
    if (_userCircle == null) {
      _userCircle = await _mapController!.addCircle(
        ml.CircleOptions(
          geometry: here,
          circleRadius: 20.0,
          circleColor: "#4285F4",
          circleOpacity: 0.18,
        ),
      );
    } else {
      await _mapController!.updateCircle(
        _userCircle!,
        ml.CircleOptions(geometry: here),
      );
    }

    final symbolOptions = ml.SymbolOptions(
      geometry: here,
      iconImage: 'triangle-15',
      iconSize: 1.5,
      iconRotate: _userHeading,
      iconAnchor: 'center',
      iconColor: '#4285F4',
      iconHaloColor: '#FFFFFF',
      iconHaloWidth: 2,
      zIndex: 10,
    );
    if (_userSymbol == null) {
      _userSymbol = await _mapController!.addSymbol(symbolOptions);
    } else {
      await _mapController!.updateSymbol(_userSymbol!, symbolOptions);
    }
  }

  void _centerOnVigil() {
    if (_fLat == null || _fLng == null) return;
    if (kIsWeb) {
      _webMapController.move(ll.LatLng(_fLat!, _fLng!), 16);
      return;
    }
    if (_mapController == null) return;
    _mapController!.animateCamera(
      ml.CameraUpdate.newLatLngZoom(ml.LatLng(_fLat!, _fLng!), 16),
    );
  }

  void _centerOnUser() {
    if (_userLat == null || _userLng == null) return;
    if (kIsWeb) {
      _webMapController.move(ll.LatLng(_userLat!, _userLng!), 16);
      return;
    }
    if (_mapController == null) return;
    _mapController!.animateCamera(
      ml.CameraUpdate.newLatLngZoom(ml.LatLng(_userLat!, _userLng!), 16),
    );
  }

  void _toggleFollow() {
    if (_userLat == null || _userLng == null) return;
    final shouldFollow = !_autoFollow;
    setState(() => _autoFollow = shouldFollow);
    if (shouldFollow) _centerOnUser();
  }

  void _stopFollowingOnMapGesture() {
    if (!_autoFollow || !mounted) return;
    setState(() => _autoFollow = false);
  }

  Widget _pillChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: .55), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
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
        ? '${(m / 1000).toStringAsFixed(2)} km'
        : '${m.toStringAsFixed(0)} m';
  }

  Widget _buildLocationStatusChip() {
    if (_locPermissionDenied) {
      return _pillChip(
        'Location unavailable',
        Icons.location_off_rounded,
        const Color(0xFFDC2626),
      );
    }
    if (_distanceMeters != null) {
      return _pillChip(
        _formatDistance(_distanceMeters!),
        Icons.route_rounded,
        const Color(0xFF0D47A1),
      );
    }
    return _pillChip(
      'Locating...',
      Icons.gps_fixed_rounded,
      const Color(0xFF0D47A1),
    );
  }

  Widget _buildMapControls() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _compactMapButton(
            icon: Icons.route_rounded,
            tooltip: 'Open route',
            onTap: _openRouteInMaps,
          ),
          _compactMapButton(
            icon: Icons.location_on_outlined,
            tooltip: 'Center on vigil',
            onTap: _centerOnVigil,
          ),
          if (_userLat != null && _userLng != null)
            _compactMapButton(
              icon: _autoFollow
                  ? Icons.my_location_rounded
                  : Icons.location_searching_rounded,
              tooltip: _autoFollow ? 'Stop following' : 'Follow my location',
              onTap: _toggleFollow,
              selected: _autoFollow,
            ),
        ],
      ),
    );
  }

  Widget _compactMapButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      icon: Icon(
        icon,
        color: selected ? const Color(0xFF0D47A1) : const Color(0xFF475569),
        size: 21,
      ),
    );
  }

  Future<Map<String, dynamic>?> _fetchNoticeRecord({
    required bool includeLocationFields,
  }) {
    // Always use claims table now, fields are from claims
    final fields = includeLocationFields
        ? 'id, PassedAway, dob, deceased_age, date_of_death, vigil_address, vigil_barangay, vigil_latitude, vigil_longitude, deceased_type, user_id, beneficiary_id, death_certificate_url, valid_ids_url, claimedmoney'
        : 'id, PassedAway, dob, deceased_age, date_of_death, vigil_address, vigil_barangay, deceased_type, user_id, beneficiary_id, death_certificate_url, valid_ids_url, claimedmoney';

    return _sb
        .from('claims')
        .select(fields)
        .eq('id', widget.noticeId!)
        .maybeSingle();
  }

  bool _isMissingLocationColumnError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('latitude') || message.contains('longitude');
  }

  Future<void> _loadIfNeeded() async {
    if (widget.noticeId == null) {
      await _resolveLocation();
      _locationWarning =
          (_fLat == null && _fLng == null && (_fBarangay ?? '').trim().isEmpty)
          ? _missingLocationMessage
          : null;
      setState(() => _loading = false);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _locationWarning = null;
    });

    try {
      Map<String, dynamic>? notice;
      try {
        notice = await _fetchNoticeRecord(includeLocationFields: true);
      } catch (error) {
        if (!_isMissingLocationColumnError(error)) rethrow;
        notice = await _fetchNoticeRecord(includeLocationFields: false);
        _locationWarning = _missingLocationMessage;
      }

      if (notice == null) {
        setState(() {
          _error = 'Notice not found';
          _loading = false;
        });
        return;
      }

      final fetchedName = (notice['PassedAway'] ?? '').toString().trim();
      if ((_fName == null || _fName!.trim().isEmpty) &&
          fetchedName.isNotEmpty) {
        _fName = fetchedName;
      }
      _fBirthDate = (notice['dob'] ?? _fBirthDate)?.toString();
      _fDateOfDeath = (notice['date_of_death'] ?? _fDateOfDeath)?.toString();
      // Prefer vigil_barangay, fallback to vigil_address, fallback to _fBarangay
      _fBarangay =
          (notice['vigil_barangay'] ?? notice['vigil_address'] ?? _fBarangay)
              ?.toString();
      _fLat = _toDouble(notice['vigil_latitude']) ?? _fLat;
      _fLng = _toDouble(notice['vigil_longitude']) ?? _fLng;
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

      if (_fLat == null && _fLng == null && (_fBarangay ?? '').trim().isEmpty) {
        _locationWarning = _missingLocationMessage;
      }

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

  Widget _buildLocationWarningCard() {
    return DayungMapErrorCard(
      title: 'Location unavailable',
      message: _locationWarning ?? _missingLocationMessage,
      icon: Icons.location_off_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final screenHeight = screenSize.height;
    final isWide = screenSize.width >= 720;
    final defaultMapHeight = (screenHeight * (isWide ? 0.58 : 0.40))
        .clamp(isWide ? 360.0 : 240.0, isWide ? 560.0 : 440.0)
        .toDouble();
    final maxMapHeight = (screenHeight * 0.65).clamp(280.0, 700.0).toDouble();
    final mapHeight = (_mapHeightOverride ?? defaultMapHeight)
        .clamp(200.0, maxMapHeight)
        .toDouble();
    final detailHeight = screenHeight * (screenSize.width >= 720 ? 0.9 : 0.75);
    final name = (_fName ?? '').trim().isEmpty ? 'Unknown' : _fName!.trim();
    final dDate = _fDateOfDeath;
    final bDate = _fBirthDate;
    final age = _fStoredAge ?? _computeAge(bDate, dDate);
    final hasMapLocation = _fLat != null && _fLng != null;

    return SafeArea(
      top: false,
      child: Container(
        height: detailHeight,
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vigil Details',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Location and remembrance details',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close details',
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFF1F5F9),
                        foregroundColor: const Color(0xFF475569),
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: _loading
                    ? const DayungPageSkeleton(
                        layout: DayungSkeletonLayout.detail,
                        itemCount: 3,
                      )
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
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                        child: Column(
                          children: [
                            // Memorial Card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 24,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF0D47A1),
                                    Color(0xFF3B82F6),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(22),
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
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
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
                            if ((bDate ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _buildInfoCard(
                                icon: Icons.cake_outlined,
                                title: 'Date of Birth',
                                value: _fmtDate(bDate),
                              ),
                            ],
                            const SizedBox(height: 16),
                            // Location Card
                            _buildInfoCard(
                              icon: Icons.location_on,
                              title: 'Vigil Location',
                              value:
                                  _fBarangay ??
                                  _locationName ??
                                  _locationWarning ??
                                  'Location unavailable',
                            ),
                            const SizedBox(height: 16),
                            if (!hasMapLocation && _locationWarning != null)
                              _buildLocationWarningCard(),
                            if (hasMapLocation) ...[
                              SizedBox(
                                height: mapHeight,
                                width: double.infinity,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: Stack(
                                    children: [
                                      Listener(
                                        behavior: HitTestBehavior.translucent,
                                        onPointerMove: (_) =>
                                            _stopFollowingOnMapGesture(),
                                        child: _buildModernMap(
                                          _fLat!,
                                          _fLng!,
                                          mapHeight: mapHeight,
                                        ),
                                      ),
                                      Positioned(
                                        left: 12,
                                        right: 12,
                                        bottom: 40,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child:
                                                    _buildLocationStatusChip(),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _buildMapControls(),
                                          ],
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        child: DayungMapResizeHandle(
                                          onResize: (deltaY) {
                                            setState(() {
                                              _mapHeightOverride =
                                                  (mapHeight + deltaY)
                                                      .clamp(
                                                        200.0,
                                                        maxMapHeight,
                                                      )
                                                      .toDouble();
                                            });
                                          },
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
      ),
    );
  }

  Widget _buildModernMap(double lat, double lng, {required double mapHeight}) {
    if (kIsWeb) {
      return SizedBox(
        height: mapHeight,
        child: FlutterMap(
          mapController: _webMapController,
          options: MapOptions(
            initialCenter: ll.LatLng(lat, lng),
            initialZoom: 15,
            minZoom: 12,
            maxZoom: 20,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'capstone_app',
              panBuffer: 0,
              keepBuffer: 1,
              tileUpdateTransformer: TileUpdateTransformers.debounce(
                const Duration(milliseconds: 150),
              ),
            ),
            CircleLayer(
              circles: [
                CircleMarker(
                  point: ll.LatLng(lat, lng),
                  radius: 26,
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderColor: const Color(0xFF10B981),
                  borderStrokeWidth: 2,
                ),
                if (_userLat != null && _userLng != null)
                  CircleMarker(
                    point: ll.LatLng(_userLat!, _userLng!),
                    radius: 20,
                    color: const Color(0xFF4285F4).withValues(alpha: 0.18),
                  ),
              ],
            ),
            if (_webRoutePoints.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _webRoutePoints,
                    color: const Color(0xFF3B82F6),
                    strokeWidth: 4,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                Marker(
                  point: ll.LatLng(lat, lng),
                  width: 48,
                  height: 48,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                if (_userLat != null && _userLng != null)
                  Marker(
                    point: ll.LatLng(_userLat!, _userLng!),
                    width: 44,
                    height: 44,
                    child: Transform.rotate(
                      angle: _userHeading * pi / 180,
                      child: const Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.navigation_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                          Icon(
                            Icons.navigation_rounded,
                            color: Color(0xFF4285F4),
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const DayungMapAttribution(alignment: Alignment.bottomRight),
          ],
        ),
      );
    }
    final compactMapControls = MediaQuery.sizeOf(context).width < 600;
    return SizedBox(
      height: mapHeight,
      child: ml.MapLibreMap(
        styleString:
            'https://api.maptiler.com/maps/streets/style.json?key=ZgS5pYNNGTrRGUAnlS71',
        initialCameraPosition: ml.CameraPosition(
          target: ml.LatLng(lat, lng),
          zoom: 16,
        ),
        onMapCreated: (controller) async {
          _mapController = controller;
          await _onMapCreated(controller);
        },
        onStyleLoadedCallback: _onStyleLoaded,
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
        },
        myLocationEnabled: false,
        compassEnabled: false,
        dragEnabled: true,
        scrollGesturesEnabled: true,
        rotateGesturesEnabled: true,
        tiltGesturesEnabled: false,
        zoomGesturesEnabled: true,
        minMaxZoomPreference: const ml.MinMaxZoomPreference(12, 20),
        attributionButtonMargins: compactMapControls
            ? const Point(64, 40)
            : const Point(6, 6),
        logoViewMargins: const Point(6, 6),
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
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: const Color(0x12000000),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF0D47A1), size: 21),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
