// filepath: lib/screens/dayung_map_page.dart
// ignore_for_file: deprecated_member_use, control_flow_in_finally, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:capstone_app/config/app_config.dart';
import 'package:capstone_app/pages/apply_membership.dart';
import 'package:capstone_app/shared/dayung_map_error_snackbar.dart';
import 'package:capstone_app/shared/dayung_map_resize_handle.dart';
import 'package:capstone_app/shared/dayung_map_attribution.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

// color palette
const Color kPrimary = Color(0xFF3B82F6);
const Color kPrimaryDark = Color(0xFF1E40AF);
const Color kAccent = Color(0xFF10B981);
const Color kWarn = Color(0xFFF59E0B);
const Color kDanger = Color(0xFFEF4444);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF6B7280);
const Color kPanelBg = Colors.white;

enum NavMode { driving, motorcycle, transit, walking }

extension NavModeX on NavMode {
  String get label {
    switch (this) {
      case NavMode.driving:
        return 'Car';
      case NavMode.motorcycle:
        return 'Motorcycle';
      case NavMode.transit:
        return 'Commute';
      case NavMode.walking:
        return 'Walk';
    }
  }

  String get apiValue {
    switch (this) {
      case NavMode.driving:
        return 'driving';
      case NavMode.motorcycle:
        return 'driving';
      case NavMode.transit:
        return 'transit';
      case NavMode.walking:
        return 'walking';
    }
  }

  IconData get icon {
    switch (this) {
      case NavMode.driving:
        return Icons.directions_car;
      case NavMode.motorcycle:
        return Icons.two_wheeler;
      case NavMode.transit:
        return Icons.directions_transit;
      case NavMode.walking:
        return Icons.directions_walk;
    }
  }
}

class LocationService {
  static Future<bool> ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  static Future<Position?> currentPosition({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final ok = await ensurePermission();
      if (!ok) return null;
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: timeout,
      );
    } on TimeoutException {
      // Fallback to last known if current fix times out
      return Geolocator.getLastKnownPosition();
    } catch (_) {
      return Geolocator.getLastKnownPosition();
    }
  }
}

class DayungMapPage extends StatefulWidget {
  final Map<String, dynamic> dayung;

  final bool isApplied;
  final bool isMember;
  final bool allowApplication;
  final List<Map<String, dynamic>>? allDayungs;
  final double nearbyRadiusMeters;

  const DayungMapPage({
    super.key,
    required this.dayung,
    this.isApplied = false,
    this.isMember = false,
    this.allowApplication = true,
    this.allDayungs,
    this.nearbyRadiusMeters = 5000,
  });

  @override
  State<DayungMapPage> createState() => _DayungMapPageState();
}

class _DayungMapPageState extends State<DayungMapPage> {
  ml.MapLibreMapController? _mlController;
  final MapController _webMapController = MapController();
  bool _styleLoaded = false;
  ml.Symbol? _dayungSymbol;
  ml.Symbol? _userSymbol;
  ml.Line? _routeLine;
  List<ml.LatLng> _routePoints = [];
  bool _addedDayungSource = false;
  bool _addedDayungLayer = false;
  bool _addedUserSource = false;
  bool _addedUserLayer = false;

  Position? _pos;
  bool _loadingLoc = true;
  bool _permissionDenied = false;
  StreamSubscription<Position>? positionStream;
  Map<String, dynamic>? _rules;
  List<Map<String, dynamic>> _requiredApplications = [];
  bool _loadingRules = true;
  late final Future<void> _rulesLoadFuture;
  double? _compassHeading;
  StreamSubscription<CompassEvent>? compassStream;
  bool _applied = false;
  bool _submitting = false;
  int? _etaMinutes;
  double _mapFlex = 65;
  int _lastCompassUpdateMs = 0;
  NavMode? _selectedMode;

  String _orsProfileFor(NavMode m) {
    switch (m) {
      case NavMode.driving:
      case NavMode.motorcycle:
        return 'driving-car';
      case NavMode.walking:
        return 'foot-walking';
      case NavMode.transit:
        return 'driving-car';
    }
  }

  double? get dayungLat {
    final v = widget.dayung['latitude'];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  double? get dayungLng {
    final v = widget.dayung['longitude'];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  List<ll.LatLng> get _routeLatLngs => _routePoints
      .map((point) => ll.LatLng(point.latitude, point.longitude))
      .toList();

  @override
  void initState() {
    super.initState();
    _applied = widget.isApplied;
    _rulesLoadFuture = _fetchRules();

    compassStream = FlutterCompass.events?.listen((event) {
      final heading = event.heading;
      if (!mounted || heading == null || !heading.isFinite) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastCompassUpdateMs > 300 &&
          (_compassHeading == null || (heading - _compassHeading!).abs() > 6)) {
        _lastCompassUpdateMs = now;
        setState(() => _compassHeading = heading);
        unawaited(_updateUserMarker());
      }
    });
    _initLocation();
    _checkExistingApplication();
  }

  int? getDayungUnitId() {
    final raw = widget.dayung['dayung_unit_id'] ?? widget.dayung['id'];
    if (raw is int) return raw;
    return int.tryParse('$raw');
  }

  Future<void> _checkExistingApplication() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    final dayungUnitId = getDayungUnitId();
    if (uid == null || dayungUnitId == null) return;
    try {
      final existing = await sb
          .from('applications')
          .select('id,status')
          .eq('user_id', uid)
          .eq('dayung_unit_id', dayungUnitId)
          .maybeSingle();
      if (mounted && existing != null) {
        setState(() => _applied = true);
      }
    } catch (_) {}
  }

