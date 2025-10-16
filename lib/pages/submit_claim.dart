import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:io';

// Shared palette (aligned with claims page)
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);
const double kRadius = 18;

class SubmitClaimForm extends StatefulWidget {
  const SubmitClaimForm({super.key});
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
  File? _deathCertFile;
  String? _selectedDeceasedType; // 'member' or 'beneficiary'
  int? _selectedBeneficiaryId;
  DateTime? _dateOfDeath;
  List<Map<String, dynamic>> _beneficiaries = [];

  @override
  void initState() {
    super.initState();
    _fetchBeneficiaries();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
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
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _deathCertFile = File(result.files.single.path!);
      });
    }
  }

  Future<void> _pickVigilLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
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

      String? addr;
      String? brgy;
      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        addr = [
          p.street,
          p.subLocality,
          p.locality,
          p.administrativeArea,
          p.postalCode,
        ].where((e) => (e ?? '').toString().trim().isNotEmpty).join(', ');
        brgy = (p.subLocality?.isNotEmpty ?? false)
            ? p.subLocality
            : p.locality;
      }

      setState(() {
        _vigilPos = pos;
        _vigilAddress = addr;
        _vigilBarangay = brgy;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to get location: $e')));
    }
  }

  Future<String?> _uploadDeathCert(String claimId) async {
    if (_deathCertFile == null) return null;
    final storage = Supabase.instance.client.storage;
    final fileName =
        'death_cert_${claimId}_${DateTime.now().millisecondsSinceEpoch}.${_deathCertFile!.path.split('.').last}';
    final bucket = 'death_certificates';
    final res = await storage.from(bucket).upload(fileName, _deathCertFile!);
    if (res.error != null) throw Exception(res.error!.message);
    return storage.from(bucket).getPublicUrl(fileName);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = Supabase.instance.client.auth.currentUser;
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
    // Require date of death for both member or beneficiary claims
    if (_dateOfDeath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select date of death.')),
      );
      return;
    }

    String _fmtDate(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    setState(() => _submitting = true);
    try {
      // 1. Insert claim (now includes date_of_death)
      final claimData = {
      'user_id': user.id,
      'title': _title.text.trim(),
      'description': _desc.text.trim(),
      'status': 'Pending',
      if (_selectedBeneficiaryId != null) 'beneficiary_id': _selectedBeneficiaryId,
      'date_of_death': _fmtDate(_dateOfDeath!),
      // vigil fields
      'vigil_latitude': _vigilPos?.latitude,
      'vigil_longitude': _vigilPos?.longitude,
      'vigil_address': _vigilAddress,
      'vigil_barangay': _vigilBarangay,
    };
    final insertRes = await Supabase.instance.client
        .from('claims')
        .insert(claimData)
        .select()
        .maybeSingle();
      final claimId = insertRes!['id'].toString();

      // 2. Upload file if picked
      String? fileUrl;
      if (_deathCertFile != null) {
        fileUrl = await _uploadDeathCert(claimId);
        await Supabase.instance.client
            .from('claims')
            .update({'death_certificate_url': fileUrl})
            .eq('id', claimId);
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

  InputDecoration _fieldDec({
    required String label,
    required IconData icon,
    int lines = 1,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.grey.shade100,
      contentPadding: EdgeInsets.symmetric(
        vertical: lines > 1 ? 16 : 0,
        horizontal: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: kPrimaryDark, width: 1.6),
      ),
    );
  }

  Widget _buildModernField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    int maxLines = 1,
    int minLines = 1,
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
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: kPrimaryDark, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
        value: _selectedDeceasedType,
        items: [
          const DropdownMenuItem(
            value: 'member',
            child: Text('I am the deceased'),
          ),
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
        onTap: _submitting ? null : () async {
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
                  color: _dateOfDeath == null ? Colors.grey.shade600 : kNeutralText,
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
                  _deathCertFile == null
                      ? 'Attach death certificate'
                      : _deathCertFile!.path.split('/').last,
                  style: TextStyle(
                    fontSize: 14,
                    color: _deathCertFile == null ? Colors.grey.shade600 : kNeutralText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_deathCertFile != null)
                IconButton(
                  onPressed: () => setState(() => _deathCertFile = null),
                  icon: Icon(Icons.close, color: Colors.grey.shade600, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernVigilLocation() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: _submitting ? null : _pickVigilLocation,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.my_location, color: kPrimaryDark, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _vigilAddress == null
                      ? 'Set vigil location'
                      : 'Barangay: ${_vigilBarangay ?? '-'}\n$_vigilAddress',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: _vigilAddress == null ? Colors.grey.shade600 : kNeutralText,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey.shade600, size: 16),
            ],
          ),
        ),
      ),
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
                colors: [
                  Color(0xFF1E40AF),
                  Color(0xFF3B82F6),
                ],
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

extension on String {
  get error => null;
}