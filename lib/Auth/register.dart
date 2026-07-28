import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:capstone_app/data/ph_address_data.dart';
import 'package:capstone_app/screens/dayungquestion.dart'
    hide kPrimary, kBg, kAccent;
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/utils/input_safety.dart';
import 'package:capstone_app/utils/network_error_dialog.dart';
import 'package:cupertino_calendar_picker/cupertino_calendar_picker.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:capstone_app/Auth/login.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// palette
const Color kPrimaryLight = Color(0xFF3B82F6);
const Color kWarn = Color(0xFFF59E0B);
const Color kDanger = Color(0xFFEF4444);
const Color kNeutralText = Color(0xFF111827);
const Color kSubtleText = Color(0xFF6B7280);
const Color kCardBg = Color(0xFFFFFFFF);
const Color kBorderColor = Color(0xFFE5E7EB);
const Color kSuccess = Color(0xFF10B981);
const double kEdge = 16;

class Register extends StatefulWidget {
  const Register({super.key});

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  final fullNameController = TextEditingController();
  final emailController = TextEditingController();
  final sexController = TextEditingController();
  final mobileController = TextEditingController();
  final addressController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  String get password => passwordController.text.trim();
  String? _confirmPasswordError;
  String? selectedProvince;
  String? selectedCity;
  String? selectedBarangay;
  String? selectedMonth;
  String? selectedDay;
  String? selectedYear;
  String? selectedSex;
  String? _pickedRegion, _pickedProvince, _pickedCity, _pickedBarangay;

  String _normalizePhone(String raw) {
    final s = raw.replaceAll(RegExp(r'\D'), '');
    if (s.length == 10 && s.startsWith('9')) {
      return '+63$s';
    }
    throw Exception('Enter a valid 10-digit number starting with 9');
  }

  double? _latitude;
  double? _longitude;

  bool _obscurePassword = true;
  bool _isSubmitting = false;

  bool _looksOffline(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('failed to fetch') ||
        s.contains('failed host lookup') ||
        s.contains('network is unreachable') ||
        s.contains('socketexception') ||
        s.contains('handshake') ||
        s.contains('network') ||
        s.contains('socket') ||
        s.contains('timeout');
  }

  DateTime? _selectedDob;

  @override
  void initState() {
    super.initState();
    confirmPasswordController.addListener(_checkPasswordMatch);
    passwordController.addListener(_checkPasswordMatch);
  }

  void _checkPasswordMatch() {
    final password = passwordController.text;
    final confirm = confirmPasswordController.text;
    setState(() {
      if (confirm.isEmpty) {
        _confirmPasswordError = null;
      } else if (password != confirm) {
        _confirmPasswordError = 'Passwords do not match';
      } else {
        _confirmPasswordError = null;
      }
    });
  }

  List<String> get provinceList =>
      phProvinces.map((p) => p['name'] as String).toList();

  List<String> get cityList {
    if (selectedProvince == null) return [];
    // Cast the top-level list to List<Map<String, dynamic>>
    final provinces = phProvinces.cast<Map<String, dynamic>>();
    final province = provinces.firstWhere(
      (p) => p['name'] == selectedProvince,
      orElse: () => <String, dynamic>{}, // empty map if not found
    );
    final rawCities = province['cities'];
    if (rawCities is! List) return [];
    final cities = rawCities.cast<Map<String, dynamic>>();
    return cities
        .map((c) => c['name'])
        .where((name) => name is String && name.trim().isNotEmpty)
        .cast<String>()
        .toList();
  }

  List<String> get barangayList {
    if (selectedProvince == null || selectedCity == null) return [];
    final provinces = phProvinces.cast<Map<String, dynamic>>();
    final province = provinces.firstWhere(
      (p) => p['name'] == selectedProvince,
      orElse: () => <String, dynamic>{},
    );
    final rawCities = province['cities'];
    if (rawCities is! List) return [];
    final cities = rawCities.cast<Map<String, dynamic>>();
    final city = cities.firstWhere(
      (c) => c['name'] == selectedCity,
      orElse: () => <String, dynamic>{},
    );
    final rawBarangays = city['barangays'];
    if (rawBarangays is! List) return [];
    return rawBarangays
        .where(
          (b) =>
              b is String &&
              b.trim().isNotEmpty &&
              !RegExp(r'^[A-Z]$').hasMatch(b.trim()),
        )
        .cast<String>()
        .toList();
  }