  Future<void> _onMapCreated(ml.MapLibreMapController c) async {
    _mlController = c;
  }

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    await _ensureMarkers();
    await _ensureDayungCircle();
    await _updateUserMarker();
    await _updateUserCircle();
    await _updateRouteOnMap();
  }

  Future<void> _ensureMarkers() async {
    if (!_styleLoaded || _mlController == null) return;
    final lat = dayungLat, lng = dayungLng;
    if (lat == null || lng == null) return;
    _dayungSymbol ??= await _mlController!.addSymbol(
      ml.SymbolOptions(
        geometry: ml.LatLng(lat, lng),
        iconImage: 'building-15',
        iconSize: 1.25,
        iconColor: '#2E7D32',
        iconHaloColor: '#FFFFFF',
        iconHaloWidth: 2,
        zIndex: 5,
      ),
    );
  }

  Future<void> _ensureDayungCircle() async {
    if (!_styleLoaded || _mlController == null) return;
    final lat = dayungLat, lng = dayungLng;
    if (lat == null || lng == null) return;

    if (!_addedDayungSource) {
      try {
        await _mlController!.addSource(
          "dayung-point",
          ml.GeojsonSourceProperties(
            data: {
              "type": "FeatureCollection",
              "features": [
                {
                  "type": "Feature",
                  "geometry": {
                    "type": "Point",
                    "coordinates": [lng, lat],
                  },
                  "properties": {},
                },
              ],
            },
          ),
        );
        _addedDayungSource = true;
      } catch (_) {}
    } else {
      // Update geometry if already added
      try {
        await _mlController!.setGeoJsonSource("dayung-point", {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "geometry": {
                "type": "Point",
                "coordinates": [lng, lat],
              },
              "properties": {},
            },
          ],
        });
      } catch (_) {}
    }

    if (!_addedDayungLayer) {
      try {
        await _mlController!.addLayer(
          "dayung-point",
          "dayung-circle",
          const ml.CircleLayerProperties(
            circleRadius: 26,
            circleColor: "#2E7D32",
            circleOpacity: 0.20,
            circleStrokeColor: "#2E7D32",
            circleStrokeWidth: 2.0,
          ),
        );
        _addedDayungLayer = true;
      } catch (_) {}
    } else {
      try {
        await _mlController!.setLayerProperties(
          "dayung-circle",
          const ml.CircleLayerProperties(
            circleRadius: 26,
            circleColor: "#2E7D32",
            circleOpacity: 0.20,
            circleStrokeColor: "#2E7D32",
            circleStrokeWidth: 2.0,
          ),
        );
      } catch (_) {}
    }
  }

  Future<void> _updateUserCircle() async {
    if (!_styleLoaded || _mlController == null) return;

    if (_pos == null) {
      try {
        if (_addedUserLayer) {
          await _mlController!.removeLayer("user-circle");
          _addedUserLayer = false;
        }
        if (_addedUserSource) {
          await _mlController!.removeSource("user-point");
          _addedUserSource = false;
        }
      } catch (_) {}
      return;
    }

    final lat = _pos!.latitude;
    final lng = _pos!.longitude;

    if (!_addedUserSource) {
      try {
        await _mlController!.addSource(
          "user-point",
          ml.GeojsonSourceProperties(
            data: {
              "type": "FeatureCollection",
              "features": [
                {
                  "type": "Feature",
                  "geometry": {
                    "type": "Point",
                    "coordinates": [lng, lat],
                  },
                  "properties": {},
                },
              ],
            },
          ),
        );
        _addedUserSource = true;
      } catch (_) {}
    } else {
      try {
        await _mlController!.setGeoJsonSource("user-point", {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "geometry": {
                "type": "Point",
                "coordinates": [lng, lat],
              },
              "properties": {},
            },
          ],
        });
      } catch (_) {}
    }

    if (!_addedUserLayer) {
      try {
        await _mlController!.addLayer(
          "user-point",
          "user-circle",
          const ml.CircleLayerProperties(
            circleRadius: 20,
            circleColor: "#4285F4",
            circleOpacity: 0.18,
          ),
        );
        _addedUserLayer = true;
      } catch (_) {}
    } else {
      try {
        await _mlController!.setLayerProperties(
          "user-circle",
          const ml.CircleLayerProperties(
            circleRadius: 20,
            circleColor: "#4285F4",
            circleOpacity: 0.18,
          ),
        );
      } catch (_) {}
    }
  }

  Future<void> _updateUserMarker() async {
    if (!_styleLoaded || _mlController == null) return;
    if (_pos == null) {
      if (_userSymbol != null) {
        await _mlController!.removeSymbol(_userSymbol!);
        _userSymbol = null;
      }
      return;
    }

    final positionHeading = _pos!.heading;
    final heading =
        _compassHeading ?? (positionHeading.isFinite ? positionHeading : 0.0);
    final options = ml.SymbolOptions(
      geometry: ml.LatLng(_pos!.latitude, _pos!.longitude),
      iconImage: 'triangle-15',
      iconSize: 1.5,
      iconRotate: heading,
      iconAnchor: 'center',
      iconColor: '#4285F4',
      iconHaloColor: '#FFFFFF',
      iconHaloWidth: 2,
      zIndex: 10,
    );
    if (_userSymbol == null) {
      _userSymbol = await _mlController!.addSymbol(options);
    } else {
      await _mlController!.updateSymbol(_userSymbol!, options);
    }
  }

  Future<void> _updateRouteOnMap() async {
    if (!_styleLoaded || _mlController == null) return;
    if (_routeLine != null) {
      try {
        await _mlController!.removeLine(_routeLine!);
      } catch (_) {
        _routeLine = null;
      }
    }
    if (_routePoints.length < 2) return;
    try {
      _routeLine = await _mlController!.addLine(
        ml.LineOptions(
          geometry: _routePoints,
          lineColor: "#0D47A1",
          lineWidth: 4.0,
          lineOpacity: 0.9,
        ),
      );
    } catch (_) {}
  }

  void _fitToRoute() {
    if (_routePoints.length < 2) return;
    if (kIsWeb) {
      final points = _routeLatLngs;
      if (points.length < 2) return;
      _webMapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(40),
        ),
      );
      return;
    }
    if (_mlController == null) return;
    final lats = _routePoints.map((p) => p.latitude).toList();
    final lngs = _routePoints.map((p) => p.longitude).toList();
    final sw = ml.LatLng(
      lats.reduce((a, b) => a < b ? a : b),
      lngs.reduce((a, b) => a < b ? a : b),
    );
    final ne = ml.LatLng(
      lats.reduce((a, b) => a > b ? a : b),
      lngs.reduce((a, b) => a > b ? a : b),
    );
    _mlController!.animateCamera(
      ml.CameraUpdate.newLatLngBounds(
        ml.LatLngBounds(southwest: sw, northeast: ne),
        left: 40,
        top: 40,
        right: 40,
        bottom: 40,
      ),
    );
  }

  bool _isNoRouteResponse(String responseBody) {
    final body = responseBody.toLowerCase();
    return body.contains('no route') ||
        body.contains('noroute') ||
        body.contains('no segment') ||
        body.contains('could not find routable point');
  }

  void _showRouteError(String message) {
    if (!mounted) return;
    setState(() {
      _routePoints = [];
      _etaMinutes = null;
    });
    final noRoute = message == 'No route found, might take a flight.';
    showDayungMapErrorSnackBar(
      context,
      title: noRoute ? 'Route unavailable' : 'Route preview error',
      message: message,
      icon: noRoute ? Icons.flight_takeoff_rounded : Icons.route_rounded,
    );
  }

  Future<void> _fetchRoute({String mode = 'foot-walking'}) async {
    if (_pos == null || dayungLat == null || dayungLng == null) return;

    final apiKey = AppConfig.openRouteServiceApiKey.trim();
    if (apiKey.isEmpty) {
      await _fetchRouteWithoutApiKey();
      return;
    }

    final startLng = _pos!.longitude;
    final startLat = _pos!.latitude;
    final endLng = dayungLng!;
    final endLat = dayungLat!;

    final url =
        'https://api.openrouteservice.org/v2/directions/$mode?api_key=$apiKey&start=$startLng,$startLat&end=$endLng,$endLat';
    debugPrint('ORS GET $url');

    try {
      final response = await http.get(Uri.parse(url));
      debugPrint('ORS status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List<dynamic>?;
        if (features == null || features.isEmpty) {
          _showRouteError('No route found, might take a flight.');
          return;
        }
        final feature = features.first as Map<String, dynamic>;
        final coords = feature['geometry']['coordinates'];
        final summary = feature['properties']['summary'];
        final durationSeconds = summary['duration'];
        if (!mounted) return;
        setState(() {
          _routePoints = coords
              .map<ml.LatLng>(
                (c) => ml.LatLng(
                  (c[1] is num
                      ? (c[1] as num).toDouble()
                      : double.parse('${c[1]}')),
                  (c[0] is num
                      ? (c[0] as num).toDouble()
                      : double.parse('${c[0]}')),
                ),
              )
              .toList();
          _etaMinutes = (durationSeconds / 60).round();
        });
      } else {
        debugPrint('ORS error body: ${response.body}');
        _showRouteError(
          _isNoRouteResponse(response.body)
              ? 'No route found, might take a flight.'
              : 'Failed to fetch route',
        );
      }
    } catch (e) {
      debugPrint('ORS fetch error: $e');
      _showRouteError('Unable to fetch route preview.');
    }
  }

  Future<void> _fetchRouteWithoutApiKey() async {
    final start = _pos;
    final endLat = dayungLat;
    final endLng = dayungLng;
    if (start == null || endLat == null || endLng == null) return;

    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};$endLng,$endLat'
      '?overview=full&geometries=geojson',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode != 200) {
        if (_isNoRouteResponse(response.body)) {
          _showRouteError('No route found, might take a flight.');
          return;
        }
        throw StateError('OSRM status ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>?;
      final route = routes?.isNotEmpty == true
          ? routes!.first as Map<String, dynamic>
          : null;
      final coordinates =
          (route?['geometry'] as Map<String, dynamic>?)?['coordinates']
              as List<dynamic>?;
      if (coordinates == null || coordinates.length < 2) {
        _showRouteError('No route found, might take a flight.');
        return;
      }

      if (!mounted) return;
      setState(() {
        _routePoints = coordinates
            .map<ml.LatLng>(
              (coordinate) => ml.LatLng(
                (coordinate[1] as num).toDouble(),
                (coordinate[0] as num).toDouble(),
              ),
            )
            .toList();
        _etaMinutes = ((route?['duration'] as num?)?.toDouble() ?? 0) ~/ 60;
      });
    } catch (error) {
      debugPrint('OSRM route error: $error');
      _showRouteError('Unable to fetch route preview.');
    }
  }

  Future<void> _openExternalMaps(NavMode mode) async {
    if (dayungLat == null || dayungLng == null) return;

    if (_pos == null) {
      await _initLocation();
    }

    final dLat = dayungLat!;
    final dLng = dayungLng!;
    final travel = mode.apiValue;
    final origin = _pos == null
        ? ''
        : '&origin=${_pos!.latitude},${_pos!.longitude}';
    final url =
        'https://www.google.com/maps/dir/?api=1$origin&destination=$dLat,$dLng&travelmode=$travel&dir_action=navigate';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cannot open Maps')));
    }
  }

  void _showDirectionModeSheet() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        NavMode? temp = _selectedMode;
        return StatefulBuilder(
          builder: (ctx, setM) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              backgroundColor: Colors.white,
              elevation: 20,
              shadowColor: const Color(0x330F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: kPrimary.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.alt_route_rounded,
                              color: kPrimaryDark,
                              size: 25,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Plan your route',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Montserrat',
                                    color: kNeutralText,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Choose how you want to travel',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: kSubtleText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(ctx),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFF3F4F6),
                            ),
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 19,
                              color: kSubtleText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'TRAVEL MODE',
                        style: TextStyle(
                          color: kSubtleText,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: NavMode.values.map((mode) {
                          final active = temp == mode;
                          return ChoiceChip(
                            selected: active,
                            showCheckmark: false,
                            selectedColor: kPrimary.withValues(alpha: 0.10),
                            backgroundColor: const Color(0xFFF8FAFC),
                            side: BorderSide(
                              color: active
                                  ? kPrimary.withValues(alpha: 0.55)
                                  : const Color(0xFFE5E7EB),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  mode.icon,
                                  size: 17,
                                  color: active ? kPrimaryDark : kNeutralText,
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  mode.label,
                                  style: TextStyle(
                                    color: active ? kPrimaryDark : kNeutralText,
                                    fontSize: 12,
                                    fontWeight: active
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                if (active) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    size: 15,
                                    color: kPrimary,
                                  ),
                                ],
                              ],
                            ),
                            onSelected: (_) async {
                              if (active) {
                                setM(() => temp = null);
                                if (!mounted) return;
                                setState(() {
                                  _selectedMode = null;
                                  _routePoints = [];
                                  _etaMinutes = null;
                                });
                                await _updateRouteOnMap();
                                return;
                              }

                              setM(() => temp = mode);
                              setState(() => _selectedMode = mode);

                              if (_pos == null) {
                                await _initLocation();
                                if (_pos == null) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('No current location.'),
                                      ),
                                    );
                                  }
                                  return;
                                }
                              }

                              await _fetchRoute(mode: _orsProfileFor(mode));
                              await _updateRouteOnMap();
                              if (mounted) _fitToRoute();
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(
                            temp == null
                                ? Icons.info_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 18,
                            color: temp == null ? kSubtleText : kAccent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              temp == null
                                  ? 'Choose a mode to preview your route.'
                                  : 'Route preview fetched.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: kSubtleText,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.open_in_new_rounded, size: 19),
                          label: const Text(
                            'Open in Google Maps',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryDark,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFE5E7EB),
                            disabledForegroundColor: kSubtleText,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            elevation: 0,
                          ),
                          onPressed: temp == null
                              ? null
                              : () {
                                  Navigator.pop(ctx);
                                  _openExternalMaps(temp!);
                                },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    positionStream?.cancel();
    compassStream?.cancel();
    positionStream = null;
    compassStream = null;
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchRequiredApplications(
    SupabaseClient supabase,
    int id,
  ) async {
    for (final value in [id, id.toString()]) {
      try {
        final result = await supabase
            .from('required_applications')
            .select('title, description')
            .eq('dayung_unit_id', value)
            .order('id', ascending: true);

        return result
            .whereType<Map<String, dynamic>>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      } catch (_) {}
    }
    return [];
  }

  Future<void> _fetchRules() async {
    setState(() => _loadingRules = true);
    try {
      final supabase = Supabase.instance.client;
      final id = getDayungUnitId();
      if (id == null) {
        if (mounted) setState(() => _loadingRules = false);
        return;
      }

      final requiredApps = await _fetchRequiredApplications(supabase, id);
      Map<String, dynamic>? rules;
      if (requiredApps.isEmpty) {
        try {
          rules = await supabase
              .from('dayung_rules')
              .select()
              .eq('dayung_unit_id', id)
              .maybeSingle();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _rules = rules;
          _requiredApplications = requiredApps;
          _loadingRules = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRules = false);
    }
  }

  Future<void> _initLocation() async {
    debugPrint('Requesting location permission...');
    final ok = await LocationService.ensurePermission();
    debugPrint('Permission result: $ok');
    if (!ok) {
      if (!mounted) return;
      setState(() {
        _permissionDenied = true;
        _loadingLoc = false;
      });
      debugPrint('Permission denied');
      return;
    }

    Position? p;
    try {
      p = await LocationService.currentPosition(
        timeout: const Duration(seconds: 8),
      );
      debugPrint('Current position: $p');
    } catch (e) {
      debugPrint('Location fetch error: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _pos = p;
        _loadingLoc = false;
      });
      await _updateUserMarker();
      await _updateUserCircle();
    }
  }

  String _address(Map<String, dynamic> d) {
    final parts = <String>[
      if ((d['barangay'] ?? '').toString().isNotEmpty) d['barangay'],
      if ((d['city'] ?? '').toString().isNotEmpty) d['city'],
      if ((d['province'] ?? '').toString().isNotEmpty) d['province'],
    ];
    return parts.join(', ');
  }

  double? _distanceToDayung() {
    if (_pos == null || dayungLat == null || dayungLng == null) return null;
    try {
      return Geolocator.distanceBetween(
        _pos!.latitude,
        _pos!.longitude,
        dayungLat!,
        dayungLng!,
      );
    } catch (_) {
      return null;
    }
  }

  String _formatDistance(double meters) {
    final km = meters / 1000;
    if (km < 1) return '${meters.toStringAsFixed(0)} m';
    return km < 10
        ? '${km.toStringAsFixed(2)} km'
        : '${km.toStringAsFixed(1)} km';
  }

  void _centerOnDayung() {
    final lat = dayungLat, lng = dayungLng;
    if (lat == null || lng == null) return;
    if (kIsWeb) {
      _webMapController.move(ll.LatLng(lat, lng), 15);
      return;
    }
    if (_mlController == null) return;
    _mlController!.animateCamera(
      ml.CameraUpdate.newLatLngZoom(ml.LatLng(lat, lng), 15),
    );
  }

  void _centerOnUser() {
    if (_pos == null) return;
    if (kIsWeb) {
      _webMapController.move(ll.LatLng(_pos!.latitude, _pos!.longitude), 15);
      return;
    }
    if (_mlController == null) return;
    _mlController!.animateCamera(
      ml.CameraUpdate.newLatLngZoom(
        ml.LatLng(_pos!.latitude, _pos!.longitude),
        15,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (dayungLat == null || dayungLng == null) {
      return const Scaffold(
        body: Center(child: Text('No location data available.')),
      );
    }

    final dist = _distanceToDayung();
    final compactMapControls = MediaQuery.sizeOf(context).width < 600;
    final Widget? primaryMapChip;
    if (_loadingLoc) {
      primaryMapChip = _pillChip(
        icon: Icons.gps_fixed,
        label: 'Locating...',
        color: kPrimaryDark,
        pulse: true,
      );
    } else if (_permissionDenied) {
      primaryMapChip = _pillChip(
        icon: Icons.location_off,
        label: 'Location denied',
        color: kDanger,
      );
    } else if (dist != null) {
      primaryMapChip = _pillChip(
        icon: Icons.route,
        label: _formatDistance(dist),
        color: kPrimary,
      );
    } else if (_pos == null) {
      primaryMapChip = _pillChip(
        icon: Icons.location_searching,
        label: 'No GPS fix',
        color: kWarn,
      );
    } else {
      primaryMapChip = null;
    }
    final mapStatusChips = <Widget>[
      if (widget.isMember)
        _pillChip(icon: Icons.verified, label: 'Your Dayung', color: kAccent)
      else if (widget.isApplied)
        _pillChip(
          icon: Icons.check_circle_outline,
          label: 'Applied',
          color: kWarn,
        ),
      if (_etaMinutes != null)
        _pillChip(
          icon: Icons.timer,
          label: 'ETA: $_etaMinutes min',
          color: kPrimary,
        ),
      if (_selectedMode != null && _routePoints.isEmpty)
        _pillChip(
          icon: _selectedMode!.icon,
          label: '${_selectedMode!.label} (no route)',
          color: kSubtleText,
        )
      else if (_selectedMode != null)
        _pillChip(
          icon: _selectedMode!.icon,
          label: _selectedMode!.label,
          color: kPrimaryDark,
        ),
    ];
    final mapControls = _buildCompactMapControls();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  flex: _mapFlex.round(),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(34),
                    ),
                    child: Stack(
                      children: [
                        _buildModernMap(context),
                        // ml.MapLibreMap(
                        //   onMapCreated: _onMapCreated,
                        //   onStyleLoadedCallback: _onStyleLoaded,
                        //   styleString:
                        //       'https://api.maptiler.com/maps/basic-v2/style.json?key=ZgS5pYNNGTrRGUAnlS71',
                        //   initialCameraPosition: ml.CameraPosition(
                        //     target: ml.LatLng(dayungLat!, dayungLng!),
                        //     zoom: 15,
                        //   ),
                        //   rotateGesturesEnabled: false,
                        //   tiltGesturesEnabled: false,
                        //   myLocationEnabled: false,
                        //   attributionButtonMargins: const Point(12, 12),
                        //   logoViewMargins: const Point(12, 12),
                        // ),
                        Positioned(
                          top: MediaQuery.of(context).padding.top + 12,
                          left: 18,
                          child: _buildBackButton(),
                        ),
                        if (compactMapControls)
                          Positioned(
                            left: 16,
                            right: 20,
                            bottom: 16,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child:
                                        primaryMapChip ??
                                        const SizedBox.shrink(),
                                  ),
                                ),
                                if (!_loadingLoc && !_permissionDenied) ...[
                                  const SizedBox(width: 8),
                                  mapControls,
                                ],
                              ],
                            ),
                          )
                        else ...[
                          if (!_loadingLoc && !_permissionDenied)
                            Positioned(
                              right: 16,
                              bottom: 16,
                              child: mapControls,
                            ),
                          Positioned(
                            left: 16,
                            bottom: 16,
                            right: 168,
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                if (primaryMapChip != null) primaryMapChip,
                                ...mapStatusChips,
                              ],
                            ),
                          ),
                        ],
                        if (compactMapControls && mapStatusChips.isNotEmpty)
                          Positioned(
                            left: 16,
                            right: 44,
                            bottom: 72,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: mapStatusChips,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(flex: 100 - _mapFlex.round(), child: _infoPanel(dist)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackButton() {
    return Material(
      color: Colors.white,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_rounded, color: kNeutralText),
      ),
    );
  }

  Widget _infoPanel(double? dist) {
    final name =
        (widget.dayung['name'] ?? widget.dayung['dayung_unit_name'] ?? 'Dayung')
            .toString();
    final address = _address(widget.dayung);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
      decoration: const BoxDecoration(
        color: kPanelBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(38)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 22,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DayungMapResizeHandle(
                      onResize: (deltaY) {
                        final screenHeight = MediaQuery.sizeOf(context).height;
                        if (screenHeight <= 0) return;
                        setState(() {
                          _mapFlex = (_mapFlex + deltaY / screenHeight * 100)
                              .clamp(35.0, 82.0)
                              .toDouble();
                        });
                      },
                    ),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Montserrat',
                        color: kPrimaryDark,
                        height: 1.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 22,
                            color: kPrimary.withOpacity(.85),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              address,
                              style: const TextStyle(
                                fontSize: 16,
                                fontFamily: 'OpenSans',
                                color: kSubtleText,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (dist != null)
                          _infoChip(
                            icon: Icons.route_rounded,
                            label: _formatDistance(dist),
                            color: kPrimaryDark,
                            background: const Color(0xFFEFF6FF),
                          ),
                        _infoChip(
                          icon: widget.isMember
                              ? Icons.verified_rounded
                              : Icons.explore_rounded,
                          label: widget.isMember
                              ? 'Your registered Dayung'
                              : 'Explore this location',
                          color: widget.isMember ? kAccent : kWarn,
                          background: widget.isMember
                              ? const Color(0xFFECFDF5)
                              : const Color(0xFFFFF7E8),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (widget.allDayungs != null &&
                        widget.allDayungs!.isNotEmpty)
                      _nearbyScroller(),
                    const Spacer(),
                    _actionSection(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: color,
              fontWeight: FontWeight.w700,
              fontFamily: 'OpenSans',
            ),
          ),
        ],
      ),
    );
  }

  Widget _rulesSection(Map<String, dynamic>? rules) {
    final items = <Widget>[];
    void addRule(String label, String? value) {
      if (value != null && value.trim().isNotEmpty) {
        items.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: kPrimaryDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: kSubtleText,
                    fontFamily: 'OpenSans',
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    if (rules != null) {
      addRule('Contribution Rules', rules['contribution_rules']?.toString());
      addRule('Payout Rules', rules['payout_rules']?.toString());
      addRule('Membership Rules', rules['membership_rules']?.toString());
      addRule('Meeting Rules', rules['meeting_rules']?.toString());
      addRule('Service Rules', rules['service_rules']?.toString());
    }

    if (items.isEmpty) {
      final requiredApps = _requiredApplications;
      if (requiredApps.isNotEmpty) {
        String? mainTitle;
        final sectionWidgets = <Widget>[];

        for (final requiredApp in requiredApps) {
          final title = (requiredApp['title'] ?? '').toString().trim();
          final description = (requiredApp['description'] ?? '')
              .toString()
              .trim();
          if (title.isEmpty && description.isEmpty) {
            continue;
          }

          if (mainTitle == null && description.isEmpty) {
            mainTitle = title;
            continue;
          }

          sectionWidgets.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDBEAFE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.isNotEmpty)
                      Text(
                        title,
                        style: const TextStyle(
                          color: kPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    if (title.isNotEmpty) const SizedBox(height: 6),
                    if (description.isNotEmpty)
                      SizedBox(
                        height: 120,
                        child: SingleChildScrollView(
                          child: Text(
                            description,
                            style: const TextStyle(
                              color: kSubtleText,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (mainTitle != null && mainTitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    mainTitle,
                    style: const TextStyle(
                      color: kPrimaryDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ...sectionWidgets,
            ],
          ),
        );
      }
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text(
          'No rules set for this Dayung unit.',
          style: TextStyle(color: kSubtleText, fontSize: 13),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dayung Rules',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: kPrimary,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 6),
          ...items,
        ],
      ),
    );
  }

  Future<void> _showRulesSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final size = MediaQuery.sizeOf(sheetContext);
        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: size.width < 720 ? size.width : 720,
            height: size.height * 0.72,
            child: Container(
              decoration: const BoxDecoration(
                color: kPanelBg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Dayung Rules',
                            style: TextStyle(
                              color: kPrimaryDark,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Montserrat',
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close rules',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: FutureBuilder<void>(
                      future: _rulesLoadFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done ||
                            _loadingRules) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: _rulesSection(_rules),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _nearbyScroller() {
    final list = <Map<String, dynamic>>[];
    if (_pos != null && widget.allDayungs != null) {
      for (final d in widget.allDayungs!) {
        if (identical(d, widget.dayung)) continue;
        double? lat, lng;
        final rl = d['latitude'];
        final rg = d['longitude'];
        if (rl is num)
          // ignore: curly_braces_in_flow_control_structures
          lat = rl.toDouble();
        else if (rl is String)
          // ignore: curly_braces_in_flow_control_structures
          lat = double.tryParse(rl);
        if (rg is num)
          // ignore: curly_braces_in_flow_control_structures
          lng = rg.toDouble();
        else if (rg is String)
          // ignore: curly_braces_in_flow_control_structures
          lng = double.tryParse(rg);
        if (lat == null || lng == null) continue;
        final dist = Geolocator.distanceBetween(
          _pos!.latitude,
          _pos!.longitude,
          lat,
          lng,
        );
        if (dist <= widget.nearbyRadiusMeters) {
          final entry = Map<String, dynamic>.from(d);
          entry['_dist'] = dist;
          list.add(entry);
        }
      }
      list.sort(
        (a, b) => (a['_dist'] as double).compareTo(b['_dist'] as double),
      );
    }
    if (list.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text(
        //   "Nearby Dayungs",
        //   style: TextStyle(
        //     fontSize: 14,
        //     fontWeight: FontWeight.w700,
        //     fontFamily: 'Montserrat',
        //     color: kSubtleText.withOpacity(.9),
        //   ),
        // ),
        const SizedBox(height: 8),
        SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            padding: const EdgeInsets.only(right: 4),
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final d = list[i];
              final dName = (d['name'] ?? d['dayung_unit_name'] ?? 'Dayung')
                  .toString();
              final dist = d['_dist'] as double;
              return InkWell(
                onTap: () {
                  final lat = (d['latitude'] is num)
                      ? (d['latitude'] as num).toDouble()
                      : double.tryParse('${d['latitude']}');
                  final lng = (d['longitude'] is num)
                      ? (d['longitude'] as num).toDouble()
                      : double.tryParse('${d['longitude']}');
                  if (lat != null && lng != null) {
                    _mlController?.animateCamera(
                      ml.CameraUpdate.newLatLngZoom(ml.LatLng(lat, lng), 15),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 170,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: kPrimary.withOpacity(.25),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Montserrat',
                          height: 1.1,
                          color: kPrimaryDark,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          const Icon(
                            Icons.route,
                            size: 14,
                            color: kPrimaryDark,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDistance(dist),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'OpenSans',
                              color: kPrimaryDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _actionSection() {
    Widget status() {
      if (widget.isMember) {
        return _infoRow(Icons.verified, 'This is your Dayung', kAccent);
      }
      if (_applied) {
        return _infoRow(Icons.check_circle, 'Application pending', kWarn);
      }
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        status(),
        if (widget.allowApplication && !widget.isMember && !_applied) ...[
          const SizedBox(height: 10),
          _primaryButton(
            label: _submitting ? 'Submitting...' : 'Apply to this Dayung',
            icon: _submitting ? Icons.hourglass_top : Icons.how_to_reg,
            onTap: _submitting ? () {} : _applyToDayung,
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _showRulesSheet,
          icon: const Icon(Icons.menu_book_outlined),
          label: const Text('View Rules'),
          style: OutlinedButton.styleFrom(
            foregroundColor: kPrimary,
            minimumSize: const Size.fromHeight(48),
            side: BorderSide(color: kPrimary.withOpacity(.25)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _applyToDayung() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    final dayungUnitId = getDayungUnitId();

    debugPrint(
      'DEBUG: dayungUnitId value: '
      '([32m$dayungUnitId[0m) type: [34m${dayungUnitId.runtimeType}[0m',
    );

    if (uid == null || dayungUnitId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Missing user or unit.')));
      return;
    }

    setState(() => _submitting = true);
    try {
      // PREVENT duplicate
      final existing = await sb
          .from('applications')
          .select('id,status')
          .eq('user_id', uid)
          .eq('dayung_unit_id', dayungUnitId)
          .maybeSingle();
      if (existing != null) {
        setState(() => _applied = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Already ${existing['status']}.')),
        );
        return;
      }

      final unit = await sb
          .from('dayung_units')
          .select('name, secretary_id')
          .eq('id', dayungUnitId)
          .maybeSingle();

      final unitName = (unit?['name'] ?? widget.dayung['name'] ?? 'Dayung')
          .toString();

      final inserted = await sb
          .from('applications')
          .insert({
            'user_id': uid,
            'dayung_unit_id': dayungUnitId,
            'status': 'for_confirmation',
            'name': unitName,
          })
          .select('id')
          .single();
      final secretaryId = unit?['secretary_id'];
      if (secretaryId != null) {
        try {
          await sb.from('dayung_application_notifications').insert({
            'application_id': inserted['id'],
            'dayung_unit_id': dayungUnitId,
            'secretary_id': secretaryId,
          });
        } catch (_) {}
      }
      if (mounted) setState(() => _applied = true);

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ApplyMembershipWizard(
            dayungUnitId: dayungUnitId,
            dayungName: unitName,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // UI helpers
  Widget _pillChip({
    required IconData icon,
    required String label,
    required Color color,
    bool pulse = false,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(.55), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 8,
            offset: Offset(0, 3),
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
          if (pulse)
            Container(
              margin: const EdgeInsets.only(left: 6),
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontFamily: 'OpenSans',
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 22),
      label: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'Montserrat',
          ),
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 3,
      ),
      onPressed: onTap,
    );
  }

  Widget _buildCompactMapControls() {
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
            icon: Icons.route,
            tooltip: 'Directions',
            onTap: _showDirectionModeSheet,
          ),
          _compactMapButton(
            icon: Icons.flag_outlined,
            tooltip: 'Center on Dayung',
            onTap: _centerOnDayung,
          ),
          if (_pos != null)
            _compactMapButton(
              icon: Icons.my_location,
              tooltip: 'Center on me',
              onTap: _centerOnUser,
            ),
        ],
      ),
    );
  }

  Widget _compactMapButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      icon: Icon(icon, color: kPrimaryDark, size: 21),
    );
  }

  Widget _buildFlutterMap(double lat, double lng) {
    return FlutterMap(
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
              color: kAccent.withValues(alpha: 0.20),
              borderColor: kAccent,
              borderStrokeWidth: 2,
            ),
            if (_pos != null)
              CircleMarker(
                point: ll.LatLng(_pos!.latitude, _pos!.longitude),
                radius: 20,
                color: const Color(0xFF4285F4).withValues(alpha: 0.18),
              ),
          ],
        ),
        if (_routeLatLngs.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(points: _routeLatLngs, color: kPrimary, strokeWidth: 4),
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
                  color: kAccent,
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
                  Icons.apartment_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
            if (_pos != null)
              Marker(
                point: ll.LatLng(_pos!.latitude, _pos!.longitude),
                width: 44,
                height: 44,
                child: Transform.rotate(
                  angle:
                      (_compassHeading ??
                          (_pos!.heading.isFinite ? _pos!.heading : 0.0)) *
                      pi /
                      180,
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
        const DayungMapAttribution(
          alignment: Alignment.bottomLeft,
        ),
      ],
    );
  }

  Widget _buildModernMap(BuildContext context) {
    final lat = dayungLat, lng = dayungLng;
    if (lat == null || lng == null) {
      return const Center(child: Text('No location data.'));
    }
    if (kIsWeb) {
      return SizedBox.expand(child: _buildFlutterMap(lat, lng));
    }
    return SizedBox.expand(
      child: ml.MapLibreMap(
        styleString:
            'https://api.maptiler.com/maps/streets/style.json?key=ZgS5pYNNGTrRGUAnlS71',
        initialCameraPosition: ml.CameraPosition(
          target: ml.LatLng(lat, lng),
          zoom: 15,
        ),
        onMapCreated: (controller) async {
          _mlController = controller;
          await _onMapCreated(controller);
        },
        onStyleLoadedCallback: _onStyleLoaded,
        myLocationEnabled: false,
        compassEnabled: false,
        rotateGesturesEnabled: true,
        tiltGesturesEnabled: false,
        minMaxZoomPreference: const ml.MinMaxZoomPreference(12, 20),
        attributionButtonMargins:
            MediaQuery.sizeOf(context).width < 600 &&
                !_loadingLoc &&
                !_permissionDenied
            ? const Point(64, 16)
            : const Point(6, 6),
        logoViewMargins: const Point(6, 6),
      ),
    );
  }
}
