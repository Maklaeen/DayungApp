import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPinKey = 'app_pin_hash';
const _kPinUserKey = 'app_pin_user_id';

class PinService {
  static String _hash(String pin) =>
      sha256.convert(utf8.encode(pin)).toString();

  static Future<bool> hasPin(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPinKey) != null &&
        prefs.getString(_kPinUserKey) == userId;
  }

  static Future<void> savePin(String userId, String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPinKey, _hash(pin));
    await prefs.setString(_kPinUserKey, userId);
  }

  static Future<bool> verifyPin(String userId, String pin) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kPinUserKey) != userId) return false;
    return prefs.getString(_kPinKey) == _hash(pin);
  }

  static Future<void> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPinKey);
    await prefs.remove(_kPinUserKey);
  }
}
