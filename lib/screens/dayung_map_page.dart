import 'package:capstone_app/screens/locationservice.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

// Shared palette (aligned with Secretary dashboard / Claims)
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kWarn = Color(0xFFF57C00);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);
const Color kPanelBg = Colors.white;

class DayungMapPage extends StatefulWidget {
  final Map<String, dynamic> dayung;
  final bool isApplied;
  final bool isMember;
  final List<Map<String, dynamic>>? allDayungs; // optional: for nearby display
  final double nearbyRadiusMeters; // meters radius for highlighting others

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
    _initLocation();
  }

  Future<void> _initLocation() async {
    final ok = await LocationService.ensurePermission();
    if (!ok) {
      setState(() {
        _permissionDenied = true;
        _loadingLoc = false;
      });
      return;
    }
    final p = await LocationService.currentPosition();
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
    return Geolocator.distanceBetween(
      _pos!.latitude,
      _pos!.longitude,
      dayungLat!,
      dayungLng!,
    );
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    // Selected dayung marker
    if (dayungLat != null && dayungLng != null) {
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

    // Nearby other dayungs
    if (widget.allDayungs != null && _pos != null) {
      for (final d in widget.allDayungs!) {
        if (identical(d, widget.dayung)) continue;
        final rawLat = d['latitude'];
        final rawLng = d['longitude'];
        double? lat, lng;
        if (rawLat is num)
          lat = rawLat.toDouble();
        else if (rawLat is String)
          lat = double.tryParse(rawLat);
        if (rawLng is num)
          lng = rawLng.toDouble();
        else if (rawLng is String)
          lng = double.tryParse(rawLng);
        if (lat == null || lng == null) continue;
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

    // User marker
    if (_pos != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('me'),
          position: LatLng(_pos!.latitude, _pos!.longitude),
          infoWindow: const InfoWindow(title: 'You'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
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
      body: Stack(
        children: [
          // Map + top gradient + chips
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
                          onMapCreated: (c) => _map = c,
                        ),
                        // Gradient overlay for contrast
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
                        // Chips overlay
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

          // Floating recenter
          if (!_loadingLoc && !_permissionDenied && _pos != null)
            Positioned(
              right: 18,
              top: MediaQuery.of(context).padding.top + 82,
              child: _fabIcon(
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
          if (widget.allDayungs != null && widget.allDayungs!.isNotEmpty)
            _nearbyScroller(),
          const Spacer(),
          _actionSection(dist),
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
      if (widget.isApplied) {
        return _infoRow(Icons.check_circle, 'You already applied', kWarn);
      }
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        status(),
        if (!widget.isMember && !widget.isApplied) ...[
          const SizedBox(height: 10),
          _primaryButton(
            label: 'Apply to this Dayung',
            icon: Icons.how_to_reg,
            onTap: () => Navigator.pop(context, widget.dayung),
          ),
        ],
        const SizedBox(height: 8),
        if (dist != null)
          Align(
            alignment: Alignment.center,
            child: Text(
              'Approx. distance: ${_formatDistance(dist)}',
              style: TextStyle(
                fontSize: 11.5,
                fontFamily: 'OpenSans',
                color: kSubtleText.withOpacity(.75),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
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
