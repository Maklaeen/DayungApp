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

  // ---------------- Existing persistence ----------------
  Future<void> loadDayungUnit() async {
    final prefs = await SharedPreferences.getInstance();
    final unitJson = prefs.getString('selectedDayungUnit');
    if (unitJson == null) {
      _dayungUnit = null;
      _dayungUnitObj = null;
      notifyListeners();
      return;
    }
    try {
      final obj = Map<String, dynamic>.from(jsonDecode(unitJson) as Map);
      _dayungUnitObj = obj;
      _dayungUnit = obj['name']?.toString();
    } catch (_) {
      _dayungUnit = null;
      _dayungUnitObj = null;
      await prefs.remove('selectedDayungUnit');
    }
    notifyListeners();
  }

  void setDayungUnit(String? name, {Map<String, dynamic>? obj}) {
    _dayungUnit = name;
    if (obj != null) {
      _dayungUnitObj = Map<String, dynamic>.from(obj);
    }
    notifyListeners();
  }

  Future<void> setDayungUnitAndSave(
    String? name,
    Map<String, dynamic>? obj,
  ) async {
    _dayungUnit = name;
    _dayungUnitObj = obj != null ? Map<String, dynamic>.from(obj) : null;
    final prefs = await SharedPreferences.getInstance();
    if (_dayungUnitObj == null) {
      await prefs.remove('selectedDayungUnit');
    } else {
      await prefs.setString('selectedDayungUnit', jsonEncode(_dayungUnitObj));
    }
    notifyListeners();
  }

  void setDayungUnitObj(Map<String, dynamic>? obj) {
    _dayungUnitObj = obj != null ? Map<String, dynamic>.from(obj) : null;
    _dayungUnit = _dayungUnitObj?['name']?.toString();
    notifyListeners();
  }

  Future<void> clear() async {
    _dayungUnit = null;
    _dayungUnitObj = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selectedDayungUnit');
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

  // Provide distances for given dayung units (list of maps each containing latitude/longitude)
  // radiusMeters: if > 0 filters by radius, else returns all with distances
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
      final latRaw = d['latitude'];
      final lngRaw = d['longitude'];
      if (latRaw is! num || lngRaw is! num) continue;
      final lat = latRaw.toDouble();
      final lng = lngRaw.toDouble();
      final dist = Geolocator.distanceBetween(userLat, userLng, lat, lng);
      if (radiusMeters > 0 && dist > radiusMeters) continue;
      final enriched = Map<String, dynamic>.from(d);
      enriched['distanceMeters'] = dist;
      results.add(enriched);
    }
    results.sort(
      (a, b) =>
          (a['distanceMeters'] as double).compareTo(b['distanceMeters'] as double),
    );
    _nearbyDayungs = results;
    _lastRadius = radiusMeters;
    notifyListeners();
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