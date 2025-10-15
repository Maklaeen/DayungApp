// filepath: lib/screens/dayung_map_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:url_launcher/url_launcher.dart';

// Shared palette
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

  static Future<Position?> currentPosition() async {
    try {
      final ok = await ensurePermission();
      if (!ok) return null;
      return Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      return null;
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
  GoogleMapController? _map;
  Position? _pos;
  bool _loadingLoc = true;
  bool _permissionDenied = false;
  StreamSubscription<Position>? positionStream;
  Map<String, dynamic>? _rules;
  bool _loadingRules = true;
  BitmapDescriptor? _arrowIcon;
  double? _compassHeading;
  StreamSubscription<CompassEvent>? compassStream;
  bool _applied = false;
  bool _submitting = false;

  NavMode _selectedMode = NavMode.driving;

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

  double _wrapHeading(double? h) {
    if (h == null || h.isNaN || !h.isFinite) return 0.0;
    final n = h % 360.0;
    return n < 0 ? n + 360.0 : n;
  }

  bool _isValidLatLng(double lat, double lng) {
    return lat.isFinite &&
        lng.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
  }

  @override
  void initState() {
    super.initState();
    _applied = widget.isApplied;
    _loadArrowIcon();
    _initLocation();
    _fetchRules();

    compassStream = FlutterCompass.events?.listen((event) {
      final heading = event.heading;
      if (!mounted || heading == null || heading.isNaN) return;
      if (_compassHeading == null || (heading - _compassHeading!).abs() > 1.5) {
        setState(() => _compassHeading = heading);
      }
    });

    positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((position) {
          if (!mounted) return;
          setState(() => _pos = position);
        });
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
        NavMode temp = _selectedMode;
        return StatefulBuilder(
          builder: (ctx, setM) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Open in Google Maps',
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
                      final active = m == temp;
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
                        onSelected: (_) => setM(() => temp = m),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open Google Maps'),
                      onPressed: () {
                        setState(() => _selectedMode = temp);
                        Navigator.pop(ctx);
                        _openExternalMaps(temp);
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select a travel mode then open external navigation. '
                    'In‑app polyline preview was removed for performance.',
                    style: const TextStyle(fontSize: 11, color: kSubtleText),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadArrowIcon() async {
    try {
      final icon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/images/wew.png',
      );
      if (mounted) setState(() => _arrowIcon = icon);
    } catch (_) {}
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
    final ok = await LocationService.ensurePermission();
    if (!ok) {
      if (!mounted) return;
      setState(() {
        _permissionDenied = true;
        _loadingLoc = false;
      });
      return;
    }
    final p = await LocationService.currentPosition();
    if (!mounted) return;
    setState(() {
      _pos = p;
      _loadingLoc = false;
    });
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

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    final rot = _wrapHeading(_compassHeading);

    if (_pos != null && _isValidLatLng(_pos!.latitude, _pos!.longitude)) {
      if (_arrowIcon != null) {
        markers.add(
          Marker(
            markerId: const MarkerId('me'),
            position: LatLng(_pos!.latitude, _pos!.longitude),
            infoWindow: const InfoWindow(title: 'You'),
            icon: _arrowIcon!,
            rotation: rot,
            flat: true,
            anchor: const Offset(0.5, 0.5),
            zIndex: 999,
          ),
        );
      } else {
        // Safe fallback if asset icon failed to load
        markers.add(
          Marker(
            markerId: const MarkerId('me'),
            position: LatLng(_pos!.latitude, _pos!.longitude),
            infoWindow: const InfoWindow(title: 'You'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueBlue,
            ),
            rotation: rot,
            flat: true,
            zIndex: 999,
          ),
        );
      }
    }

    if (dayungLat != null &&
        dayungLng != null &&
        _isValidLatLng(dayungLat!, dayungLng!)) {
      markers.add(
        Marker(
          markerId: const MarkerId('selected_dayung'),
          position: LatLng(dayungLat!, dayungLng!),
          infoWindow: InfoWindow(
            title: (widget.dayung['name'] ?? 'Dayung').toString(),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            widget.isMember
                ? BitmapDescriptor.hueAzure
                : BitmapDescriptor.hueRed,
          ),
        ),
      );
    }

    if (widget.allDayungs != null && _pos != null) {
      for (final d in widget.allDayungs!) {
        if (identical(d, widget.dayung)) continue;
        final rl = d['latitude'], rg = d['longitude'];
        final lat = rl is num ? rl.toDouble() : double.tryParse('$rl');
        final lng = rg is num ? rg.toDouble() : double.tryParse('$rg');
        if (lat == null || lng == null || !_isValidLatLng(lat, lng)) continue;
        final dist = Geolocator.distanceBetween(
          _pos!.latitude,
          _pos!.longitude,
          lat,
          lng,
        );
        if (dist <= widget.nearbyRadiusMeters) {
          markers.add(
            Marker(
              markerId: MarkerId('dayung_${d['id']}'),
              position: LatLng(lat, lng),
              infoWindow: InfoWindow(title: (d['name'] ?? 'Dayung').toString()),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
            ),
          );
        }
      }
    }
    return markers;
  }

  Circle? _nearbyCircle() {
    if (_pos == null) return null;
    return Circle(
      circleId: const CircleId('radius'),
      center: LatLng(_pos!.latitude, _pos!.longitude),
      radius: widget.nearbyRadiusMeters,
      strokeWidth: 1,
      strokeColor: kPrimary.withOpacity(.45),
      fillColor: kPrimary.withOpacity(.10),
    );
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
    if (_map == null || lat == null || lng == null) return;
    _map!.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15));
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
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'directionsFab',
        backgroundColor: const Color.fromARGB(255, 239, 239, 239),
        icon: const Icon(Icons.directions),
        label: const Text('Open Maps'),
        onPressed: _showDirectionModeSheet,
      ),
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
                        GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: LatLng(dayungLat!, dayungLng!),
                            zoom: 15,
                          ),
                          markers: _buildMarkers(),
                          circles: {
                            if (_nearbyCircle() != null) _nearbyCircle()!,
                          },
                          myLocationEnabled: false,
                          zoomControlsEnabled: false,
                          onMapCreated: (c) {
                            _map = c;
                            final lat = dayungLat, lng = dayungLng;
                            if (lat != null && lng != null) {
                              // Recenter to the selected Dayung to avoid any stale camera state
                              _map!.moveCamera(
                                CameraUpdate.newLatLngZoom(
                                  LatLng(lat, lng),
                                  15,
                                ),
                              );
                            }
                          },
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
          if (!_loadingLoc && !_permissionDenied && _pos != null)
            Positioned(
              right: 18,
              top: MediaQuery.of(context).padding.top + 82,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // NEW: Center to Dayung button (always available if map/coords exist)
                  _fabIcon(
                    icon: Icons.flag_outlined, // or Icons.location_on_outlined
                    onTap: _centerOnDayung,
                  ),
                  const SizedBox(height: 12),
                  // Existing: Center to Me button (only when we have a user location)
                  if (!_loadingLoc && !_permissionDenied && _pos != null)
                    _fabIcon(
                      icon: Icons.my_location,
                      onTap: () {
                        if (_map != null && _pos != null) {
                          _map!.animateCamera(
                            CameraUpdate.newLatLng(
                              LatLng(_pos!.latitude, _pos!.longitude),
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
    final name = (widget.dayung['name'] ?? 'Dayung').toString();
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
          lat = rl.toDouble();
        else if (rl is String)
          lat = double.tryParse(rl);
        if (rg is num)
          lng = rg.toDouble();
        else if (rg is String)
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
        Text(
          "Nearby Dayungs",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFamily: 'Montserrat',
            color: kSubtleText.withOpacity(.9),
          ),
        ),
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
              final dName = (d['name'] ?? 'Dayung').toString();
              final dist = d['_dist'] as double;
              return InkWell(
                onTap: () {
                  final lat = (d['latitude'] is num)
                      ? (d['latitude'] as num).toDouble()
                      : double.tryParse('${d['latitude']}');
                  final lng = (d['longitude'] is num)
                      ? (d['longitude'] as num).toDouble()
                      : double.tryParse('${d['longitude']}');
                  if (lat != null && lng != null && _map != null) {
                    _map!.animateCamera(
                      CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15),
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
        return _infoRow(Icons.check_circle, 'Application submitted', kWarn);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot apply: missing user or unit.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      Map<String, dynamic>? existing;
      try {
        existing = await sb
            .from('applications')
            .select('id, status')
            .eq('user_id', uid)
            .eq('dayung_unit_id', dayungId)
            .maybeSingle();
      } catch (_) {
        existing = null;
      }
      if (existing != null) {
        setState(() => _applied = true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Already ${existing['status'] ?? 'pending'}')),
        );
        Navigator.pop(context, {'applied': true, 'dayung_id': dayungId});
        return;
      }

      await sb.from('applications').insert({
        'user_id': uid,
        'dayung_unit_id': dayungId,
        'status': 'pending',
      });

      if (!mounted) return;
      setState(() => _applied = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Application submitted.')));
      Navigator.pop(context, {'applied': true, 'dayung_id': dayungId});
    } on PostgrestException catch (e) {
      final code = e.code ?? '';
      final msg = (e.message).toLowerCase();
      if (code == '23505' ||
          msg.contains('unique') ||
          msg.contains('duplicate')) {
        if (mounted) {
          setState(() => _applied = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You already applied to this Dayung.'),
            ),
          );
          Navigator.pop(context, {'applied': true, 'dayung_id': dayungId});
        }
      } else if (code == '23503' || msg.contains('foreign key')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile not found. Complete registration first.'),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to apply: ${e.message}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to apply: $e')));
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
