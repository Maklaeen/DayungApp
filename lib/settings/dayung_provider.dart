import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DayungUnitProvider extends ChangeNotifier {
  String? _selectedDayungUnit;

  String? get selectedDayungUnit => _selectedDayungUnit;

  Future<void> loadDayungUnit() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedDayungUnit = prefs.getString('selectedDayungUnit') ?? 'Dayung';
    notifyListeners();
  }

  Future<void> setDayungUnit(String unit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedDayungUnit', unit);
    _selectedDayungUnit = unit;
    notifyListeners();
  }
}