import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DayungUnitProvider extends ChangeNotifier {
  String? _dayungUnit; // display name (e.g., "Buhangin Dayung")
  Map<String, dynamic>? _dayungUnitObj; // full persisted object from prefs

  String? get dayungUnit => _dayungUnit;
  Map<String, dynamic>? get dayungUnitObj => _dayungUnitObj;

  // Load from SharedPreferences at app start
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

  // Set in-memory (headers update immediately)
  void setDayungUnit(String? name, {Map<String, dynamic>? obj}) {
    _dayungUnit = name;
    if (obj != null) {
      _dayungUnitObj = Map<String, dynamic>.from(obj);
    }
    notifyListeners();
  }

  // Set and persist to SharedPreferences
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

  // Replace full object (no name passed)
  void setDayungUnitObj(Map<String, dynamic>? obj) {
    _dayungUnitObj = obj != null ? Map<String, dynamic>.from(obj) : null;
    _dayungUnit = _dayungUnitObj?['name']?.toString();
    notifyListeners();
  }

  // Clear in-memory and prefs
  Future<void> clear() async {
    _dayungUnit = null;
    _dayungUnitObj = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selectedDayungUnit');
    notifyListeners();
  }
}
