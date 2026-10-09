import 'dart:convert';
import 'dart:ui';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:capstone_app/utils/input_safety.dart';
import 'package:capstone_app/utils/supabase_storage.dart';
import 'package:cupertino_calendar_picker/cupertino_calendar_picker.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kBg = Color(0xFFFAFAF7);
const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kAccent = Color(0xFF0D47A1);
const kPrimary = Color(0xFF0D47A1);
const kWarn = Color(0xFFF57C00);
const kDanger = Color(0xFFC62828);
const kSuccess = Color(0xFF10B981);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);

class AddBeneficiaryPage extends StatefulWidget {
  final bool embedded;
  final Map<String, dynamic>? beneficiary;
  final int? dayungUnitId;

  const AddBeneficiaryPage({
    super.key,
    this.embedded = false,
    this.beneficiary,
    this.dayungUnitId,
  });

  @override
  State<AddBeneficiaryPage> createState() => _AddBeneficiaryPageState();
}

class _AddBeneficiaryPageState extends State<AddBeneficiaryPage> {
  final TextEditingController fullNameController = TextEditingController();
  final user = Supabase.instance.client.auth.currentUser;
  final _formKey = GlobalKey<FormState>();

  bool _isSubmitting = false;
  bool _isUploadingFile = false;
  bool _isUploadingValidId = false;

  String? selectedRelationship;
  String? birthCertificateFile;
  String? validIdFile;
  String? selectedMaritalStatus;
  DateTime? _selectedDob;

  final List<String> _relationships = [
    'Spouse',
    'Child',
    'Parent',
    'Sibling',
    'Grandparent',
    'Grandchild',
    'Aunt/Uncle',
    'Niece/Nephew',
    'Cousin',
    'Household Member',
    'Other',
  ];

  final List<String> _maritalStatuses = ['Single', 'Widowed', 'Separated'];

  List<String> get _availableMaritalStatuses =>
      selectedRelationship == 'Spouse' ? ['Married'] : _maritalStatuses;

  @override
  void initState() {
    super.initState();
    _prefillForEdit();
  }

  void _prefillForEdit() {
    final beneficiary = widget.beneficiary;
    if (beneficiary == null) return;

    fullNameController.text = (beneficiary['full_name'] ?? '').toString();
    selectedRelationship = beneficiary['relationship']?.toString();
    selectedMaritalStatus = beneficiary['marital_status']?.toString();
    birthCertificateFile = beneficiary['birth_certificate']?.toString();
    validIdFile = beneficiary['valid_id']?.toString();

    final dob = beneficiary['dob']?.toString();
    if (dob != null && dob.isNotEmpty) {
      try {
        _selectedDob = DateTime.parse(dob);
      } catch (_) {
        _selectedDob = null;
      }
    }

    if (selectedRelationship == 'Spouse' && selectedMaritalStatus == null) {
      selectedMaritalStatus = 'Married';
    }
  }

  @override
  void dispose() {
    fullNameController.dispose();
    super.dispose();
  }

