import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:io';
import 'package:flutter/foundation.dart'; 
import 'package:capstone_app/data/ph_address_data.dart';
import 'package:capstone_app/utils/input_safety.dart';
import 'package:capstone_app/utils/supabase_storage.dart';



const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);
const double kRadius = 18;

class SubmitClaimForm extends StatefulWidget {
  final int? dayungUnitId;
  final bool requireMembership;
  const SubmitClaimForm({
    super.key,
    this.dayungUnitId,
    this.requireMembership = false,
  });
  @override
  State<SubmitClaimForm> createState() => _SubmitClaimFormState();
}

class _SubmitClaimFormState extends State<SubmitClaimForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  String? _vigilAddress;
  String? _vigilBarangay;
  bool _submitting = false;
  bool _locating = false;
  File? _deathCertFile;
  Uint8List? _deathCertBytes;
  String? _deathCertOrigName;
  double? _vigilLat;
  double? _vigilLng;
  String? _pickedVigilRegion;
  String? _pickedVigilProvince;
  String? _pickedVigilCity;
  String? _pickedVigilBarangay;
  // ADD: valid ID state
  File? _validIdFile;
  Uint8List? _validIdBytes;
  String? _validIdOrigName;
  String? _selectedDeceasedType; // 'member' or 'beneficiary'
  int? _selectedBeneficiaryId;
  DateTime? _dateOfDeath;
  List<Map<String, dynamic>> _beneficiaries = [];
  String? _firstNonEmpty(List values) {
    for (final v in values) {
      if (v != null) {
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _title.text = 'Claim for Deceased Member';
    _fetchBeneficiaries();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<String?> _reverseViaNominatim(double lat, double lng) async {
    try {
      final url =
          'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&zoom=18&addressdetails=1';
      final resp = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'capstone-app/1.0'},
      );
      if (resp.statusCode != 200) return null;
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
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchBeneficiaries() async {
    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;
    if (user == null) return;
    final res = await sb
        .from('beneficiaries')
        .select('id, full_name')
        .eq('user_id', user.id)
        .eq('eligible_to_claim', true)
        .eq('status', 'Approved');
    setState(() {
      _beneficiaries = List<Map<String, dynamic>>.from(res);
    });
  }

  Future<void> _pickDeathCert() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true, // ensure bytes on web
    );
    if (result == null) return;
    final picked = result.files.single;
    setState(() {
      _deathCertOrigName = picked.name;
      if (kIsWeb) {
        _deathCertBytes = picked.bytes;
        _deathCertFile = null;
      } else {
        if (picked.path != null) {
          _deathCertFile = File(picked.path!);
          _deathCertBytes = _deathCertFile!.readAsBytesSync();
        }
      }
    });
  }

  // ADD: pick valid ID (same allowed extensions)
  Future<void> _pickValidId() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null) return;
    final picked = result.files.single;
    setState(() {
      _validIdOrigName = picked.name;
      if (kIsWeb) {
        _validIdBytes = picked.bytes;
        _validIdFile = null;
      } else {
        if (picked.path != null) {
          _validIdFile = File(picked.path!);
          _validIdBytes = _validIdFile!.readAsBytesSync();
        }
      }
    });
  }

  Future<Map<String, double>?> _geocodeVigilAddress(
    String? barangay,
    String? city,
    String? province,
  ) async {
    final cleanBarangay = barangay
        ?.replaceAll(RegExp(r'\s*\(.*?\)'), '')
        .trim();
    final cleanCity = city?.trim();
    final cleanProvince = province?.trim();

    final addressVariants = [
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

    for (final address in addressVariants) {
      if (address.trim().isEmpty) continue;
      try {
        final locations = await locationFromAddress(address);
        if (locations.isNotEmpty) {
          return {
            'lat': locations.first.latitude,
            'lng': locations.first.longitude,
          };
        }
      } catch (_) {}
    }

    for (final address in addressVariants) {
      if (address.trim().isEmpty) continue;
      try {
        final url =
            'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(address)}&countrycodes=ph&limit=1&addressdetails=1';
        final resp = await http.get(
          Uri.parse(url),
          headers: {'User-Agent': 'capstone-app/1.0'},
        );
        if (resp.statusCode != 200) continue;

        final data = json.decode(resp.body);
        if (data is List && data.isNotEmpty) {
          final lat = double.tryParse(data[0]['lat']?.toString() ?? '');
          final lng = double.tryParse(data[0]['lon']?.toString() ?? '');
          if (lat != null && lng != null) {
            return {'lat': lat, 'lng': lng};
          }
        }
      } catch (_) {}
    }

    return null;
  }

  Future<void> _openVigilLocationPicker() async {
    final result = await showModalBottomSheet<_ClaimAddressPickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ClaimAddressPickerSheet(
        onUseMyLocation: () async {
          await _pickVigilLocation();
          if (!ctx.mounted) return;
          Navigator.pop(
            ctx,
            _ClaimAddressPickResult(
              rawText: _vigilAddress ?? '',
              region: _pickedVigilRegion,
              province: _pickedVigilProvince,
              city: _pickedVigilCity,
              barangay: _pickedVigilBarangay,
            ),
          );
        },
        initialRegion: _pickedVigilRegion,
        initialProvince: _pickedVigilProvince,
        initialCity: _pickedVigilCity,
        initialBarangay: _pickedVigilBarangay,
      ),
    );

    if (!mounted) return;
    if (result == null || result.rawText.trim().isEmpty) return;

    final geocoded = await _geocodeVigilAddress(
      result.barangay,
      result.city,
      result.province,
    );

    if (!mounted) return;

    setState(() {
      _vigilAddress = result.rawText;
      _vigilBarangay = result.barangay ?? result.city;
      _pickedVigilRegion = result.region;
      _pickedVigilProvince = result.province;
      _pickedVigilCity = result.city;
      _pickedVigilBarangay = result.barangay;
      _vigilLat = geocoded?['lat'];
      _vigilLng = geocoded?['lng'];
    });

    if (geocoded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Address saved, but exact coordinates could not be determined.',
          ),
        ),
      );
    }
  }

  Future<void> _pickVigilLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied.')),
        );
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

      if (kIsWeb) {
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
        } catch (_) {}

        final needsFallback =
            composed == null ||
            composed.isEmpty ||
            composed.contains('+') ||
            (barangay == null || barangay.isEmpty) ||
            (street == null || street.isEmpty);

        if (needsFallback) {
          final nominatim = await _reverseViaNominatim(
            pos.latitude,
            pos.longitude,
          );
          if (nominatim != null && nominatim.isNotEmpty) composed = nominatim;
        }
      }

      if (!mounted) return;
      setState(() {
        _vigilLat = pos.latitude;
        _vigilLng = pos.longitude;
        _vigilAddress = composed ?? '(${pos.latitude}, ${pos.longitude})';
        _vigilBarangay = barangay?.isNotEmpty == true ? barangay : city;
        _pickedVigilRegion = 'Mindanao';
        _pickedVigilProvince = province?.isNotEmpty == true ? province : null;
        _pickedVigilCity = city?.isNotEmpty == true ? city : null;
        _pickedVigilBarangay = barangay?.isNotEmpty == true
            ? barangay
            : _vigilBarangay;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to get location: $e')));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<String?> _uploadDeathCert(String claimId) async {
    // Use bytes (web safe)
    final bytes = _deathCertBytes;
    if (bytes == null) return null;

    final storage = Supabase.instance.client.storage;
    const bucket = 'death_certificates';

    final nameSource =
        _deathCertOrigName ??
        (_deathCertFile != null
            ? _deathCertFile!.path.split('/').last
            : 'file');
    final ext = nameSource.split('.').last.toLowerCase();
    final mime =
        {
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'png': 'image/png',
          'pdf': 'application/pdf',
        }[ext] ??
        'application/octet-stream';

    final fileName =
        'claims/$claimId/death_cert_${DateTime.now().millisecondsSinceEpoch}.$ext';

    try {
      debugPrint(
        '[UPLOAD] bucket=$bucket fileName=$fileName size=${bytes.length} mime=$mime',
      );

      final storedPath = await storage
          .from(bucket)
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );

      debugPrint('[UPLOAD] stored path: $storedPath');

      return buildStorageRef(bucket, fileName);
    } on StorageException catch (e, st) {
      debugPrint('[UPLOAD][StorageException] ${e.message}\n$st');
      rethrow;
    } catch (e, st) {
      debugPrint('[UPLOAD][GenericError] $e\n$st');
      rethrow;
    }
  }

  // ADD: upload valid ID

  Future<String?> _uploadValidId(String claimId) async {
    final bytes = _validIdBytes;
    if (bytes == null) return null;

    final storage = Supabase.instance.client.storage;
    const bucket = 'valid_ids';

    final nameSource =
        _validIdOrigName ??
        (_validIdFile != null ? _validIdFile!.path.split('/').last : 'file');
    final ext = nameSource.split('.').last.toLowerCase();
    final mime =
        {
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'png': 'image/png',
          'pdf': 'application/pdf',
        }[ext] ??
        'application/octet-stream';

    final fileName =
        'claims/$claimId/valid_id_${DateTime.now().millisecondsSinceEpoch}.$ext';

    try {
      final storedPath = await storage
          .from(bucket)
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
      return buildStorageRef(bucket, fileName);
    } on StorageException catch (e, st) {
      debugPrint('[VALID_ID][StorageException] ${e.message}\n$st');
      rethrow;
    } catch (e, st) {
      debugPrint('[VALID_ID][GenericError] $e\n$st');
      rethrow;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;
    if (user == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Not logged in.')));
      return;
    }
    if (_selectedDeceasedType == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please select who passed away.')),
      );
      return;
    }
    if (_dateOfDeath == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please select date of death.')),
      );
      return;
    }

    // Always re-read the currently selected unit from SharedPreferences
    int? unitFromPrefs;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('selectedDayungUnit');
      if (raw != null) {
        final map = Map<String, dynamic>.from(jsonDecode(raw));
        unitFromPrefs = map['id'] is int
            ? map['id'] as int
            : int.tryParse('${map['id']}');
      }
    } catch (_) {}

    // Prefer the latest from prefs, fallback to the passed-in value
    final int? effectiveUnitId = unitFromPrefs ?? widget.dayungUnitId;

    if (effectiveUnitId == null) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('No Dayung selected.')),
      );
      return;
    }

    final apps = await sb
        .from('applications')
        .select('id')
        .eq('user_id', user.id)
        .eq('dayung_unit_id', effectiveUnitId)
        .eq('status', 'approved')
        .limit(1);
    if (!mounted) return;
    if ((apps as List).isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('You are not a member of this Dayung.')),
      );
      return;
    }

    if (widget.requireMembership) {
      final apps = await sb
          .from('applications')
          .select('id')
          .eq('user_id', user.id)
          .eq('dayung_unit_id', effectiveUnitId)
          .eq('status', 'approved')
          .limit(1);
      if (!mounted) return;
      if ((apps as List).isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('You are not a member of this Dayung.')),
        );
        return;
      }
    }

    String fmtDate(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    // --- Fetch deceased dob and age ---
    String? deceasedDob;
    int? deceasedAge;
    try {
      if (_selectedDeceasedType == 'member') {
        // Fetch member's dob from users table
        final userRow = await sb.from('users').select('dob').eq('id', user.id).maybeSingle();
        if (userRow != null && userRow['dob'] != null) {
          deceasedDob = userRow['dob'];
        }
      } else if (_selectedDeceasedType != null && _selectedDeceasedType!.startsWith('beneficiary_')) {
        // Fetch beneficiary's dob
        if (_selectedBeneficiaryId != null) {
          final ben = await sb.from('beneficiaries').select('dob').eq('id', _selectedBeneficiaryId as Object).maybeSingle();
          if (ben != null && ben['dob'] != null) {
            deceasedDob = ben['dob'];
          }
        }
      }
      // Calculate age if dob and date of death are available
      if (deceasedDob != null && _dateOfDeath != null) {
        final dobDate = DateTime.tryParse(deceasedDob);
        if (dobDate != null) {
          deceasedAge = _dateOfDeath!.year - dobDate.year - ((_dateOfDeath!.month < dobDate.month || (_dateOfDeath!.month == dobDate.month && _dateOfDeath!.day < dobDate.day)) ? 1 : 0);
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch deceased dob/age: $e');
    }

    setState(() => _submitting = true);
    try {
      final claimData = {
        'user_id': user.id,
        'title': AppInputSecurity.sanitizePlainText(
          _title.text,
          maxLength: 120,
        ),
        'description': AppInputSecurity.sanitizePlainText(
          _desc.text,
          allowNewLines: true,
          maxLength: 500,
        ),
        'status': 'Pending',
        if (_selectedBeneficiaryId != null)
          'beneficiary_id': _selectedBeneficiaryId,
        'deceased_type': _selectedDeceasedType?.startsWith('beneficiary_') == true ? 'beneficiary' : 'member',
        'date_of_death': fmtDate(_dateOfDeath!),
        'dayung_unit_id': effectiveUnitId,
        'vigil_latitude': _vigilLat,
        'vigil_longitude': _vigilLng,
        'vigil_address': _vigilAddress == null
            ? null
            : AppInputSecurity.sanitizePlainText(
                _vigilAddress!,
                maxLength: 200,
              ),
        'vigil_barangay': _vigilBarangay == null
            ? null
            : AppInputSecurity.sanitizePlainText(
                _vigilBarangay!,
                maxLength: 120,
              ),
        if (deceasedDob != null) 'dob': deceasedDob,
        if (deceasedAge != null) 'deceased_age': deceasedAge,
      };

      final insertRes = await sb
          .from('claims')
          .insert(claimData)
          .select()
          .maybeSingle();
      final claimId = insertRes!['id'].toString();

      Map<String, dynamic> updateFields = {};

      if (_deathCertBytes != null) {
        try {
          final fileUrl = await _uploadDeathCert(claimId);
          if (fileUrl != null) {
            updateFields['death_certificate_url'] = fileUrl;
          }
        } catch (e) {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(content: Text('Certificate upload failed: $e')),
          );
        }
      }

      // ADD: valid ID upload
      if (_validIdBytes != null) {
        try {
          final validUrl = await _uploadValidId(claimId);
          if (validUrl != null) {
            updateFields['valid_ids_url'] = validUrl;
          }
        } catch (e) {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(content: Text('Valid ID upload failed: $e')),
          );
        }
      }

      if (updateFields.isNotEmpty) {
        await sb.from('claims').update(updateFields).eq('id', claimId);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
  
    } catch (e, st) {
      debugPrint('CLAIM SUBMIT ERROR: $e\n$st');
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Submit failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildModernField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    int minLines = 1,
    bool readOnly = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextFormField(
        controller: controller,
        inputFormatters: inputFormatters,
        maxLines: maxLines,
        minLines: minLines,
        textInputAction: TextInputAction.next,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: kPrimaryDark, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          labelStyle: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildModernDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonFormField<String>(
        initialValue: _selectedDeceasedType,
        items: [
          const DropdownMenuItem(value: 'member', child: Text('This Member')),
          if (_beneficiaries.isNotEmpty)
            ..._beneficiaries.map(
              (b) => DropdownMenuItem(
                value: 'beneficiary_${b['id']}',
                child: Text(b['full_name']),
              ),
            ),
        ],
        onChanged: (v) {
          setState(() {
            _selectedDeceasedType = v;
            if (v != null && v.startsWith('beneficiary_')) {
              _selectedBeneficiaryId = int.tryParse(v.split('_').last);
            } else {
              _selectedBeneficiaryId = null;
            }
          });
        },
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          labelText: 'Who passed away?',
        ),
        validator: (v) {
          if (v == null || v.isEmpty) {
            return 'Please select who passed away';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildModernDateField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: _submitting
            ? null
            : () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                );
                if (!mounted) return;
                if (picked != null) {
                  setState(() => _dateOfDeath = picked);
                }
              },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.calendar_today_rounded, color: kPrimaryDark, size: 20),
              const SizedBox(width: 12),
              Text(
                _dateOfDeath == null
                    ? 'Select date of death'
                    : '${_dateOfDeath!.year}-${_dateOfDeath!.month.toString().padLeft(2, '0')}-${_dateOfDeath!.day.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 14,
                  color: _dateOfDeath == null
                      ? Colors.grey.shade600
                      : kNeutralText,
                ),
              ),
              const Spacer(),
              Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernFileUpload() {
    Widget? previewWidget;
    if (_deathCertBytes != null && _deathCertOrigName != null) {
      final ext = _deathCertOrigName!.split('.').last.toLowerCase();
      if (["jpg", "jpeg", "png"].contains(ext)) {
        previewWidget = GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => Dialog(
                child: InteractiveViewer(
                  child: Image.memory(_deathCertBytes!),
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _deathCertBytes!,
                height: 80,
                width: 80,
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      } else if (ext == "pdf") {
        previewWidget = GestureDetector(
          onTap: () async {
            // Optionally, implement PDF viewing using a package like flutter_pdfview
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('PDF Preview'),
                content: const Text('PDF preview not supported in this dialog. Please ensure you selected the correct file.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.picture_as_pdf, color: Colors.red, size: 32),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _deathCertOrigName!,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _submitting ? null : _pickDeathCert,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Icon(Icons.attach_file_rounded, color: kPrimaryDark, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _deathCertOrigName == null
                          ? 'Attach death certificate'
                          : _deathCertOrigName!,
                      style: TextStyle(
                        fontSize: 14,
                        color: _deathCertOrigName == null
                            ? Colors.grey.shade600
                            : kNeutralText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_deathCertOrigName != null)
                    IconButton(
                      onPressed: () => setState(() {
                        _deathCertFile = null;
                        _deathCertBytes = null;
                        _deathCertOrigName = null;
                      }),
                      icon: Icon(
                        Icons.close,
                        color: Colors.grey.shade600,
                        size: 18,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (previewWidget != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: previewWidget,
            ),
        ],
      ),
    );
  }

  // ADD: valid ID upload widget
  Widget _buildValidIdUpload() {
    Widget? previewWidget;
    if (_validIdBytes != null && _validIdOrigName != null) {
      final ext = _validIdOrigName!.split('.').last.toLowerCase();
      if (["jpg", "jpeg", "png"].contains(ext)) {
        previewWidget = GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => Dialog(
                child: InteractiveViewer(
                  child: Image.memory(_validIdBytes!),
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _validIdBytes!,
                height: 80,
                width: 80,
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      } else if (ext == "pdf") {
        previewWidget = GestureDetector(
          onTap: () async {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('PDF Preview'),
                content: const Text('PDF preview not supported in this dialog. Please ensure you selected the correct file.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.picture_as_pdf, color: Colors.red, size: 32),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _validIdOrigName!,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _submitting ? null : _pickValidId,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Icon(Icons.perm_identity, color: kPrimaryDark, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _validIdOrigName == null
                          ? 'Attach Valid ID of the claimant'
                          : _validIdOrigName!,
                      style: TextStyle(
                        fontSize: 14,
                        color: _validIdOrigName == null
                            ? Colors.grey.shade600
                            : kNeutralText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_validIdOrigName != null)
                    IconButton(
                      onPressed: () => setState(() {
                        _validIdFile = null;
                        _validIdBytes = null;
                        _validIdOrigName = null;
                      }),
                      icon: Icon(
                        Icons.close,
                        color: Colors.grey.shade600,
                        size: 18,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (previewWidget != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: previewWidget,
            ),
        ],
      ),
    );
  }

  Widget _buildModernVigilLocation() {
    final disabled = _submitting || _locating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Vigil location',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: InkWell(
            onTap: disabled ? null : _openVigilLocationPicker,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    color: _locating ? Colors.orange : kPrimaryDark,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _locating
                          ? 'Setting location...'
                          : (_vigilAddress == null
                                ? 'Set Vigil Location'
                                : 'Barangay: ${_vigilBarangay ?? '-'}\n$_vigilAddress'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: _locating
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: _locating
                            ? Colors.orange
                            : (_vigilAddress == null
                                  ? Colors.grey.shade600
                                  : kNeutralText),
                      ),
                    ),
                  ),
                  if (_locating)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.orange,
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.grey.shade600,
                      size: 16,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModernSubmitButton() {
    return Container(
      width: double.infinity,
      height: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: kPrimaryDark.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _submitting ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _submitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Submit Claim',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Montserrat',
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Modern Header with gradient
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'New Claim',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Montserrat',
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Form Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    _buildModernField(
                      controller: _title,
                      label: 'Title',
                      icon: Icons.title_rounded,
                      inputFormatters: AppInputSecurity.singleLineFormatters(
                        maxLength: 120,
                      ),
                      validator: (v) {
                        return AppInputSecurity.validateSafeText(
                          v,
                          fieldName: 'Title',
                          minLength: 4,
                          maxLength: 120,
                        );
                      },
                      readOnly: true,
                    ),
                    const SizedBox(height: 16),

                    // Description
                    _buildModernField(
                      controller: _desc,
                      label: 'Description (optional)',
                      icon: Icons.notes_rounded,
                      inputFormatters: AppInputSecurity.multiLineFormatters(
                        maxLength: 500,
                      ),
                      validator: (v) => AppInputSecurity.validateSafeText(
                        v,
                        fieldName: 'Description',
                        required: false,
                        maxLength: 500,
                        allowNewLines: true,
                      ),
                      maxLines: 3,
                      minLines: 2,
                    ),
                    const SizedBox(height: 16),

                    // Who passed away?
                    _buildModernDropdown(),
                    const SizedBox(height: 16),

                    // Date of Death
                    _buildModernDateField(),
                    const SizedBox(height: 16),

                    // Death Certificate
                    _buildModernFileUpload(),
                    const SizedBox(height: 16),

                    // ADD: Valid ID
                    _buildValidIdUpload(),
                    const SizedBox(height: 16),

                    // Vigil Location
                    _buildModernVigilLocation(),
                    const SizedBox(height: 20),

                    // Submit Button
                    _buildModernSubmitButton(),
                    const SizedBox(height: 14),

                    // Cancel
                    TextButton.icon(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClaimAddressPickResult {
  final String rawText;
  final String? region;
  final String? province;
  final String? city;
  final String? barangay;

  const _ClaimAddressPickResult({
    required this.rawText,
    this.region,
    this.province,
    this.city,
    this.barangay,
  });
}

class _ClaimAddressPickerSheet extends StatefulWidget {
  final Future<void> Function() onUseMyLocation;
  final String? initialRegion;
  final String? initialProvince;
  final String? initialCity;
  final String? initialBarangay;

  const _ClaimAddressPickerSheet({
    required this.onUseMyLocation,
    this.initialRegion,
    this.initialProvince,
    this.initialCity,
    this.initialBarangay,
  });

  @override
  State<_ClaimAddressPickerSheet> createState() =>
      _ClaimAddressPickerSheetState();
}

class _ClaimAddressPickerSheetState extends State<_ClaimAddressPickerSheet> {
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

  List<Map<String, dynamic>> get _mindanaoProvinces {
    return phProvinces.cast<Map<String, dynamic>>();
  }

  List<Map<String, dynamic>> get _citiesInProvince {
    if (_province == null) return const [];
    final province = _mindanaoProvinces.firstWhere(
      (item) => item['name'] == _province,
      orElse: () => <String, dynamic>{},
    );
    final rawCities = province['cities'];
    if (rawCities is! List) return const [];
    return rawCities.cast<Map<String, dynamic>>();
  }

  List<String> get _barangaysInCity {
    if (_city == null) return const [];
    final city = _citiesInProvince.firstWhere(
      (item) => item['name'] == _city,
      orElse: () => <String, dynamic>{},
    );
    final rawBarangays = city['barangays'];
    if (rawBarangays is! List) return const [];
    return rawBarangays
        .where(
          (item) =>
              item is String &&
              item.trim().isNotEmpty &&
              !RegExp(r'^[A-Z]$').hasMatch(item.trim()),
        )
        .cast<String>()
        .toList();
  }

  void _goBackOneStep() {
    setState(() {
      if (_stepIndex == 1) {
        _region = null;
        _province = null;
        _city = null;
        _barangay = null;
      } else if (_stepIndex == 2) {
        _province = null;
        _city = null;
        _barangay = null;
      } else if (_stepIndex == 3) {
        _city = null;
        _barangay = null;
      }
    });
  }

  String _composeAddress() {
    return [
      if (_barangay?.isNotEmpty == true) _barangay,
      if (_city?.isNotEmpty == true) _city,
      if (_province?.isNotEmpty == true) _province,
      if (_region?.isNotEmpty == true) _region,
    ].join(', ');
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
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  const Text(
                    'Set Vigil Location',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kNeutralText,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _region = null;
                      _province = null;
                      _city = null;
                      _barangay = null;
                      _barangaySearch = '';
                    }),
                    child: const Text(
                      'Reset',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ClaimVerticalTrail(
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
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _locating
                              ? null
                              : () async {
                                  setState(() => _locating = true);
                                  await widget.onUseMyLocation();
                                  if (mounted) {
                                    setState(() => _locating = false);
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: _locating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.my_location_rounded),
                          label: Text(
                            _locating
                                ? 'Getting current location...'
                                : 'Use My Current Location',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Region',
                          style: TextStyle(color: kSubtleText),
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Mindanao'),
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                        ),
                        onTap: () => setState(() {
                          _region = 'Mindanao';
                          _province = null;
                          _city = null;
                          _barangay = null;
                        }),
                      ),
                    ],
                    if (_stepIndex == 1) ...[
                      _ClaimBackButton(onPressed: _goBackOneStep),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Province',
                          style: TextStyle(color: kSubtleText),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._mindanaoProvinces.map((province) {
                        final name = (province['name'] ?? '').toString();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(name),
                          trailing: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                          ),
                          onTap: () => setState(() {
                            _province = name;
                            _city = null;
                            _barangay = null;
                          }),
                        );
                      }),
                    ],
                    if (_stepIndex == 2) ...[
                      _ClaimBackButton(onPressed: _goBackOneStep),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'City / Municipality',
                          style: TextStyle(color: kSubtleText),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._citiesInProvince.map((city) {
                        final name = (city['name'] ?? '').toString().trim();
                        if (name.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(name),
                          trailing: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                          ),
                          onTap: () => setState(() {
                            _city = name;
                            _barangay = null;
                          }),
                        );
                      }),
                    ],
                    if (_stepIndex == 3) ...[
                      _ClaimBackButton(onPressed: _goBackOneStep),
                      TextField(
                        inputFormatters: AppInputSecurity.singleLineFormatters(
                          maxLength: 80,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search barangay...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (value) {
                          setState(
                            () => _barangaySearch =
                                AppInputSecurity.sanitizeSearchQuery(value),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      RadioGroup<String>(
                        groupValue: _barangay,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _barangay = value);
                          Navigator.pop(
                            context,
                            _ClaimAddressPickResult(
                              rawText: _composeAddress(),
                              region: _region,
                              province: _province,
                              city: _city,
                              barangay: value,
                            ),
                          );
                        },
                        child: Column(
                          children: _barangaysInCity
                              .where(
                                (name) => name.toLowerCase().contains(
                                  _barangaySearch.toLowerCase(),
                                ),
                              )
                              .map(
                                (name) => RadioListTile<String>(
                                  contentPadding: EdgeInsets.zero,
                                  value: name,
                                  title: Text(name),
                                  activeColor: kPrimary,
                                ),
                              )
                              .toList(),
                        ),
                      ),
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

class _ClaimBackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ClaimBackButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14),
        label: const Text('Back'),
      ),
    );
  }
}

class _ClaimVerticalTrail extends StatelessWidget {
  final String? region;
  final String? province;
  final String? city;
  final String? barangay;
  final int activeStep;

  const _ClaimVerticalTrail({
    required this.region,
    required this.province,
    required this.city,
    required this.barangay,
    required this.activeStep,
  });

  Widget _step(String label, String? value, bool active, bool showDivider) {
    final highlight = value != null || active;
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: highlight ? kPrimary : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value == null ? label : '$label: $value',
                style: TextStyle(
                  fontSize: 12,
                  color: highlight ? kNeutralText : Colors.grey.shade500,
                  fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
        if (showDivider)
          Container(
            margin: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
            width: 2,
            height: 16,
            color: Colors.grey.shade300,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _step('Region', region, activeStep == 0, true),
        _step('Province', province, activeStep == 1, true),
        _step('City', city, activeStep == 2, true),
        _step('Barangay', barangay, activeStep == 3, false),
      ],
    );
  }
}
