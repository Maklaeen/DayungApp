// filepath: lib/screens/dayung_map_page.dart
// ignore_for_file: deprecated_member_use, control_flow_in_finally, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

// color palette
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kWarn = Color(0xFFF57C00);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);
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
  final List<Map<String, dynamic>>? allDayungs;
  final double nearbyRadiusMeters;

  const DayungMapPage({
    super.key,
    required this.dayung,
    this.isApplied = false,
    this.isMember = false,
    this.allDayungs,
    this.nearbyRadiusMeters = 5000,
  });

  @override
  State<DayungMapPage> createState() => _DayungMapPageState();
}

class _DayungMapPageState extends State<DayungMapPage> {
  ml.MapLibreMapController? _mlController;
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
  bool _loadingRules = true;
  double? _compassHeading;
  StreamSubscription<CompassEvent>? compassStream;
  bool _applied = false;
  bool _submitting = false;
  bool _loadingRoute = false;
  int? _etaMinutes;
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

  @override
  void initState() {
    super.initState();
    _applied = widget.isApplied;
    _fetchRules();

    compassStream = FlutterCompass.events?.listen((event) {
      final heading = event.heading;
      if (!mounted || heading == null || heading.isNaN) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastCompassUpdateMs > 300 &&
          (_compassHeading == null || (heading - _compassHeading!).abs() > 6)) {
        _lastCompassUpdateMs = now;
        setState(() => _compassHeading = heading);
      }
    });
    _loadSavedMode();
    _initLocation();
    _checkExistingApplication();
  }

  void _onCompass(CompassEvent event) {
    final heading = event.heading;
    if (!mounted || heading == null || heading.isNaN) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastCompassUpdateMs > 300 &&
        (_compassHeading == null || (heading - _compassHeading!).abs() > 6)) {
      _lastCompassUpdateMs = now;
      setState(() => _compassHeading = heading);
    }
  }

  Future<void> _checkExistingApplication() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    final rawId = widget.dayung['id'];
    final dayungId = rawId is int ? rawId : int.tryParse('$rawId');
    if (uid == null || dayungId == null) return;
    try {
      final existing = await sb
          .from('applications')
          .select('id,status')
          .eq('user_id', uid)
          .eq('dayung_unit_id', dayungId)
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
    if (_dayungSymbol == null) {
      _dayungSymbol = await _mlController!.addSymbol(
        ml.SymbolOptions(
          geometry: ml.LatLng(lat, lng),
          iconImage: 'marker-15',
          iconSize: 1.6,
        ),
      );
    }
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
            circleColor: "#0D47A1",
            circleOpacity: 0.18,
            circleStrokeColor: "#0D47A1",
            circleStrokeWidth: 2.0,
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
            circleColor: "#0D47A1",
            circleOpacity: 0.18,
            circleStrokeColor: "#0D47A1",
            circleStrokeWidth: 2.0,
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
    final here = ml.LatLng(_pos!.latitude, _pos!.longitude);
    if (_userSymbol == null) {
      _userSymbol = await _mlController!.addSymbol(
        ml.SymbolOptions(
          geometry: here,
          iconImage: 'marker-15',
          iconColor: '#0D47A1',
          iconSize: 1.4,
        ),
      );
    } else {
      await _mlController!.updateSymbol(
        _userSymbol!,
        ml.SymbolOptions(geometry: here),
      );
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

  Future<void> _loadSavedMode() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt('nav_mode');
    if (idx != null &&
        idx >= 0 &&
        idx < NavMode.values.length &&
        _selectedMode == null) {
      setState(() => _selectedMode = NavMode.values[idx]);
    }
  }

  Future<void> _saveMode(NavMode? m) async {
    final prefs = await SharedPreferences.getInstance();
    if (m == null) {
      await prefs.remove('nav_mode');
    } else {
      await prefs.setInt('nav_mode', m.index);
    }
  }

  void _fitToRoute() {
    if (_routePoints.length < 2 || _mlController == null) return;
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

  Future<void> _getDirectionsAndFit() async {
    if (_selectedMode == null) return;
    if (_pos == null) {
      await _initLocation();
      if (_pos == null) return;
    }
    final profile = _orsProfileFor(_selectedMode!);
    await _fetchRoute(mode: profile);
    await _updateRouteOnMap();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitToRoute());
  }

  Future<void> _fetchRoute({String mode = 'foot-walking'}) async {
    if (_pos == null || dayungLat == null || dayungLng == null) return;
    setState(() => _loadingRoute = true);

    final apiKey =
        'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjJmYTI4ZjFkODc3NzQ1ZTNiNGI3ZGIxNGI5MGFlYzI1IiwiaCI6Im11cm11cjY0In0='; // <-- Replace with your ORS key
    final startLng = _pos!.longitude;
    final startLat = _pos!.latitude;
    final endLng = dayungLng!;
    final endLat = dayungLat!;

    final url =
        'https://api.openrouteservice.org/v2/directions/$mode?api_key=$apiKey&start=$startLng,$startLat&end=$endLng,$endLat';
    print('ORS GET $url');

    try {
      final response = await http.get(Uri.parse(url));
      print('ORS status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final coords = data['features'][0]['geometry']['coordinates'];
        final summary = data['features'][0]['properties']['summary'];
        final durationSeconds = summary['duration'];
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
        print('ORS error body: ${response.body}');
        if (mounted) {
          setState(() {
            _routePoints = [];
            _etaMinutes = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to fetch route')),
          );
        }
      }
    } catch (e) {
      print('ORS fetch error: $e');
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  Future<void> _openExternalMaps(NavMode mode) async {
    if (dayungLat == null || dayungLng == null) return;
    final dLat = dayungLat!;
    final dLng = dayungLng!;
    final travel = mode.apiValue;
    final url =
        'https://www.google.com/maps/dir/?api=1&destination=$dLat,$dLng&travelmode=$travel';
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
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        NavMode? temp = _selectedMode;
        return StatefulBuilder(
          builder: (ctx, setM) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Select Travel Mode',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    children: NavMode.values.map((m) {
                      final active = temp == m;
                      return ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(m.icon, size: 16),
                            const SizedBox(width: 6),
                            Text(m.label),
                          ],
                        ),
                        selected: active,
                        onSelected: (_) async {
                          setM(() => temp = m);
                          setState(() => _selectedMode = temp);
                          await _saveMode(temp);

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

                          final profile = _orsProfileFor(temp!);
                          await _fetchRoute(mode: profile);
                          await _updateRouteOnMap();
                          if (mounted) _fitToRoute();
                          if (mounted) Navigator.pop(ctx);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open Google Maps'),
                      onPressed: temp == null
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _openExternalMaps(temp!);
                            },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    temp == null
                        ? 'Pick a mode to preview route and ETA.'
                        : 'Route preview fetched.',
                    style: const TextStyle(fontSize: 11, color: kSubtleText),
                    textAlign: TextAlign.center,
                  ),
                  if (temp != null)
                    TextButton(
                      onPressed: () async {
                        setM(() => temp = null);
                        setState(() => _selectedMode = null);
                        await _saveMode(null);
                        setState(() {
                          _routePoints = [];
                          _etaMinutes = null;
                        });
                      },
                      child: const Text(
                        'Clear selection',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
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

  Future<void> _fetchRules() async {
    setState(() => _loadingRules = true);
    try {
      final supabase = Supabase.instance.client;
      final id = widget.dayung['id'];
      final res = await supabase
          .from('dayung_rules')
          .select()
          .eq('dayung_unit_id', id)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _rules = res;
          _loadingRules = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRules = false);
    }
  }

  Future<void> _initLocation() async {
    print('Requesting location permission...');
    final ok = await LocationService.ensurePermission();
    print('Permission result: $ok');
    if (!ok) {
      if (!mounted) return;
      setState(() {
        _permissionDenied = true;
        _loadingLoc = false;
      });
      print('Permission denied');
      return;
    }

    Position? p;
    try {
      p = await LocationService.currentPosition(
        timeout: const Duration(seconds: 8),
      );
      print('Current position: $p');
    } catch (e) {
      print('Location fetch error: $e');
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
    if (lat == null || lng == null || _mlController == null) return;
    _mlController!.animateCamera(
      ml.CameraUpdate.newLatLngZoom(ml.LatLng(lat, lng), 15),
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

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF7),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          (widget.dayung['name'] ?? 'Dayung Location').toString(),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontFamily: 'Montserrat',
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      // floatingActionButton: FloatingActionButton.extended(
      //   heroTag: 'directionsFab',
      //   backgroundColor: const Color.fromARGB(255, 239, 239, 239),
      //   icon: const Icon(Icons.directions),
      //   label: const Text('Open Maps'),
      //   onPressed: _showDirectionModeSheet,
      // ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  flex: 55,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(34),
                    ),
                    child: Stack(
                      children: [
                        ml.MapLibreMap(
                          onMapCreated: _onMapCreated,
                          onStyleLoadedCallback: _onStyleLoaded,
                          styleString:
                              'https://api.maptiler.com/maps/basic-v2/style.json?key=ZgS5pYNNGTrRGUAnlS71',
                          initialCameraPosition: ml.CameraPosition(
                            target: ml.LatLng(dayungLat!, dayungLng!),
                            zoom: 15,
                          ),
                          rotateGesturesEnabled: false,
                          tiltGesturesEnabled: false,
                          myLocationEnabled: false,
                          attributionButtonMargins: const Point(12, 12),
                          logoViewMargins: const Point(12, 12),
                        ),
                        Container(
                          height: 140,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xCC0D47A1), Color(0x000D47A1)],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          bottom: 16,
                          right: 16,
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              if (!_loadingLoc &&
                                  !_permissionDenied &&
                                  dist != null)
                                _pillChip(
                                  icon: Icons.route,
                                  label: _formatDistance(dist),
                                  color: kPrimary,
                                ),
                              if (_loadingLoc)
                                _pillChip(
                                  icon: Icons.gps_fixed,
                                  label: 'Locating...',
                                  color: kPrimaryDark,
                                  pulse: true,
                                ),
                              if (_permissionDenied)
                                _pillChip(
                                  icon: Icons.location_off,
                                  label: 'Location denied',
                                  color: kDanger,
                                ),
                              if (!_loadingLoc &&
                                  !_permissionDenied &&
                                  _pos == null)
                                _pillChip(
                                  icon: Icons.location_searching,
                                  label: 'No GPS fix',
                                  color: kWarn,
                                ),
                              if (widget.isMember)
                                _pillChip(
                                  icon: Icons.verified,
                                  label: 'Your Dayung',
                                  color: kAccent,
                                )
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
                              if (_selectedMode == null)
                                _pillChip(
                                  icon: Icons.info_outline,
                                  label: 'Pick mode',
                                  color: kSubtleText,
                                )
                              else if (_routePoints.isEmpty)
                                _pillChip(
                                  icon: _selectedMode!.icon,
                                  label: '${_selectedMode!.label} (no route)',
                                  color: kSubtleText,
                                )
                              else
                                _pillChip(
                                  icon: _selectedMode!.icon,
                                  label: '${_selectedMode!.label}',
                                  color: kPrimaryDark,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(flex: 45, child: _infoPanel(dist)),
              ],
            ),
          ),
          if (!_loadingLoc && !_permissionDenied)
            Positioned(
              right: 18,
              top: MediaQuery.of(context).padding.top + 82,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _fabIcon(icon: Icons.route, onTap: _showDirectionModeSheet),
                  const SizedBox(height: 12),
                  _fabIcon(icon: Icons.flag_outlined, onTap: _centerOnDayung),
                  const SizedBox(height: 12),
                  if (_pos != null)
                    _fabIcon(
                      icon: Icons.my_location,
                      onTap: () {
                        if (_pos != null) {
                          _mlController!.animateCamera(
                            ml.CameraUpdate.newLatLngZoom(
                              ml.LatLng(_pos!.latitude, _pos!.longitude),
                              15,
                            ),
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
        ],
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
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
      decoration: const BoxDecoration(
        color: kPanelBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(38)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 22,
            offset: Offset(0, -4),
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
                    Center(
                      child: Container(
                        width: 48,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 22,
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
                            size: 18,
                            color: kPrimary.withOpacity(.85),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              address,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontFamily: 'OpenSans',
                                color: kSubtleText,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (widget.allDayungs != null &&
                        widget.allDayungs!.isNotEmpty)
                      _nearbyScroller(),
                    if (_loadingRules)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_rules != null)
                      _rulesSection(_rules!),
                    const Spacer(),
                    _actionSection(dist),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _rulesSection(Map<String, dynamic> rules) {
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

    addRule('Contribution Rules', rules['contribution_rules']);
    addRule('Payout Rules', rules['payout_rules']);
    addRule('Membership Rules', rules['membership_rules']);
    addRule('Meeting Rules', rules['meeting_rules']);
    addRule('Service Rules', rules['service_rules']);

    if (items.isEmpty) {
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

  Widget _actionSection(double? dist) {
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
        if (!widget.isMember && !_applied) ...[
          const SizedBox(height: 10),
          _primaryButton(
            label: _submitting ? 'Submitting...' : 'Apply to this Dayung',
            icon: _submitting ? Icons.hourglass_top : Icons.how_to_reg,
            onTap: _submitting ? () {} : _applyToDayung,
          ),
        ],
        const SizedBox(height: 10),
        if (dist != null) Align(alignment: Alignment.center),
      ],
    );
  }

  Future<void> _applyToDayung() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    final rawId = widget.dayung['id'];
    final dayungId = rawId is int ? rawId : int.tryParse('$rawId');

    if (uid == null || dayungId == null) {
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
          .eq('dayung_unit_id', dayungId)
          .maybeSingle();
      if (existing != null) {
        setState(() => _applied = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Already ${existing['status']}.')),
        );
        return;
      }

      // Fetch dayung name + secretary_id
      final unit = await sb
          .from('dayung_units')
          .select('name, secretary_id')
          .eq('id', dayungId)
          .maybeSingle();

      final unitName = (unit?['name'] ?? widget.dayung['name'] ?? 'Dayung')
          .toString();
      final secretaryId = unit?['secretary_id'];

      // Insert application WITH name
      final inserted = await sb
          .from('applications')
          .insert({
            'user_id': uid,
            'dayung_unit_id': dayungId,
            'status': 'pending',
            'name': unitName,
          })
          .select('id')
          .single();

      // OPTIONAL secretary notification (create table first, see SQL below)
      if (secretaryId != null) {
        try {
          await sb.from('dayung_application_notifications').insert({
            'application_id': inserted['id'],
            'dayung_unit_id': dayungId,
            'secretary_id': secretaryId,
          });
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() => _applied = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Application sent to $unitName.')));
      Navigator.pop(context, {'applied': true, 'dayung_id': dayungId});
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
              fontSize: 14,
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
            fontSize: 16.5,
            fontWeight: FontWeight.w700,
            fontFamily: 'Montserrat',
          ),
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 3,
      ),
      onPressed: onTap,
    );
  }

  Widget _fabIcon({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: kPrimary,
      shape: const CircleBorder(),
      elevation: 6,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 50,
          height: 50,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}