  void _showTopPopup(
    String message, {
    Color color = kAccent,
    IconData icon = Icons.check_circle,
  }) {
    final overlay = Overlay.of(context);

    late OverlayEntry entry;
    final animationController = AnimationController(
      vsync: Navigator.of(context),
      duration: const Duration(milliseconds: 350),
    );
    final curved = CurvedAnimation(
      parent: animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 24,
        right: 24,
        child: AnimatedBuilder(
          animation: curved,
          builder: (context, child) {
            return Opacity(
              opacity: curved.value,
              child: Transform.translate(
                offset: Offset(0, -40 * (1 - curved.value)),
                child: child,
              ),
            );
          },
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.38),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                blurRadius: 8,
                                offset: Offset(0, 2),
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
          ),
        ),
      ),
    );

    overlay.insert(entry);
    animationController.forward();

    Future.delayed(const Duration(seconds: 3), () async {
      await animationController.reverse();
      entry.remove();
      animationController.dispose();
    });
  }

  InputDecoration _dec(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        color: kSubText,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      prefixIcon: icon != null ? Icon(icon, color: kSubText, size: 18) : null,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: kBorderColor.withValues(alpha: 0.9)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kDanger, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kDanger, width: 1.5),
      ),
    );
  }

  InputDecoration _dropdownDec(String label) => _dec(label).copyWith(
    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
  );

  Widget _buildTopCategoryChip({
    required String label,
    required String value,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
                fontFamily: 'Montserrat',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorderColor.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader({required IconData icon, required String title}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionIcon(icon),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: kText,
              fontFamily: 'Montserrat',
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: kPrimary, size: 22),
    );
  }

  Future<void> _showCalendarDialog(BuildContext context) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 120, 1, 1);
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
              primaryColor: kAccent,
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
                            color: kText,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, temp),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              color: kAccent,
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

  Widget _dobField(BuildContext rootContext) {
    return GestureDetector(
      onTap: () => _showCalendarDialog(rootContext),
      child: AbsorbPointer(
        child: TextFormField(
          readOnly: true,
          style: const TextStyle(
            fontSize: 14,
            color: kText,
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

  Future<void> _pickAndUploadFile() async {
    setState(() => _isUploadingFile = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) {
        setState(() => _isUploadingFile = false);
        return;
      }

      final file = result.files.single;
      final ext = (file.extension ?? 'jpg').toLowerCase();
      final fileName =
          '${user?.id}-${DateTime.now().millisecondsSinceEpoch}.$ext';
      final filePath = 'birth_certificates/$fileName';

      await Supabase.instance.client.storage
          .from('birth_certificates')
          .uploadBinary(
            filePath,
            file.bytes!,
            fileOptions: const FileOptions(upsert: true),
          );

      setState(() {
        birthCertificateFile = buildStorageRef('birth_certificates', filePath);
      });

      if (!mounted) return;
      _showTopPopup(
        'File uploaded successfully',
        color: kSuccess,
        icon: Icons.check_circle,
      );
    } catch (e) {
      if (!mounted) return;
      _showTopPopup(
        'File upload failed: $e',
        color: kWarn,
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _isUploadingFile = false);
    }
  }

  Future<void> _pickAndUploadValidId() async {
    setState(() => _isUploadingValidId = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) {
        setState(() => _isUploadingValidId = false);
        return;
      }

      final file = result.files.single;
      final ext = (file.extension ?? 'jpg').toLowerCase();
      final fileName =
          '${user?.id}-${DateTime.now().millisecondsSinceEpoch}.$ext';
      final filePath = 'valid_ids/$fileName';

      await Supabase.instance.client.storage
          .from('valid_ids')
          .uploadBinary(
            filePath,
            file.bytes!,
            fileOptions: const FileOptions(upsert: true),
          );

      setState(() {
        validIdFile = buildStorageRef('valid_ids', filePath);
      });

      if (!mounted) return;
      _showTopPopup(
        'Valid ID uploaded successfully',
        color: kSuccess,
        icon: Icons.check_circle,
      );
    } catch (e) {
      if (!mounted) return;
      _showTopPopup(
        'Valid ID upload failed: $e',
        color: kWarn,
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _isUploadingValidId = false);
    }
  }

  Future<void> _showUploadedFilePreview(String fileUrl) async {
    try {
      final signedUrl = await resolveSupabaseStorageUrl(fileUrl);
      if (signedUrl == null) throw Exception('Could not access uploaded file');

      final response = await http.get(Uri.parse(signedUrl));
      if (response.statusCode != 200) {
        throw Exception('Download failed (${response.statusCode})');
      }

      final bytes = response.bodyBytes;
      final imageBytes = _isPlaintextImage(bytes)
          ? bytes
          : _decryptUploadedImage(bytes);
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 500,
                    maxHeight: 600,
                  ),
                  child: Image.memory(
                    imageBytes,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const Text('Could not display this image'),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Close'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showTopPopup(
        'Could not load image: $e',
        color: kWarn,
        icon: Icons.error_outline,
      );
    }
  }

  Uint8List _decryptUploadedImage(Uint8List bytes) {
    if (bytes.length < 32) throw Exception('Invalid encrypted image');

    final key = encrypt.Key.fromUtf8(
      'capstonedayungappjjm'.padRight(32).substring(0, 32),
    );
    final iv = encrypt.IV(bytes.sublist(0, 16));
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    return Uint8List.fromList(
      encrypter.decryptBytes(encrypt.Encrypted(bytes.sublist(16)), iv: iv),
    );
  }

  bool _isPlaintextImage(Uint8List bytes) {
    final isPng =
        bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A;
    final isJpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
    final isGif =
        bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x37 || bytes[4] == 0x39) &&
        bytes[5] == 0x61;
    final isWebp =
        bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return isPng || isJpeg || isGif || isWebp;
  }

  String _formatDob(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submitBeneficiary() async {
    if (!_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    if (user == null) {
      _showTopPopup(
        'You must be logged in',
        color: kWarn,
        icon: Icons.error_outline,
      );
      return;
    }
    if (_selectedDob == null) {
      _showTopPopup(
        'Date of birth is required',
        color: kWarn,
        icon: Icons.error_outline,
      );
      return;
    }
    if (validIdFile == null) {
      _showTopPopup(
        'Valid ID is required',
        color: kWarn,
        icon: Icons.error_outline,
      );
      return;
    }

    int? unitFromPrefs = widget.dayungUnitId;
    if (unitFromPrefs == null) {
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
    }

    final String? unitText = unitFromPrefs?.toString();
    setState(() => _isSubmitting = true);

    final fullName = AppInputSecurity.sanitizePlainText(
      fullNameController.text,
      maxLength: 120,
    );
    final maritalStatus = selectedMaritalStatus?.trim();
    final relationship = selectedRelationship!.trim();
    final dob = _formatDob(_selectedDob!);
    final isEditing = widget.beneficiary != null;
    final beneficiaryId = widget.beneficiary?['id'];
    final isLockedForClaim = widget.beneficiary?['eligible_to_claim'] == true;

    if (isEditing && isLockedForClaim) {
      _showTopPopup(
        'This beneficiary is already eligible to claim and cannot be edited.',
        color: kWarn,
        icon: Icons.lock_rounded,
      );
      return;
    }

    try {
      Map<String, dynamic>? response;

      if (isEditing) {
        if (beneficiaryId == null) {
          _showTopPopup(
            'Could not find this beneficiary to update.',
            color: kWarn,
            icon: Icons.error_outline,
          );
          return;
        }

        response = await Supabase.instance.client
            .from('beneficiaries')
            .update({
              'full_name': fullName,
              'dob': dob,
              'marital_status': maritalStatus,
              'relationship': relationship,
              'birth_certificate': birthCertificateFile,
              'valid_id': validIdFile,
              'dayung_unit_id': unitText,
            })
            .eq('id', beneficiaryId)
            .eq('user_id', user!.id)
            .select()
            .maybeSingle();
      } else {
        response = await Supabase.instance.client
            .from('beneficiaries')
            .insert([
              {
                'user_id': user!.id,
                'full_name': fullName,
                'dob': dob,
                'marital_status': maritalStatus,
                'relationship': relationship,
                'birth_certificate': birthCertificateFile,
                'valid_id': validIdFile,
                'dayung_unit_id': unitText,
              },
            ])
            .select()
            .maybeSingle();
      }

      if (!mounted) return;
      if (response == null || response['id'] == null) {
        _showTopPopup(
          isEditing
              ? 'Failed to update beneficiary'
              : 'Failed to add beneficiary',
          color: kWarn,
          icon: Icons.error_outline,
        );
      } else {
        _showTopPopup(
          isEditing ? 'Beneficiary updated' : 'Beneficiary added',
          color: kSuccess,
          icon: Icons.check_circle,
        );
        if (!isEditing) {
          fullNameController.clear();
          setState(() {
            selectedRelationship = null;
            selectedMaritalStatus = null;
            _selectedDob = null;
            birthCertificateFile = null;
            validIdFile = null;
          });
        }
        if (!widget.embedded) navigator.pop();
      }
    } catch (e) {
      if (!mounted) return;
      _showTopPopup('Error: $e', color: kWarn, icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;
    final isCompact = width < 380;
    final horizontal = isCompact ? 16.0 : 24.0;
    final isLockedForClaim = widget.beneficiary?['eligible_to_claim'] == true;

    final content = SafeArea(
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              8,
              isWide ? 36 : 28,
              isWide ? 24 : 16,
              isWide ? 32 : 24,
            ),
            decoration: const BoxDecoration(
              color: kPrimary,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF1E40AF),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                if (!widget.embedded) ...[
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Text(
                    widget.beneficiary != null
                        ? 'Edit Beneficiary'
                        : widget.embedded
                        ? 'My Beneficiaries1'
                        : 'Add Beneficiary',
                    style: TextStyle(
                      fontSize: isWide ? 24 : 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontFamily: 'Montserrat',
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isWide ? 720 : 480),
                  child: Column(
                    children: [
                      _buildSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isLockedForClaim)
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: kWarn.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: kWarn.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.lock_rounded,
                                      color: kWarn,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'This beneficiary is already eligible to claim and can no longer be edited.',
                                        style: TextStyle(
                                          color: kText,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          fontFamily: 'OpenSans',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            _buildSectionHeader(
                              icon: Icons.person_add_alt_1_rounded,
                              title:
                                  'Please add your beneficiaries. This is required for Dayung.',
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildTopCategoryChip(
                                  label: 'Status',
                                  value: 'Pending',
                                  color: kWarn,
                                  background: const Color(0xFFFFFBEB),
                                ),
                                _buildTopCategoryChip(
                                  label: 'Required',
                                  value: 'ID',
                                  color: kPrimary,
                                  background: const Color(0xFFF5F9FF),
                                ),
                                _buildTopCategoryChip(
                                  label: 'Optional',
                                  value: 'BC',
                                  color: kSuccess,
                                  background: const Color(0xFFF0FDF4),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSectionCard(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_isSubmitting)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 20),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: kAccent.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const LinearProgressIndicator(
                                    color: kAccent,
                                    backgroundColor: Color(0xFFEFF2F7),
                                    minHeight: 4,
                                  ),
                                ),
                              _buildSectionHeader(
                                icon: Icons.badge_outlined,
                                title: 'Basic Details',
                              ),
                              const SizedBox(height: 18),
                              TextFormField(
                                controller: fullNameController,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                inputFormatters: [
                                  ...AppInputSecurity.singleLineFormatters(
                                    maxLength: 120,
                                  ),
                                  TextInputFormatter.withFunction((
                                    oldValue,
                                    newValue,
                                  ) {
                                    String capitalizeWordInitials(String text) {
                                      return text.replaceAllMapped(
                                        RegExp(r'(^|\s)(\S)'),
                                        (match) =>
                                            '${match[1]}${match[2]!.toUpperCase()}',
                                      );
                                    }

                                    final text = capitalizeWordInitials(
                                      newValue.text,
                                    );
                                    final baseOffset =
                                        newValue.selection.baseOffset;
                                    final extentOffset =
                                        newValue.selection.extentOffset;

                                    return newValue.copyWith(
                                      text: text,
                                      selection: TextSelection(
                                        baseOffset: baseOffset < 0
                                            ? baseOffset
                                            : capitalizeWordInitials(
                                                newValue.text.substring(
                                                  0,
                                                  baseOffset,
                                                ),
                                              ).length,
                                        extentOffset: extentOffset < 0
                                            ? extentOffset
                                            : capitalizeWordInitials(
                                                newValue.text.substring(
                                                  0,
                                                  extentOffset,
                                                ),
                                              ).length,
                                        affinity: newValue.selection.affinity,
                                        isDirectional:
                                            newValue.selection.isDirectional,
                                      ),
                                    );
                                  }),
                                ],
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: kText,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: _dec(
                                  'Full Name',
                                  hint: 'e.g., Yanashii Mikasa',
                                  icon: Icons.badge_outlined,
                                ),
                                validator: (v) =>
                                    AppInputSecurity.validateSafeText(
                                      v,
                                      fieldName: 'Full Name',
                                      minLength: 2,
                                      maxLength: 120,
                                    ),
                              ),
                              const SizedBox(height: 14),
                              _dobField(context),
                              const SizedBox(height: 14),
                              DropdownButtonFormField2<String>(
                                isExpanded: true,
                                decoration: _dropdownDec('Relationship'),
                                value: selectedRelationship,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: kText,
                                  fontWeight: FontWeight.w500,
                                ),
                                items: _relationships
                                    .map(
                                      (rel) => DropdownMenuItem<String>(
                                        value: rel,
                                        child: Text(rel),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) => setState(() {
                                  selectedRelationship = value;
                                  if (value == 'Spouse') {
                                    selectedMaritalStatus = 'Married';
                                  }
                                }),
                                validator: (value) => value == null
                                    ? 'Relationship is required'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              DropdownButtonFormField2<String>(
                                isExpanded: true,
                                decoration: _dropdownDec('Marital Status'),
                                value: selectedMaritalStatus,
                                style: const TextStyle(
                                  color: kText,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                                items: _availableMaritalStatuses
                                    .map(
                                      (status) => DropdownMenuItem<String>(
                                        value: status,
                                        child: Text(status),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) => setState(
                                  () => selectedMaritalStatus = value,
                                ),
                                validator: (value) => value == null
                                    ? 'Marital status is required'
                                    : null,
                              ),
                              const SizedBox(height: 24),
                              _buildSectionHeader(
                                icon: Icons.file_copy_rounded,
                                title: 'Supporting Documents',
                              ),
                              const SizedBox(height: 18),
                              _fileUploadSection(
                                label: 'Birth Certificate (optional)',
                                isUploading: _isUploadingFile,
                                fileUrl: birthCertificateFile,
                                onUpload: _pickAndUploadFile,
                                onClear: () =>
                                    setState(() => birthCertificateFile = null),
                              ),
                              const SizedBox(height: 16),
                              _fileUploadSection(
                                label: 'Valid ID (required)',
                                isUploading: _isUploadingValidId,
                                fileUrl: validIdFile,
                                onUpload: _pickAndUploadValidId,
                                onClear: () =>
                                    setState(() => validIdFile = null),
                                required: true,
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton.icon(
                                  icon: const Icon(
                                    Icons.check_circle_rounded,
                                    size: 20,
                                  ),
                                  label: Text(
                                    widget.beneficiary != null
                                        ? 'Save Changes'
                                        : 'Submit Beneficiary',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      fontFamily: 'Montserrat',
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isLockedForClaim
                                        ? kSubText
                                        : kAccent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 0,
                                  ),
                                  onPressed: _isSubmitting || isLockedForClaim
                                      ? null
                                      : _submitBeneficiary,
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
          ),
        ],
      ),
    );

    if (widget.embedded) return content;

    return Scaffold(backgroundColor: kBg, body: content);
  }

  Widget _fileUploadSection({
    required String label,
    required bool isUploading,
    required String? fileUrl,
    required VoidCallback onUpload,
    required VoidCallback onClear,
    bool required = false,
  }) {
    final isCompact = MediaQuery.of(context).size.width < 380;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorderColor.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildUploadIcon(fileUrl),
                    const SizedBox(height: 12),
                    _buildUploadTexts(label, required, fileUrl),
                  ],
                )
              : Row(
                  children: [
                    _buildUploadIcon(fileUrl),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildUploadTexts(label, required, fileUrl),
                    ),
                  ],
                ),
          const SizedBox(height: 14),
          if (fileUrl == null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon(
                  isUploading ? Icons.autorenew_rounded : Icons.upload_file,
                  color: kAccent,
                ),
                label: Text(isUploading ? 'Uploading...' : 'Upload File'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kAccent,
                  side: const BorderSide(color: kAccent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Montserrat',
                  ),
                ),
                onPressed: isUploading ? null : onUpload,
              ),
            )
          else if (isCompact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'File uploaded',
                  style: TextStyle(
                    color: kSuccess,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.visibility_rounded, size: 18),
                      label: const Text('Preview'),
                      style: TextButton.styleFrom(
                        foregroundColor: kAccent,
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                      onPressed: () => _showUploadedFilePreview(fileUrl),
                    ),
                    TextButton.icon(
                      icon: const Icon(
                        Icons.clear_rounded,
                        color: kDanger,
                        size: 18,
                      ),
                      label: const Text('Remove'),
                      style: TextButton.styleFrom(
                        foregroundColor: kDanger,
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                      onPressed: onClear,
                    ),
                  ],
                ),
              ],
            )
          else
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'File uploaded',
                    style: TextStyle(
                      color: kSuccess,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text('Preview'),
                  style: TextButton.styleFrom(
                    foregroundColor: kAccent,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                  onPressed: () => _showUploadedFilePreview(fileUrl),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.clear_rounded,
                    color: kDanger,
                    size: 20,
                  ),
                  onPressed: onClear,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildUploadIcon(String? fileUrl) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: (fileUrl != null ? kSuccess : kPrimary).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        fileUrl != null
            ? Icons.check_circle_rounded
            : Icons.upload_file_rounded,
        color: fileUrl != null ? kSuccess : kPrimary,
      ),
    );
  }

  Widget _buildUploadTexts(String label, bool required, String? fileUrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label + (required ? ' *' : ''),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: kText,
            fontSize: 15,
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          fileUrl == null
              ? 'JPG, PNG, PDF'
              : 'Document uploaded and ready for review.',
          style: const TextStyle(
            color: kSubText,
            fontSize: 12,
            fontFamily: 'OpenSans',
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
