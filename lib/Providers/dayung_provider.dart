import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
// NEW: geolocation
import 'package:geolocator/geolocator.dart';

class DayungUnitProvider extends ChangeNotifier {
  String? _dayungUnit; // display name
  Map<String, dynamic>? _dayungUnitObj; // persisted object

  // NEW: user location + nearby computations
  Position? _lastPosition;
  bool _gettingLocation = false;
  String? _locationError;

  List<Map<String, dynamic>> _nearbyDayungs = [];
  // Each entry enriched with distanceMeters (double)
  double _lastRadius = 0;

  String? get dayungUnit => _dayungUnit;
  Map<String, dynamic>? get dayungUnitObj => _dayungUnitObj;

  Position? get lastPosition => _lastPosition;
  bool get gettingLocation => _gettingLocation;
  String? get locationError => _locationError;

  List<Map<String, dynamic>> get nearbyDayungs => _nearbyDayungs;
  double get lastRadius => _lastRadius;
  int? get currentUnitId {
    final v = _dayungUnitObj?['id'];
    if (v is int) return v;
    return int.tryParse('$v');
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  Map<String, dynamic> _normalizeUnit(Map<String, dynamic> u) {
    final lat = _toDouble(u['latitude'] ?? u['lat'] ?? u['latitute']);
    final lng = _toDouble(u['longitude'] ?? u['lng'] ?? u['long'] ?? u['lon']);
    return {
      ...u,
      'latitude': lat,
      'longitude': lng,
      // aliases to satisfy any old code paths
      'lat': lat,
      'lng': lng,
    };
  }

  // ---------------- Existing persistence ----------------
  Future<void> loadDayungUnit() async {
    final prefs = await SharedPreferences.getInstance();
    // CHANGED: prefer the full object, fallback to minimal
    final unitJson =
        prefs.getString('selectedDayungUnitData') ??
        prefs.getString('selectedDayungUnit');
    if (unitJson == null) {
      _dayungUnit = null;
      _dayungUnitObj = null;
      notifyListeners();
      return;
    }
    try {
      final obj = Map<String, dynamic>.from(jsonDecode(unitJson) as Map);
      final normalized = _normalizeUnit(obj); // NEW
      _dayungUnitObj = normalized;
      _dayungUnit = normalized['name']?.toString();
    } catch (_) {
      _dayungUnit = null;
      _dayungUnitObj = null;
      await prefs.remove('selectedDayungUnit');
      await prefs.remove('selectedDayungUnitData'); // NEW
    }
    notifyListeners();
  }

  void setDayungUnit(String? name, {Map<String, dynamic>? obj}) {
    _dayungUnit = name;
    if (obj != null) {
      _dayungUnitObj = _normalizeUnit(Map<String, dynamic>.from(obj)); // NEW
    }
    notifyListeners();
  }

  Future<void> persistSelection(Map<String, dynamic> unit) async {
    _dayungUnitObj = _normalizeUnit(Map<String, dynamic>.from(unit)); // NEW
    _dayungUnit = _dayungUnitObj!['name']?.toString();
    final prefs = await SharedPreferences.getInstance();
    // Save both keys so all pages stay in sync
    final json = jsonEncode(_dayungUnitObj);
    await prefs.setString('selectedDayungUnit', json);
    await prefs.setString('selectedDayungUnitData', json);
    notifyListeners();
  }

  Future<void> setDayungUnitAndSave(
    String? name,
    Map<String, dynamic>? obj,
  ) async {
    _dayungUnit = name;
    _dayungUnitObj = obj != null
        ? _normalizeUnit(Map<String, dynamic>.from(obj))
        : null; // NEW
    final prefs = await SharedPreferences.getInstance();
    if (_dayungUnitObj == null) {
      await prefs.remove('selectedDayungUnit');
      await prefs.remove('selectedDayungUnitData'); // NEW
    } else {
      final json = jsonEncode(_dayungUnitObj);
      await prefs.setString('selectedDayungUnit', json);
      await prefs.setString('selectedDayungUnitData', json); // NEW
    }
    notifyListeners();
  }

  void setDayungUnitObj(Map<String, dynamic>? obj) {
    _dayungUnitObj = obj != null
        ? _normalizeUnit(Map<String, dynamic>.from(obj))
        : null; // NEW
    _dayungUnit = _dayungUnitObj?['name']?.toString();
    notifyListeners();
  }

  void computeNearby(
    List<Map<String, dynamic>> allDayungs, {
    double radiusMeters = 5000,
  }) {
    if (_lastPosition == null) {
      _nearbyDayungs = [];
      _lastRadius = radiusMeters;
      notifyListeners();
      return;
    }
    final userLat = _lastPosition!.latitude;
    final userLng = _lastPosition!.longitude;

    final results = <Map<String, dynamic>>[];
    for (final d in allDayungs) {
      final nd = _normalizeUnit(d); // NEW: ensure doubles
      final lat = nd['latitude'] as double?;
      final lng = nd['longitude'] as double?;
      if (lat == null || lng == null) continue;
      final dist = Geolocator.distanceBetween(userLat, userLng, lat, lng);
      if (radiusMeters > 0 && dist > radiusMeters) continue;
      final enriched = Map<String, dynamic>.from(nd);
      enriched['distanceMeters'] = dist;
      results.add(enriched);
    }
    results.sort(
      (a, b) => (a['distanceMeters'] as double).compareTo(
        b['distanceMeters'] as double,
      ),
    );
    _nearbyDayungs = results;
    _lastRadius = radiusMeters;
    notifyListeners();
  }

  Future<void> clear() async {
    _dayungUnit = null;
    _dayungUnitObj = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selectedDayungUnit');
    await prefs.remove('selectedDayungUnitData'); // NEW
    notifyListeners();
  }

  // ---------------- NEW: Geolocation helpers ----------------

  Future<bool> _ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _locationError = 'Location services disabled';
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.denied) {
      _locationError = 'Permission denied';
      return false;
    }
    _locationError = null;
    return true;
  }

  Future<void> updateUserLocation({bool force = false}) async {
    if (_gettingLocation) return;
    if (!force && _lastPosition != null) return;
    _gettingLocation = true;
    _locationError = null;
    notifyListeners();
    try {
      final ok = await _ensurePermission();
      if (!ok) {
        _gettingLocation = false;
        notifyListeners();
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _lastPosition = pos;
    } catch (e) {
      _locationError = 'Failed: $e';
    } finally {
      _gettingLocation = false;
      notifyListeners();
    }
  }

  // Convenience formatting
  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    final km = meters / 1000;
    return km < 10
        ? '${km.toStringAsFixed(2)} km'
        : '${km.toStringAsFixed(1)} km';
  }
}