  // ignore: unused_field
  final List<String> _months = const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    fullNameController.dispose();
    sexController.dispose();
    mobileController.dispose();
    addressController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    emailController.dispose();
    confirmPasswordController.removeListener(_checkPasswordMatch);
    passwordController.removeListener(_checkPasswordMatch);
    super.dispose();
  }

  void _showTopErrorDialog(BuildContext context, String message) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Error',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, a1, a2) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kDanger, kDanger.withValues(alpha: 0.9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: kDanger.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                    const BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                constraints: const BoxConstraints(maxWidth: 420),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.error_outline_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Dismiss',
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, a1, a2, child) => FadeTransition(
        opacity: a1,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, -0.4),
            end: Offset.zero,
          ).animate(a1),
          child: child,
        ),
      ),
    );
  }

  Future<void> _openAddressPicker() async {
    final result = await showModalBottomSheet<_AddressPickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => AddressPickerSheet(
        onUseMyLocation: () async {
          final navigator = Navigator.of(ctx);
          await _useMyLocation();
          if (!mounted) return;
          navigator.pop(_AddressPickResult(rawText: addressController.text));
        },
        initialRegion: _pickedRegion,
        initialProvince: _pickedProvince,
        initialCity: _pickedCity,
        initialBarangay: _pickedBarangay,
      ),
    );
    if (!mounted) return;

    if (result != null) {
      setState(() {
        addressController.text = result.rawText;
        _pickedRegion = result.region;
        _pickedProvince = result.province;
        _pickedCity = result.city;
        _pickedBarangay = result.barangay;
        _latitude = null;
        _longitude = null;
      });

      String? cleanBarangay = result.barangay
          ?.replaceAll(RegExp(r'\s*\(.*?\)'), '')
          .trim();
      String? cleanProvince = result.province?.trim();
      String? cleanCity = result.city?.trim();

      final List<String> addressVariants = [
        [
          if (cleanBarangay != null && cleanBarangay.isNotEmpty) cleanBarangay,
          if (cleanCity != null && cleanCity.isNotEmpty) cleanCity,
          if (cleanProvince != null && cleanProvince.isNotEmpty) cleanProvince,
          'Philippines',
        ].join(', '),
        [
          if (cleanCity != null && cleanCity.isNotEmpty) cleanCity,
          if (cleanProvince != null && cleanProvince.isNotEmpty) cleanProvince,
          'Philippines',
        ].join(', '),
      ];

      bool found = false;
      String triedAddresses = '';

      for (final addr in addressVariants) {
        triedAddresses += '$addr\n';
        try {
          final locations = await locationFromAddress(addr);
          if (locations.isNotEmpty) {
            setState(() {
              _latitude = locations.first.latitude;
              _longitude = locations.first.longitude;
            });
            found = true;
            break;
          }
        } catch (e) {
          if (_looksOffline(e)) {
            await NetworkMonitor().checkNow();
            return;
          }
        }
      }

      if (!found) {
        for (final addr in addressVariants) {
          triedAddresses += '[Nominatim] $addr\n';
          try {
            final nominatimResult = await _geocodeViaNominatim(addr);
            if (nominatimResult != null) {
              setState(() {
                _latitude = nominatimResult['lat'];
                _longitude = nominatimResult['lon'];
              });
              found = true;
              break;
            }
          } catch (e) {
            if (_looksOffline(e)) {
              await NetworkMonitor().checkNow();
              return;
            }
          }
        }
      }

      if (!found) {
        setState(() {
          _latitude = null;
          _longitude = null;
        });
        if (!mounted) return;
        _showTopErrorDialog(
          context,
          'Geocoding failed: Could not find any result for the supplied address or coordinates.\nAddresses tried:\n$triedAddresses',
        );
      }
    }
  }

  Future<void> _useMyLocation() async {
    try {
      final perm = await Geolocator.requestPermission();
      if (!mounted) return;
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _showTopErrorDialog(context, 'Location permission denied.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      String? composed;
      String? street;
      String? barangay;
      String? city;
      String? province;
      bool neededInternetLookup = false;

      if (kIsWeb) {
        neededInternetLookup = true;
        composed = await _reverseViaNominatim(pos.latitude, pos.longitude);
      } else {
        try {
          final placemarks = await placemarkFromCoordinates(
            pos.latitude,
            pos.longitude,
          );
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            street = (p.street ?? '').trim();
            barangay = (p.subLocality ?? '').trim();
            city = (p.locality ?? '').trim();
            province = (p.administrativeArea ?? '').trim();
            composed = [
              if (street.isNotEmpty) street,
              if (barangay.isNotEmpty) barangay,
              if (city.isNotEmpty) city,
              if (province.isNotEmpty) province,
            ].join(', ');
          }
        } catch (e) {
          if (_looksOffline(e)) {
            await NetworkMonitor().checkNow();
            return;
          }
        }

        final needsFallback =
            composed == null ||
            composed.isEmpty ||
            composed.contains('+') ||
            (barangay == null || barangay.isEmpty) ||
            (street == null || street.isEmpty);

        if (needsFallback) {
          neededInternetLookup = true;
          final nominatim = await _reverseViaNominatim(
            pos.latitude,
            pos.longitude,
          );
          if (nominatim != null && nominatim.isNotEmpty) {
            composed = nominatim;
          }
        }
      }

      if (!mounted) return;

      if (composed == null || composed.isEmpty) {
        if (neededInternetLookup) {
          await NetworkMonitor().checkNow();
          return;
        }

        _showTopErrorDialog(
          context,
          'Could not determine your address. Please try again.',
        );
        return;
      }

      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        addressController.text = composed!;
      });
    } catch (e) {
      if (_looksOffline(e)) {
        await NetworkMonitor().checkNow();
        return;
      }
      _showTopErrorDialog(context, 'Location error: $e');
    }
  }

  Future<String?> _reverseViaNominatim(double lat, double lng) async {
    final url =
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&zoom=18&addressdetails=1';
    final resp = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': 'capstone-app/1.0'},
    );

    if (resp.statusCode != 200) {
      throw Exception(
        'Reverse geocoding failed with status ${resp.statusCode}',
      );
    }

    final data = json.decode(resp.body);
    final a = (data['address'] ?? {}) as Map;

    final street = _firstNonEmpty([
      a['road'],
      a['residential'],
      a['pedestrian'],
      a['path'],
    ]);
    final block = _firstNonEmpty([a['block'], a['quarter']]);
    final purok = _firstNonEmpty([
      a['neighbourhood'],
      a['hamlet'],
      a['subdivision'],
    ]);
    final barangay = _firstNonEmpty([a['suburb'], a['barangay']]);
    final city = _firstNonEmpty([
      a['city'],
      a['municipality'],
      a['town'],
      a['village'],
    ]);
    final province = _firstNonEmpty([a['state'], a['province']]);

    final parts = [
      if (street != null) street,
      if (block != null) block,
      if (purok != null) purok,
      if (barangay != null) barangay,
      if (city != null) city,
      if (province != null) province,
    ];

    return parts.where((e) => e.trim().isNotEmpty).join(', ');
  }

  String? _firstNonEmpty(List values) {
    for (final v in values) {
      if (v != null) {
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    return null;
  }

  Future<void> _showCalendarDialog(BuildContext context) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 100, 1, 1);
    final lastDate = now;
    final initialDate = _selectedDob ?? DateTime(now.year - 18, 1, 1);

    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        DateTime temp = initialDate;
        final size = MediaQuery.of(ctx).size;

        return SafeArea(
          child: CupertinoTheme(
            data: const CupertinoThemeData(
              brightness: Brightness.light,
              primaryColor: Color(0xFF3B82F6),
            ),
            child: SizedBox(
              height: size.height * 0.50,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: kDanger,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'Select Date of Birth',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: kNeutralText,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, temp),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              color: kPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: CupertinoCalendar(
                        minimumDateTime: firstDate,
                        maximumDateTime: lastDate,
                        initialDateTime: temp,
                        currentDateTime: _selectedDob ?? DateTime.now(),
                        mode: CupertinoCalendarMode.date,
                        onDateTimeChanged: (d) => temp = d,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDob = picked);
    }
  }

  Future<void> _registerUser() async {
    if (!_formKey.currentState!.validate()) return;
    if (_confirmPasswordError != null) return;

    if (_latitude == null || _longitude == null) {
      _showTopErrorDialog(
        context,
        'Please select a valid address so we can get your location.',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final email = AppInputSecurity.sanitizeEmail(emailController.text);
    final password = passwordController.text.trim();
    const role = 'member';

    final fullName = AppInputSecurity.sanitizePlainText(
      fullNameController.text,
      maxLength: 120,
    );
    final address = AppInputSecurity.sanitizePlainText(
      addressController.text,
      maxLength: 200,
    );
    final rawPhone = AppInputSecurity.sanitizePhone(mobileController.text);
    String normalizedPhone;
    try {
      normalizedPhone = _normalizePhone(rawPhone);
    } catch (e) {
      setState(() => _isSubmitting = false);
      _showTopErrorDialog(context, e.toString());
      return;
    }

    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {'role': role},
      );

      final user = res.user;
      if (user == null) {
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        _showTopErrorDialog(context, 'Failed to register user.');
        return;
      }

      final dob = _selectedDob!.toIso8601String().split('T').first;

      await Supabase.instance.client.from('users').insert({
        'id': user.id,
        'full_name': fullName,
        'dob': dob,
        'sex': selectedSex,
        'mobile_number': rawPhone,
        'mobile_number_normalized': normalizedPhone,
        'latitude': _latitude,
        'longitude': _longitude,
        'address': address,
        'barangay': _pickedBarangay,
        'city': _pickedCity,
        'province': _pickedProvince,
        'role': role,
        'email': email,
      });

      final hashed = BCrypt.hashpw(password, BCrypt.gensalt());
      await Supabase.instance.client
          .from('users')
          .update({'password_hash': hashed})
          .eq('id', user.id);

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => QuestionnaireScreen(userId: user.id, role: role),
        ),
      );
    } on AuthException catch (e) {
      setState(() => _isSubmitting = false);

      final msg = e.message.toLowerCase();
      final isOffline =
          _looksOffline(e) ||
          msg.contains('network') ||
          msg.contains('fetch') ||
          msg.contains('socket') ||
          msg.contains('timeout');
      final isEmailTaken =
          msg.contains('already registered') ||
          msg.contains('already exists') ||
          msg.contains('email already') ||
          msg.contains('user already') ||
          msg.contains('duplicate');

      if (isOffline) {
        await NetworkMonitor().checkNow();
        return;
      }

      if (isEmailTaken) {
        _showTopErrorDialog(
          context,
          'This email is already registered. Please sign in or use a different email.',
        );
        return;
      }

      _showTopErrorDialog(context, 'Auth error: ${e.message}');
    } catch (e) {
      setState(() => _isSubmitting = false);

      if (_looksOffline(e)) {
        await NetworkMonitor().checkNow();
        return;
      }

      _showTopErrorDialog(context, 'Error: $e');
    }
  }

  Future<Map<String, double>?> _geocodeViaNominatim(String address) async {
    final url =
        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(address)}&countrycodes=ph&limit=1&addressdetails=1';

    final resp = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': 'capstone-app/1.0'},
    );

    if (resp.statusCode != 200) {
      throw Exception('Geocoding failed with status ${resp.statusCode}');
    }

    final data = json.decode(resp.body);
    if (data is List && data.isNotEmpty) {
      final lat = double.tryParse(data[0]['lat'] ?? '');
      final lon = double.tryParse(data[0]['lon'] ?? '');
      if (lat != null && lon != null) {
        return {'lat': lat, 'lon': lon};
      }
    }

    return null;
  }

  Widget _dobField(BuildContext rootContext) {
    final isWide = MediaQuery.of(context).size.width > 720;

    return GestureDetector(
      onTap: () => _showCalendarDialog(rootContext),
      child: AbsorbPointer(
        child: TextFormField(
          readOnly: true,
          style: TextStyle(
            fontSize: isWide ? 18 : 16,
            color: kNeutralText,
            fontWeight: FontWeight.w500,
          ),
          decoration: _dec(
            'Date of Birth',
            hint: 'YYYY-MM-DD',
            icon: Icons.calendar_today_rounded,
          ),
          controller: TextEditingController(
            text: _selectedDob == null
                ? ''
                : '${_selectedDob!.year}-${_selectedDob!.month.toString().padLeft(2, '0')}-${_selectedDob!.day.toString().padLeft(2, '0')}',
          ),
          validator: (v) =>
              _selectedDob == null ? 'Date of birth is required' : null,
        ),
      ),
    );
  }

  String _formatFullName(String input) {
    if (input.trim().isEmpty) return '';

    return input
        .split(RegExp(r'\s+'))
        .map((word) {
          if (word.isEmpty) return '';
          return '${word[0].toUpperCase()}${word.substring(1)}';
        })
        .join(' ');
  }

  InputDecoration _dec(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        color: kSubtleText,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: const TextStyle(color: kSubtleText, fontSize: 16),
      prefixIcon: icon != null
          ? Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: kPrimary, size: 20),
            )
          : null,
      filled: true,
      fillColor: kCardBg,
      contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kEdge),
        borderSide: const BorderSide(color: kBorderColor, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kEdge),
        borderSide: const BorderSide(color: kPrimary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kEdge),
        borderSide: const BorderSide(color: kDanger, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kEdge),
        borderSide: const BorderSide(color: kDanger, width: 2),
      ),
      errorStyle: const TextStyle(
        color: kDanger,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  InputDecoration _dropdownDec(String label) => _dec(label).copyWith(
    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 720;
    final isSmall = width < 350;

    return Scaffold(
      backgroundColor: kBg,
      resizeToAvoidBottomInset: true,
      body: Builder(
        builder: (rootContext) {
          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isSmall ? 16 : 24,
                  vertical: isSmall ? 12 : 20,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isWide ? 640 : 420),
                  child: Column(
                    children: [
                      // Header
                      Padding(
                        padding: EdgeInsets.only(bottom: isSmall ? 12 : 20),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: kPrimary.withValues(alpha: 0.1),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/images/dayunglogo.jpeg',
                                width: isWide ? 280 : (isSmall ? 120 : 220),
                                height: isWide ? 100 : (isSmall ? 40 : 80),
                                fit: BoxFit.contain,
                              ),
                            ),
                            SizedBox(height: isSmall ? 8 : 12),
                            AutoSizeText(
                              'Tabang sa Kalisud, Sa Isa ka Tap.',
                              maxLines: 1,
                              minFontSize: 10,
                              style: TextStyle(
                                fontSize: isWide ? 20 : (isSmall ? 12 : 16),
                                fontWeight: FontWeight.w600,
                                color: kSubtleText,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Card(
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        color: kCardBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(
                            color: kBorderColor.withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(isSmall ? 10 : 20),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                if (_isSubmitting)
                                  Container(
                                    margin: EdgeInsets.only(
                                      bottom: isSmall ? 8 : 16,
                                    ),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: kPrimary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: kPrimary,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Creating your account...',
                                          style: TextStyle(
                                            color: kPrimary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: kPrimary.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: kPrimary.withValues(alpha: 0.1),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: kPrimary,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.person_rounded,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Personal Information',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: kNeutralText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: fullNameController,
                                  textInputAction: TextInputAction.next,
                                  textCapitalization: TextCapitalization.words,
                                  inputFormatters: [
                                    ...AppInputSecurity.singleLineFormatters(
                                      maxLength: 120,
                                    ),
                                    TextInputFormatter.withFunction(
                                      (oldValue, newValue) {
                                        final formatted = _formatFullName(
                                          newValue.text,
                                        );
                                        return newValue.copyWith(
                                          text: formatted,
                                          selection: TextSelection.collapsed(
                                            offset: formatted.length,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                  style: TextStyle(
                                    fontSize: isWide ? 18 : 16,
                                    color: kNeutralText,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: _dec(
                                    'Full Name',
                                    hint: 'Juan Dela Cruz',
                                    icon: Icons.person_rounded,
                                  ),
                                  validator: (v) =>
                                      AppInputSecurity.validateSafeText(
                                        v,
                                        fieldName: 'Full Name',
                                        minLength: 2,
                                        maxLength: 120,
                                      ),
                                ),
                                const SizedBox(height: 16),
                                DropdownButtonFormField2<String>(
                                  isExpanded: true,
                                  decoration: _dropdownDec('Sex'),
                                  value: selectedSex,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: kText,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  items: ['Male', 'Female', 'Prefer not to say']
                                      .map(
                                        (sex) => DropdownMenuItem<String>(
                                          value: sex,
                                          child: Text(
                                            sex,

                                            style: const TextStyle(
                                              color: kNeutralText,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  selectedItemBuilder: (context) =>
                                      [
                                        'Male',
                                        'Female',
                                        'Prefer not to say',
                                      ].map((sex) {
                                        return Row(
                                          children: [
                                            if (sex == 'Male')
                                              Icon(
                                                Icons.male,
                                                color: Colors.blue[700],
                                              )
                                            else if (sex == 'Female')
                                              Icon(
                                                Icons.female,
                                                color: Colors.pink[400],
                                              )
                                            else
                                              const Icon(
                                                Icons.person_outline,
                                                color: kSubtleText,
                                              ),
                                            const SizedBox(width: 8),
                                            const SizedBox.shrink(),
                                            Text(
                                              sex,
                                              style: const TextStyle(
                                                color: kNeutralText,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                  onChanged: (value) =>
                                      setState(() => selectedSex = value),
                                  validator: (value) =>
                                      value == null ? 'Sex is required' : null,
                                ),
                                const SizedBox(height: 16),
                                _dobField(rootContext),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: mobileController,
                                  decoration: _dec(
                                    'Mobile Number',
                                    hint: '9123456789',
                                    icon: Icons.phone,
                                  ).copyWith(prefixText: '+63 '),
                                  keyboardType: TextInputType.number,
                                  maxLength: 10,
                                  inputFormatters:
                                      AppInputSecurity.phoneFormatters(
                                        maxLength: 10,
                                      ),
                                  validator: (value) {
                                    final err = AppInputSecurity.validatePhone(
                                      value,
                                    );
                                    if (err != null) return err;
                                    final v = AppInputSecurity.sanitizePhone(
                                      value ?? '',
                                    ).replaceAll('+', '');
                                    if (v.length != 10) {
                                      return 'Enter 10 digits (e.g., 9123456789)';
                                    }
                                    if (!RegExp(r'^9\d{9}$').hasMatch(v)) {
                                      return 'Must start with 9';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                GestureDetector(
                                  onTap: _openAddressPicker,
                                  child: AbsorbPointer(
                                    child: TextFormField(
                                      controller: addressController,
                                      readOnly: true,
                                      inputFormatters:
                                          AppInputSecurity.singleLineFormatters(
                                            maxLength: 200,
                                          ),
                                      decoration: _dec(
                                        'Address',
                                        hint:
                                            'Select Region, Province, City, Barangay',
                                        icon: Icons.location_on_rounded,
                                      ),
                                      validator: (v) =>
                                          AppInputSecurity.validateSafeText(
                                            v,
                                            fieldName: 'Address',
                                            minLength: 6,
                                            maxLength: 200,
                                          ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 28),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: kAccent.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: kAccent.withValues(alpha: 0.1),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: kAccent,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.lock_rounded,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Account Information',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: kNeutralText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  textCapitalization: TextCapitalization.none,
                                  textInputAction: TextInputAction.next,
                                  inputFormatters: [
                                    ...AppInputSecurity.singleLineFormatters(
                                      maxLength: 120,
                                    ),
                                    FilteringTextInputFormatter.deny(
                                      RegExp(r'[A-Z]'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    final lowered = value.toLowerCase();
                                    if (value != lowered) {
                                      emailController.value =
                                          emailController.value.copyWith(
                                            text: lowered,
                                            selection:
                                                TextSelection.collapsed(
                                                  offset: lowered.length,
                                                ),
                                          );
                                    }
                                  },
                                  style: TextStyle(
                                    fontSize: isWide ? 18 : 16,
                                    color: kNeutralText,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: _dec(
                                    'Email',
                                    hint: 'example@email.com',
                                    icon: Icons.email_rounded,
                                  ),
                                  validator: AppInputSecurity.validateEmail,
                                ),
                                const SizedBox(height: 16),

                                TextFormField(
                                  controller: passwordController,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.next,
                                  style: TextStyle(
                                    fontSize: isWide ? 18 : 16,
                                    color: kNeutralText,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration:
                                      _dec(
                                        'Create Password',
                                        hint: '********',
                                        icon: Icons.lock_rounded,
                                      ).copyWith(
                                        helperText:
                                            'At least 8 chars with upper, lower, number, and symbol',
                                        helperStyle: TextStyle(
                                          color: kSubtleText,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Password is required';
                                    }
                                    final value = v.trim();
                                    if (value.length < 8) {
                                      return 'Password must be at least 8 characters';
                                    }
                                    if (!RegExp(r'[A-Z]').hasMatch(value)) {
                                      return 'Password must include an uppercase letter';
                                    }
                                    if (!RegExp(r'[a-z]').hasMatch(value)) {
                                      return 'Password must include a lowercase letter';
                                    }
                                    if (!RegExp(r'\d').hasMatch(value)) {
                                      return 'Password must include a number';
                                    }
                                    if (!RegExp(
                                      r'[^A-Za-z0-9]',
                                    ).hasMatch(value)) {
                                      return 'Password must include a special character';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                // Confirm Password
                                TextFormField(
                                  controller: confirmPasswordController,
                                  obscureText:
                                      _obscurePassword, // Use the same variable!
                                  textInputAction: TextInputAction.done,
                                  style: TextStyle(
                                    fontSize: isWide ? 18 : 16,
                                    color: kNeutralText,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration:
                                      _dec(
                                        'Confirm Password',
                                        hint: '********',
                                        icon: Icons.lock_person_rounded,
                                      ).copyWith(
                                        errorText: _confirmPasswordError,
                                        // No suffixIcon here!
                                      ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Confirm your password';
                                    }
                                    if (v != passwordController.text) {
                                      return 'Passwords do not match';
                                    }
                                    return null;
                                  },
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                      color: kSubtleText,
                                    ),
                                    label: Text(
                                      _obscurePassword
                                          ? 'Show password'
                                          : 'Hide password',
                                      style: TextStyle(
                                        color: kSubtleText,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: kSubtleText,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 0,
                                      ),
                                      minimumSize: Size(0, 36),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 15),
                                Container(
                                  width: double.infinity,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [kPrimary, kPrimaryLight],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(kEdge),
                                    boxShadow: [
                                      BoxShadow(
                                        color: kPrimary.withValues(alpha: 0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: _isSubmitting
                                        ? null
                                        : _registerUser,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          kEdge,
                                        ),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: _isSubmitting
                                        ? const SizedBox(
                                            width: 26,
                                            height: 26,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 3,
                                            ),
                                          )
                                        : const Text(
                                            'Create Account',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  width: double.infinity,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(kEdge),
                                    border: Border.all(
                                      color: kBorderColor,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: OutlinedButton(
                                    onPressed: _isSubmitting
                                        ? null
                                        : () => Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => const Login(),
                                            ),
                                          ),
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          kEdge,
                                        ),
                                      ),
                                      side: BorderSide.none,
                                      foregroundColor: kPrimary,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.arrow_back_rounded,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            'Already have an account? Login',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: kSuccess.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: kSuccess.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.security_rounded,
                              color: kSuccess,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Your information is kept private and secure.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: kSuccess,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AddressPickResult {
  final String rawText;
  final String? region, province, city, barangay;
  _AddressPickResult({
    required this.rawText,
    this.region,
    this.province,
    this.city,
    this.barangay,
  });
}

class AddressPickerSheet extends StatefulWidget {
  final Future<void> Function() onUseMyLocation;
  final String? initialRegion, initialProvince, initialCity, initialBarangay;

  const AddressPickerSheet({
    super.key,
    required this.onUseMyLocation,
    this.initialRegion,
    this.initialProvince,
    this.initialCity,
    this.initialBarangay,
  });

  @override
  State<AddressPickerSheet> createState() => _AddressPickerSheetState();
}

class _AddressPickerSheetState extends State<AddressPickerSheet> {
  // State
  String? _region;
  String? _province;
  String? _city;
  String? _barangay;
  String _barangaySearch = '';
  bool _locating = false;

  int get _stepIndex {
    if (_region == null) return 0;
    if (_province == null) return 1;
    if (_city == null) return 2;
    return 3;
  }

  @override
  void initState() {
    super.initState();
    _region = widget.initialRegion;
    _province = widget.initialProvince;
    _city = widget.initialCity;
    _barangay = widget.initialBarangay;
  }

  void _goBackOneStep() {
    setState(() {
      if (_stepIndex == 1) {
        // Province -> Region
        _region = null;
        _province = null;
        _city = null;
        _barangay = null;
      } else if (_stepIndex == 2) {
        // City -> Province
        _province = null;
        _city = null;
        _barangay = null;
      } else if (_stepIndex == 3) {
        // Barangay -> City
        _city = null;
        _barangay = null;
      }
    });
  }

  List<Map<String, dynamic>> get _mindanaoProvinces {
    return phProvinces.cast<Map<String, dynamic>>();
  }

  List<Map<String, dynamic>> get _citiesInProvince {
    if (_province == null) return const [];
    final province = _mindanaoProvinces.firstWhere(
      (p) => p['name'] == _province,
      orElse: () => <String, dynamic>{},
    );
    final rawCities = province['cities'];
    if (rawCities is! List) return const [];
    return rawCities.cast<Map<String, dynamic>>();
  }

  List<String> get _barangaysInCity {
    if (_city == null) return const [];
    final city = _citiesInProvince.firstWhere(
      (c) => c['name'] == _city,
      orElse: () => <String, dynamic>{},
    );
    final rawBarangays = city['barangays'];
    if (rawBarangays is! List) return const [];
    return rawBarangays
        .where(
          (b) =>
              b is String &&
              b.trim().isNotEmpty &&
              !RegExp(r'^[A-Z]$').hasMatch(b.trim()),
        )
        .cast<String>()
        .toList();
  }

  String _composeAddress() {
    return [
      if (_barangay?.isNotEmpty == true) _barangay,
      if (_city?.isNotEmpty == true) _city,
      if (_province?.isNotEmpty == true) _province,
      if (_region?.isNotEmpty == true) _region,
    ].map((e) => e.toString()).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return SafeArea(
      child: SizedBox(
        height: size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text(
                    'Region Selected',
                    style: TextStyle(color: kSubtleText),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _region = null;
                      _province = null;
                      _city = null;
                      _barangay = null;
                    }),
                    child: const Text(
                      'Reset',
                      style: TextStyle(
                        color: kDanger,
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _VerticalTrail(
                region: _region,
                province: _province,
                city: _city,
                barangay: _barangay,
                activeStep: _stepIndex,
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (_stepIndex == 0) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: _locating
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Icon(Icons.my_location_rounded),
                            label: Text(
                              _locating
                                  ? 'Locating...'
                                  : 'Use My Current Location',
                            ),
                            onPressed: _locating
                                ? null
                                : () async {
                                    setState(() => _locating = true);
                                    await widget.onUseMyLocation();
                                    if (mounted) {
                                      setState(() => _locating = false);
                                    }
                                  },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Region',
                          style: TextStyle(color: kSubtleText),
                        ),
                      ),
                      ListTile(
                        title: const Text('Mindanao'),
                        onTap: () => setState(() {
                          _region = 'Mindanao';
                          _province = null;
                          _city = null;
                          _barangay = null;
                        }),
                      ),
                    ],

                    // Step 1: Province
                    if (_stepIndex == 1) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          'Province',
                          style: TextStyle(color: kSubtleText),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _goBackOneStep,
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 14,
                          color: kSubtleText,
                        ),
                        label: const Text(
                          'Back',
                          style: TextStyle(color: kSubtleText),
                        ),
                      ),
                      ..._mindanaoProvinces.map((p) {
                        final name = (p['name'] ?? '').toString();
                        return ListTile(
                          title: Text(name),
                          onTap: () => setState(() {
                            _province = name;
                            _city = null;
                            _barangay = null;
                          }),
                        );
                      }),
                    ],

                    // Step 2: City/Municipality
                    if (_stepIndex == 2) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          'City/Municipality',
                          style: TextStyle(color: kSubtleText),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _goBackOneStep,
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 14,
                          color: kSubtleText,
                        ),
                        label: const Text(
                          'Back',
                          style: TextStyle(color: kSubtleText),
                        ),
                      ),
                      ...(() {
                        final cityNames = _citiesInProvince
                            .map((c) => (c['name'] ?? '').toString().trim())
                            .where((name) => name.isNotEmpty)
                            .toList();

                        cityNames.sort(
                          (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                        );

                        final Map<String, List<String>> grouped = {};
                        for (final name in cityNames) {
                          final letter = name.substring(0, 1).toUpperCase();
                          grouped.putIfAbsent(letter, () => []).add(name);
                        }

                        return grouped.entries.map((entry) {
                          final letter = entry.key;
                          final items = entry.value;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                child: Text(
                                  letter,
                                  style: const TextStyle(
                                    color: kSubtleText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              ...items.map((name) {
                                return ListTile(
                                  title: Text(name),
                                  onTap: () => setState(() {
                                    _city = name;
                                    _barangay = null;
                                  }),
                                );
                              }),
                            ],
                          );
                        }).toList();
                      })(),
                    ],
                    if (_stepIndex == 3) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          'Barangay',
                          style: TextStyle(color: kSubtleText),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _goBackOneStep,
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 14,
                          color: kSubtleText,
                        ),
                        label: const Text(
                          'Back',
                          style: TextStyle(color: kSubtleText),
                        ),
                      ),

                      // Inside the barangay step in your AddressPickerSheet build method:
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Search barangay...',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              vertical: 0,
                              horizontal: 12,
                            ),
                          ),
                          onChanged: (val) =>
                              setState(() => _barangaySearch = val),
                        ),
                      ),
                      // Filtered barangay list:
                      ...(() {
                        final names = _barangaysInCity
                            .where(
                              (b) => b.toLowerCase().contains(
                                _barangaySearch.toLowerCase(),
                              ),
                            )
                            .toList();
                        names.sort(
                          (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                        );
                        return [
                          RadioGroup<String>(
                            groupValue: _barangay,
                            onChanged: (val) {
                              if (val == null) return;
                              setState(() => _barangay = val);
                              Navigator.pop(
                                context,
                                _AddressPickResult(
                                  rawText: _composeAddress(),
                                  region: _region,
                                  province: _province,
                                  city: _city,
                                  barangay: val,
                                ),
                              );
                            },
                            child: Column(
                              children: names.map((name) {
                                return RadioListTile<String>(
                                  value: name,
                                  title: Text(name),
                                  activeColor: kPrimary,
                                );
                              }).toList(),
                            ),
                          ),
                        ];
                      })(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerticalTrail extends StatelessWidget {
  final String? region;
  final String? province;
  final String? city;
  final String? barangay;
  final int activeStep;
  const _VerticalTrail({
    required this.region,
    required this.province,
    required this.city,
    required this.barangay,
    required this.activeStep,
  });

  Widget _line({
    required String label,
    required bool highlight,
    bool showConnector = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: highlight ? kPrimary : kBorderColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: highlight ? kNeutralText : kSubtleText,
                  fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        if (showConnector)
          Container(
            width: 1.5,
            height: 18,
            margin: const EdgeInsets.only(left: 3.5, top: 6, bottom: 6),
            color: kBorderColor,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = region ?? 'Region';
    final p = province ?? 'Province';
    final c = city ?? 'City/Municipality';
    final b = barangay ?? 'Barangay';

    // Map active step to highlighted line
    final highlightRegion = activeStep == 0;
    final highlightProvince = activeStep == 1;
    final highlightCity = activeStep == 2;
    final highlightBarangay = activeStep == 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line(label: r, highlight: highlightRegion),
        _line(label: p, highlight: highlightProvince),
        _line(label: c, highlight: highlightCity),
        _line(label: b, highlight: highlightBarangay, showConnector: false),
      ],
    );
  }
}
