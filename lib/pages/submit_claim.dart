import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:io';
import 'package:flutter/foundation.dart'; // add for kIsWeb

// Shared palette (aligned with claims page)
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
  Position? _vigilPos;
  String? _vigilAddress;
  String? _vigilBarangay;
  bool _submitting = false;
  bool _locating = false;
  File? _deathCertFile;
  Uint8List? _deathCertBytes;
  String? _deathCertOrigName;
  double? _vigilLat;
  double? _vigilLng;
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
      _title.text = 'You Will Always Be With Us'; 
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied.')),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _vigilLat = pos.latitude;
      _vigilLng = pos.longitude;

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

      setState(() {
        _vigilPos = pos;
        _vigilAddress = composed ?? '(${pos.latitude}, ${pos.longitude})';
        _vigilBarangay = barangay?.isNotEmpty == true ? barangay : city;
      });
    } catch (e) {
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
      print(
        '[UPLOAD] bucket=$bucket fileName=$fileName size=${bytes.length} mime=$mime',
      );

      final storedPath = await storage
          .from(bucket)
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );

      print('[UPLOAD] stored path: $storedPath');

      final publicUrl = storage.from(bucket).getPublicUrl(fileName);
      print('[UPLOAD] public URL: $publicUrl');
      return publicUrl;
    } on StorageException catch (e, st) {
      print('[UPLOAD][StorageException] ${e.message}\n$st');
      rethrow;
    } catch (e, st) {
      print('[UPLOAD][GenericError] $e\n$st');
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
      await storage
          .from(bucket)
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
      final publicUrl = storage.from(bucket).getPublicUrl(fileName);
      return publicUrl;
    } on StorageException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Valid ID storage error: ${e.message}')),
      );
      return null;
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Valid ID upload failed: $e')));
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final sb = Supabase.instance.client;
    final user = sb.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not logged in.')));
      return;
    }
    if (_selectedDeceasedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select who passed away.')),
      );
      return;
    }
    if (_dateOfDeath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No Dayung selected.')));
      return;
    }

    // Validate membership in the selected unit via applications (approved)
    final apps = await sb
        .from('applications')
        .select('id')
        .eq('user_id', user.id)
        .eq('dayung_unit_id', effectiveUnitId)
        .eq('status', 'approved')
        .limit(1);
    if ((apps as List).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are not a member of this Dayung.')),
      );
      return;
    }

    // Validate membership in the selected unit via applications (approved)
    if (widget.requireMembership) {
      final apps = await sb
          .from('applications')
          .select('id')
          .eq('user_id', user.id)
          .eq('dayung_unit_id', effectiveUnitId)
          .eq('status', 'approved')
          .limit(1);
      if ((apps as List).isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are not a member of this Dayung.')),
        );
        return;
      }
    }

    String fmtDate(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    setState(() => _submitting = true);
    try {
      final claimData = {
        'user_id': user.id,
        'title': _title.text.trim(),
        'description': _desc.text.trim(),
        'status': 'Pending',
        if (_selectedBeneficiaryId != null)
          'beneficiary_id': _selectedBeneficiaryId,
        'date_of_death': fmtDate(_dateOfDeath!),
        'dayung_unit_id': effectiveUnitId,
        'vigil_latitude': _vigilPos?.latitude,
        'vigil_longitude': _vigilPos?.longitude,
        'vigil_address': _vigilAddress,
        'vigil_barangay': _vigilBarangay,
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
          ScaffoldMessenger.of(context).showSnackBar(
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Valid ID upload failed: $e')));
        }
      }

      if (updateFields.isNotEmpty) {
        await sb.from('claims').update(updateFields).eq('id', claimId);
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Claim submitted.')));
    } catch (e, st) {
      print('CLAIM SUBMIT ERROR: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Submit failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

Widget _buildModernField({
  required TextEditingController controller,
  required String label,
  required IconData icon,
  String? Function(String?)? validator,
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: InkWell(
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
    );
  }

  // ADD: valid ID upload widget
  Widget _buildValidIdUpload() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: InkWell(
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
                      ? 'Attach Valid ID of the claimant / Valid ID sa person na mo claim'
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
    );
  }

  Widget _buildModernVigilLocation() {
    final disabled = _submitting || _locating;
    return Column(
      children: [
        // Align(
        //   alignment: Alignment.centerLeft,
        //   child: ElevatedButton.icon(
        //     onPressed: disabled ? null : _pickVigilLocation,
        //     style: ElevatedButton.styleFrom(
        //       backgroundColor: kPrimaryDark,
        //       foregroundColor: Colors.white,
        //     ),
        //     icon: _locating
        //         ? const SizedBox(
        //             width: 18,
        //             height: 18,
        //             child: CircularProgressIndicator(
        //               strokeWidth: 2,
        //               valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        //             ),
        //           )
        //         : const Icon(Icons.my_location, size: 18),
        //     label: Text(
        //       _locating ? 'Setting location...' : 'Use My Current Location',
        //       style: const TextStyle(fontWeight: FontWeight.w600),
        //     ),
        //   ),
        // ),
        // const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: InkWell(
            onTap: disabled ? null : _pickVigilLocation,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.my_location,
                    color: _locating ? Colors.orange : kPrimaryDark,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _locating
                          ? 'Setting location...'
                          : (_vigilAddress == null
                                ? 'Set vigil location'
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
            color: kPrimaryDark.withOpacity(0.3),
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
                    color: Colors.white.withOpacity(0.2),
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
                    color: Colors.white.withOpacity(0.2),
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
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'Enter a title';
                        if (t.length < 4) return 'Too short';
                        return null;
                      },
                        readOnly: true, 
                    ),
                    const SizedBox(height: 16),

                    // Description
                    _buildModernField(
                      controller: _desc,
                      label: 'Description (optional)',
                      icon: Icons.notes_rounded,
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
