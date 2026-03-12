import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:capstone_app/Auth/login.dart' hide kWarn, kDanger;
import 'package:capstone_app/President/manage_rules.dart'
    hide kPrimary, kAccent;
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/profile/required_application_page.dart'
    hide kAccent;
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/ui/theme/branding.dart';
import 'package:capstone_app/utils/input_safety.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dropdown_button2/dropdown_button2.dart';

// color palette
const kText = Color(0xFF111827);
const kSubText = Color(0xFF6B7280);
const kPrimaryLight = Color(0xFF3B82F6);
const kAccentDark = Color(0xFF059669);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSuccess = Color(0xFF10B981);

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;

  final _fullNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _addressController = TextEditingController();
  final _sexController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _personalInfoKey = GlobalKey();
  final ImagePicker _imagePicker = ImagePicker();
  final _currentPwController = TextEditingController();
  final _newPwController = TextEditingController();
  final _confirmPwController = TextEditingController();

  String fullName = '';
  String mobileNumber = '';
  String address = '';
  String sex = '';
  String email = '';
  String? dateOfBirth;
  String? barangay;
  String? city;
  String? province;
  int? activeDayungUnitId;
  String? activeDayungName;
  String? activeApplicationStatus;
  String? profileUrl;
  String? birthCertificateUrl;
  String? marriageCertificateUrl;
  String? validIdUrl; // Add this field to hold the valid ID URL
  String?
  proofOfResidencyUrl; // Add this field to hold the proof of residency URL
  // ignore: unused_field
  int? _unitAtEntry;

  bool _obscureCur = true;
  bool _obscureNew = true;
  bool _obscureConf = true;
  bool _loggingOut = false;
  bool isLoading = true;
  bool _editing = false;
  bool _saving = false;
  bool _uploadingImage = false;
  bool get isPresident {
    try {
      return context.select<DayungRoleProvider, bool>((r) => r.isPresident);
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
    _loadUnitAtEntry();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final unitId = context.read<DayungUnitProvider>().currentUnitId;
      context.read<DayungRoleProvider>().refreshRoles(unitId);
    });
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _sexController.dispose();
    _currentPwController.dispose();
    _newPwController.dispose();
    _confirmPwController.dispose();
    super.dispose();
  }

  Future<void> _logAudit(String action) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await supabase.from('audit_logs').insert({
      'action': action,
      'user_id': user.id,
    });
  }

  Future<void> _loadUnitAtEntry() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('selectedDayungUnit');
    int? id;
    if (raw != null) {
      try {
        id = (jsonDecode(raw) as Map)['id'] as int?;
      } catch (_) {}
    }
    if (mounted) setState(() => _unitAtEntry = id);
  }

  Future<void> _openChangePasswordDialog() async {
    _currentPwController.clear();
    _newPwController.clear();
    _confirmPwController.clear();

    String? curErr;
    String? newErr;
    String? confErr;
    String? genErr;
    bool saving = false;

    InputDecoration dec(
      String label, {
      IconData? icon,
      bool error = false,
      bool isPw = false,
      VoidCallback? toggle,
      bool obscure = false,
    }) {
      return InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: kSubText) : null,
        suffixIcon: isPw
            ? IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: kSubText,
                  size: 20,
                ),
                onPressed: toggle,
                splashRadius: 18,
              )
            : null,
        filled: true,
        fillColor: kCardBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: error ? kWarn : kBorderColor.withOpacity(0.7),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: error ? kWarn : kPrimaryLight,
            width: 2,
          ),
        ),
        errorText: null,
      );
    }

    Widget errRow(String msg) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: kWarn, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(color: kWarn, fontSize: 13.5, height: 1.2),
            ),
          ),
        ],
      ),
    );

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: !saving,
      barrierColor: Colors.black.withOpacity(0.35),
      barrierLabel: 'Change Password',
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, __, ___) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: Center(
              child: StatefulBuilder(
                builder: (ctx, setD) {
                  return Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      margin: EdgeInsets.fromLTRB(
                        18,
                        0,
                        18,
                        MediaQuery.of(ctx).viewInsets.bottom + 24,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 0,
                      ),
                      decoration: BoxDecoration(
                        color: kCardBg,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.10),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 28,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: kPrimaryLight.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  child: const Icon(
                                    Icons.lock_reset_rounded,
                                    color: kPrimaryLight,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Change Password',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: kText,
                                    fontFamily: 'Montserrat',
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: kSubText,
                                  ),
                                  onPressed: saving
                                      ? null
                                      : () => Navigator.pop(ctx),
                                  tooltip: 'Close',
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            if (genErr != null) ...[
                              errRow(genErr!),
                              const SizedBox(height: 10),
                            ],
                            // Current password
                            TextField(
                              controller: _currentPwController,
                              obscureText: _obscureCur,
                              onChanged: (_) => setD(() {
                                curErr = null;
                                genErr = null;
                              }),
                              decoration: dec(
                                'Current Password',
                                icon: Icons.lock_outline_rounded,
                                error: curErr != null,
                                isPw: true,
                                obscure: _obscureCur,
                                toggle: () =>
                                    setD(() => _obscureCur = !_obscureCur),
                              ),
                            ),
                            if (curErr != null) errRow(curErr!),
                            const SizedBox(height: 16),
                            // New password
                            TextField(
                              controller: _newPwController,
                              obscureText: _obscureNew,
                              onChanged: (_) => setD(() {
                                newErr = null;
                                genErr = null;
                              }),
                              decoration: dec(
                                'New Password',
                                icon: Icons.lock_rounded,
                                error: newErr != null,
                                isPw: true,
                                obscure: _obscureNew,
                                toggle: () =>
                                    setD(() => _obscureNew = !_obscureNew),
                              ),
                            ),
                            if (newErr != null) errRow(newErr!),
                            const SizedBox(height: 16),
                            // Confirm password
                            TextField(
                              controller: _confirmPwController,
                              obscureText: _obscureConf,
                              onChanged: (_) => setD(() {
                                confErr = null;
                                genErr = null;
                              }),
                              decoration: dec(
                                'Confirm New Password',
                                icon: Icons.lock_rounded,
                                error: confErr != null,
                                isPw: true,
                                obscure: _obscureConf,
                                toggle: () =>
                                    setD(() => _obscureConf = !_obscureConf),
                              ),
                            ),
                            if (confErr != null) errRow(confErr!),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: saving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.check_rounded,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                    label: Text(
                                      saving ? 'Saving...' : 'Save',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: Colors.white,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kPrimaryLight,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                    ),
                                    onPressed: saving
                                        ? null
                                        : () async {
                                            setD(() => saving = true);
                                            // Add your password change logic here, including validation and error handling.
                                            // Set curErr, newErr, confErr, genErr as needed, and setD(() => saving = false) when done.
                                          },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _showLogoutConfirmDialog() {
    return showGeneralDialog<bool>(
      context: context,
      barrierLabel: 'Logout',
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, __, ___) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: kWarn.withOpacity(0.35)),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 18,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: kWarn.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.logout, color: kWarn),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'Log out?',
                                    style: TextStyle(
                                      color: kText,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'You will be logged out of your account on this device. You can sign in again anytime.',
                                    style: TextStyle(
                                      color: kSubText,
                                      fontSize: 16,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              icon: const Icon(Icons.close, color: kSubText),
                              tooltip: 'Close',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: OutlinedButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    side: const BorderSide(
                                      color: kAccent,
                                      width: 1.5,
                                    ),
                                    foregroundColor: kAccent,
                                  ),
                                  child: const Text(
                                    'Stay logged in',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kWarn,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: const Text(
                                    'Log out',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _chooseImageSource() async {
    if (_uploadingImage) return;
    final source = await showModalBottomSheet<_PickSource>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            const Text(
              'Profile Photo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, _PickSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, _PickSource.gallery),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );

    if (source == null) return;

    switch (source) {
      case _PickSource.camera:
        await _capturePhoto();
        break;
      case _PickSource.gallery:
        await _pickFromGallery();
        break;
    }
  }

  Future<void> _capturePhoto() async {
    if (_uploadingImage) return;
    // Request camera permission
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (!mounted) return;
      _showTopPopup(
        'Camera permission denied',
        color: kWarn,
        icon: Icons.error_outline,
      );
    }
    try {
      final xFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 70,
      );
      if (xFile == null) return;
      final bytes = await xFile.readAsBytes();
      await _cropAndConfirm(
        bytes,
        originalFileName: 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
    } catch (e) {
      if (!mounted) return;
      _showTopPopup(
        'Camera error: $e',
        color: kWarn,
        icon: Icons.error_outline,
      );
    }
  }

  Future<void> _pickFromGallery() async {
    // ORIGINAL logic (moved from _pickAndCropImage)
    if (_uploadingImage) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null) return;
      final bytes = result.files.first.bytes;
      final name = result.files.first.name;
      if (bytes == null) throw Exception('No file bytes');

      await _cropAndConfirm(bytes, originalFileName: name);
    } catch (e) {
      if (!mounted) return;
      _showTopPopup(
        'Image selection failed: $e',
        color: kWarn,
        icon: Icons.error_outline,
      );
    }
  }

  Future<void> _cropAndConfirm(
    Uint8List bytes, {
    required String originalFileName,
  }) async {
    // Save temp file
    final tempDir = await getTemporaryDirectory();
    final originalPath = '${tempDir.path}/$originalFileName';
    final f = File(originalPath);
    await f.writeAsBytes(bytes);

    final crop = await ImageCropper().cropImage(
      sourcePath: originalPath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 92,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Photo',
          toolbarColor: kPrimary,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: kAccent,
          hideBottomControls: false,
          lockAspectRatio: false,
        ),
        IOSUiSettings(title: 'Crop Photo', aspectRatioLockEnabled: false),
      ],
    );
    if (crop == null) return;

    final croppedBytes = await File(crop.path).readAsBytes();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use this photo?'),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(croppedBytes, fit: BoxFit.cover, height: 220),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _uploadCroppedBytes(croppedBytes, extension: 'jpg');
    }
  }

  Future<void> _fetchUserProfile() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      setState(() => isLoading = false);
      return;
    }

    try {
      final response = await supabase
          .from('users')
          .select(
            'full_name, mobile_number, address, sex, email, dob, barangay, city, province, profile_url, birth_certificate_url, marriage_certificate_url, valid_id, proof_of_residency_url',
          )
          .eq('id', currentUser.id)
          .maybeSingle();

      final application = await supabase
          .from('applications')
          .select('dayung_unit_id, status, approved_at')
          .eq('user_id', currentUser.id)
          .eq('status', 'approved')
          .order('approved_at', ascending: false)
          .limit(1)
          .maybeSingle();

      Map<String, dynamic>? dayungUnit;
      final dayungId = application?['dayung_unit_id'] as int?;
      if (dayungId != null) {
        dayungUnit = await supabase
            .from('dayung_units')
            .select('id, name')
            .eq('id', dayungId)
            .maybeSingle();
      }

      if (!mounted) return;

      if (response == null) {
        setState(() {
          fullName = '';
          mobileNumber = '';
          address = '';
          sex = '';
          email = currentUser.email ?? '';
          dateOfBirth = null;
          barangay = null;
          city = null;
          province = null;
          activeDayungUnitId = null;
          activeDayungName = null;
          activeApplicationStatus = null;
          profileUrl = null;
          birthCertificateUrl = null;
          marriageCertificateUrl = null;
          validIdUrl = null;
          proofOfResidencyUrl = null;
          isLoading = false;
        });
        return;
      }

      setState(() {
        fullName = (response['full_name'] as String?)?.trim() ?? '';
        mobileNumber = (response['mobile_number'] as String?)?.trim() ?? '';
        address = (response['address'] as String?)?.trim() ?? '';
        sex = (response['sex'] as String?)?.trim() ?? '';
        email =
            (response['email'] as String?)?.trim() ?? currentUser.email ?? '';
        dateOfBirth = response['dob']?.toString();
        barangay = (response['barangay'] as String?)?.trim();
        city = (response['city'] as String?)?.trim();
        province = (response['province'] as String?)?.trim();
        activeDayungUnitId = dayungId;
        activeApplicationStatus = application?['status']?.toString();
        activeDayungName = dayungUnit?['name']?.toString();
        profileUrl = response['profile_url'] as String?;
        birthCertificateUrl = response['birth_certificate_url'] as String?;
        marriageCertificateUrl =
            response['marriage_certificate_url'] as String?;
        validIdUrl = response['valid_id'] as String?;
        proofOfResidencyUrl = response['proof_of_residency_url'] as String?;
        _fullNameController.text = fullName;
        _mobileController.text = mobileNumber;
        _addressController.text = address;
        _sexController.text = sex;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showTopPopup(
        'Failed to load profile: $e',
        color: kWarn,
        icon: Icons.error_outline,
      );
    }
  }

  String removeTitle(String name) {
    final titleRegex = RegExp(r'^(Mr\.|Mrs\.)\s', caseSensitive: false);
    return name.replaceAll(titleRegex, '').trim();
  }

  String _displayName() => removeTitle(fullName);

  String _displayDateOfBirth() {
    final raw = dateOfBirth?.trim();
    if (raw == null || raw.isEmpty) return 'Not provided';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  }

  String _displayLocationSummary() {
    final parts = [barangay, city, province]
        .where((part) => part != null && part.trim().isNotEmpty)
        .map((part) => part!.trim())
        .toList();
    if (parts.isNotEmpty) {
      return parts.join(', ');
    }
    return address.isNotEmpty ? address : 'Not provided';
  }

  void _toggleEditingMode() {
    if (_editing) {
      _fullNameController.text = fullName;
      _mobileController.text = mobileNumber;
      _addressController.text = address;
      _sexController.text = sex;
    }

    final nextEditing = !_editing;
    setState(() => _editing = nextEditing);

    if (nextEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final targetContext = _personalInfoKey.currentContext;
        if (targetContext == null) return;
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOutCubic,
          alignment: 0.08,
        );
      });
    }
  }

  String _maskedMobileNumber() {
    final value = mobileNumber.trim();
    if (value.isEmpty) return 'Not provided';

    final visiblePrefix = value.startsWith('+63') && value.length > 6 ? 4 : 3;
    final visibleSuffix = value.length - visiblePrefix > 2 ? 2 : 1;

    if (value.length <= visiblePrefix + visibleSuffix) {
      return '*' * value.length;
    }

    final hiddenLength = value.length - visiblePrefix - visibleSuffix;
    return '${value.substring(0, visiblePrefix)}${'*' * hiddenLength}${value.substring(value.length - visibleSuffix)}';
  }

  String _initialOf(String? name) {
    final t = (name ?? '').trim();
    if (t.isEmpty) return 'M';
    return t.characters.first.toUpperCase();
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
                    color: color.withOpacity(0.38),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.18),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.18),
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

    Future.delayed(const Duration(seconds: 5), () async {
      await animationController.reverse();
      entry.remove();
      animationController.dispose();
    });
  }

  Future<void> _uploadCroppedBytes(
    Uint8List bytes, {
    required String extension,
  }) async {
    setState(() => _uploadingImage = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      // 1. Delete previous profile image if it exists
      if (profileUrl != null && profileUrl!.isNotEmpty) {
        // Extract the file name from the URL
        final uri = Uri.parse(profileUrl!);
        final segments = uri.pathSegments;
        final fileName = segments.isNotEmpty ? segments.last : null;
        if (fileName != null && fileName.isNotEmpty) {
          await supabase.storage.from('avatars').remove([fileName]);
        }
        await _logAudit('Updated profile picture');
      }

      // 2. Upload new image
      final fileName =
          '$userId-${DateTime.now().millisecondsSinceEpoch}.$extension';

      await supabase.storage
          .from('avatars')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);

      final update = await supabase
          .from('users')
          .update({'profile_url': publicUrl})
          .eq('id', userId)
          .select()
          .maybeSingle();

      if (update == null) {
        throw Exception('Update failed');
      }

      if (!mounted) return;
      setState(() {
        profileUrl = publicUrl;
        _uploadingImage = false;
      });
      ScaffoldMessenger.of(context);
      _showTopPopup('Profile photo updated');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      ScaffoldMessenger.of(context);
      _showTopPopup(
        'Upload error: $e',
        color: kWarn,
        icon: Icons.error_outline,
      );
    }
  }

  void _openProfilePreview() {
    if (profileUrl == null || profileUrl!.isEmpty) return;
    showGeneralDialog(
      context: context,
      barrierLabel: 'Profile Photo',
      barrierDismissible: true,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, a1, a2, child) {
        final scale = Curves.easeOutCubic.transform(a1.value);
        return Opacity(
          opacity: a1.value,
          child: Transform.scale(
            scale: scale,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Stack(
                children: [
                  Center(
                    child: Hero(
                      tag: 'profilePhotoHero',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: InteractiveViewer(
                          clipBehavior: Clip.none,
                          minScale: 0.7,
                          maxScale: 4,
                          child: Image.network(
                            profileUrl!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 40,
                    right: 20,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 32,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 260),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final userId = supabase.auth.currentUser!.id;
      final updated = {
        'full_name': AppInputSecurity.sanitizePlainText(
          _fullNameController.text,
          maxLength: 120,
        ),
        'mobile_number': AppInputSecurity.sanitizePhone(_mobileController.text),
        'address': AppInputSecurity.sanitizePlainText(
          _addressController.text,
          maxLength: 200,
        ),
        'sex': _sexController.text.trim(),
        'profile_url': profileUrl,
      };

      final res = await supabase
          .from('users')
          .update(updated)
          .eq('id', userId)
          .select();

      if (!mounted) return;
      if (res.isEmpty) {
        _showTopPopup(
          'No profile found to update',
          color: kWarn,
          icon: Icons.error_outline,
        );
      } else {
        final row = res.first;
        setState(() {
          fullName = (row['full_name'] ?? '').toString();
          mobileNumber = (row['mobile_number'] ?? '').toString();
          address = (row['address'] ?? '').toString();
          sex = (row['sex'] ?? '').toString();
          profileUrl = (row['profile_url'] ?? profileUrl)?.toString();
          _editing = false;
        });
        _showTopPopup('Profile updated successfully');
      }
    } catch (e) {
      if (!mounted) return;
      _showTopPopup(
        'Error updating profile: $e',
        color: kWarn,
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    await _logAudit('Updated profile information');
  }

  Future<void> _confirmLogout() async {
    final ok = await _showLogoutConfirmDialog();
    if (ok == true) {
      await Supabase.instance.client.auth.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('selectedDayungUnit');
      await prefs.remove('selectedDayungUnitData');

      try {
        if (mounted) {
          context.read<DayungUnitProvider>().clear();
        }
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Login()),
        (route) => false,
      );
    }
  }

  Future<void> handleLogout(BuildContext context) async {
    setState(() => _loggingOut = true);
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selectedDayungUnit');
    await prefs.remove('selectedDayungUnitData');

    try {
      context.read<DayungUnitProvider>().clear();
    } catch (_) {}
    try {
      await context.read<DayungRoleProvider>().refreshRoles(null);
    } catch (_) {}

    if (!context.mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      setState(() => _loggingOut = false);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Login()),
        (route) => false,
      );
    });
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kSubText),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeBg = isDark ? const Color(0xFF18181B) : const Color(0xFFF8FAFC);
    final themeCard = isDark ? const Color(0xFF23232A) : Colors.white;
    final themeText = isDark ? Colors.white : const Color(0xFF111827);
    final themeSubText = isDark ? Colors.white70 : kSubText;
    final themeField = isDark ? const Color(0xFF23232A) : Colors.white;
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 700;

    if (isLoading) {
      return DayungLoadingScaffold(
        layout: DayungSkeletonLayout.profile,
        backgroundColor: themeBg,
      );
    }

    return Scaffold(
      backgroundColor: themeBg,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFFEAF3FF), themeBg],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildModernHeader(context, isWide),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: themeCard,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 18,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isWide ? 760 : double.infinity,
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildModernProfileSection(
                                themeCard,
                                themeText,
                                themeSubText,
                              ),
                              const SizedBox(height: 18),
                              Container(
                                key: _personalInfoKey,
                                padding: const EdgeInsets.all(22),
                                decoration: BoxDecoration(
                                  color: themeCard,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: kBorderColor.withOpacity(0.75),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _editing
                                          ? 'Update Profile Details'
                                          : 'Personal Information',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: themeText,
                                        fontFamily: 'Montserrat',
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _editing
                                          ? 'Review your information carefully before saving changes.'
                                          : 'Your important account details are shown here in a simple and easy-to-read format.',
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.45,
                                        color: themeSubText,
                                        fontFamily: 'OpenSans',
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    _buildProfileFields(
                                      themeCard,
                                      themeText,
                                      themeSubText,
                                      themeField,
                                    ),
                                    const SizedBox(height: 18),
                                    if (_editing)
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          icon: _saving
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        color: Colors.white,
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.save_rounded,
                                                  color: Colors.white,
                                                ),
                                          label: Text(
                                            _saving
                                                ? 'Saving...'
                                                : 'Save Changes',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 17,
                                              fontFamily: 'Montserrat',
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: kAccentDark,
                                            foregroundColor: Colors.white,
                                            minimumSize: const Size.fromHeight(
                                              56,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                            elevation: 0,
                                          ),
                                          onPressed: _saving
                                              ? null
                                              : _saveProfile,
                                        ),
                                      ),
                                    if (!_editing) ...[
                                      const SizedBox(height: 10),
                                      _buildActionButtons(),
                                    ],
                                  ],
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
            ],
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.dashboard_rounded, color: Colors.white),
            label: const Text(
              'Dashboard',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                fontFamily: 'Montserrat',
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryLight,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
    );
  }

  Widget _buildModernProfileSection(
    Color themeCard,
    Color themeText,
    Color themeSubText,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kBorderColor.withOpacity(0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(44),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: _buildProfileAvatar(themeCard),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName().isNotEmpty ? _displayName() : 'Your name',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: themeText,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      activeDayungName ?? 'No approved Dayung unit yet',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: themeSubText,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Column(
            children: [
              _buildSummaryInfoRow(
                icon: Icons.badge_rounded,
                label: 'Dayung Unit',
                value: activeDayungName ?? 'No approved unit yet',
              ),
              _buildSummaryInfoRow(
                icon: Icons.alternate_email_rounded,
                label: 'Email Address',
                value: email.isNotEmpty ? email : 'Not provided',
              ),
              _buildSummaryInfoRow(
                icon: Icons.phone_rounded,
                label: 'Mobile Number',
                value: mobileNumber.isNotEmpty
                    ? _maskedMobileNumber()
                    : 'Not provided',
              ),
              _buildSummaryInfoRow(
                icon: Icons.home_rounded,
                label: 'Address',
                value: _displayLocationSummary(),
              ),
              _buildSummaryInfoRow(
                icon: Icons.cake_rounded,
                label: 'Date of Birth',
                value: _displayDateOfBirth(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_user_rounded,
                  color: kPrimaryLight,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _editing
                        ? 'Editing mode is active. Review your details before saving.'
                        : 'Sensitive details like your mobile number are partially hidden for privacy.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: themeText,
                      fontFamily: 'OpenSans',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorderColor.withOpacity(0.9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: kPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kSubText,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: kText,
                    fontFamily: 'OpenSans',
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernHeader(BuildContext context, bool isWide) {
    return SafeArea(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12, left: 12, right: 12, bottom: 8),
        padding: EdgeInsets.symmetric(
          horizontal: isWide ? 28 : 18,
          vertical: isWide ? 24 : 18,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kPrimaryLight, kAccentDark],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  // child: IconButton(
                  //   onPressed: () => Navigator.of(context).maybePop(),
                  //   icon: const Icon(
                  //     Icons.arrow_back_ios_new_rounded,
                  //     color: Colors.white,
                  //   ),
                  // ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'My Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: isWide ? 28 : 22,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Simple account details in one place.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.88),
                          fontSize: isWide ? 14 : 12,
                          height: 1.4,
                          fontFamily: 'OpenSans',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: Icon(
                    _editing ? Icons.close_rounded : Icons.edit_rounded,
                    size: 17,
                    color: Colors.white,
                  ),
                  label: Text(
                    _editing ? 'Cancel' : 'Edit',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _editing
                        ? kWarn
                        : const Color.fromARGB(255, 11, 101, 73),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(112, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _toggleEditingMode,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _editing
                          ? 'You can now update your details. Tap your photo if you want to change it.'
                          : 'Review your profile details below.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.94),
                        fontSize: 12,
                        height: 1.4,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileAvatar(Color themeCard) {
    return GestureDetector(
      onTap: _editing ? _chooseImageSource : _openProfilePreview,
      child: Hero(
        tag: 'profilePhotoHero',
        child: CircleAvatar(
          radius: 40,
          backgroundColor: themeCard,
          backgroundImage: (profileUrl != null && profileUrl!.isNotEmpty)
              ? NetworkImage(profileUrl!)
              : null,
          child: (profileUrl == null || profileUrl!.isEmpty)
              ? Text(
                  _initialOf(_displayName()),
                  style: const TextStyle(
                    color: kPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Montserrat',
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildProfileFields(
    Color themeCard,
    Color themeText,
    Color themeSubText,
    Color themeField,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Profile Details',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: themeText,
            fontFamily: 'Montserrat',
          ),
        ),
        const SizedBox(height: 14),
        _buildSimpleField(
          icon: Icons.person_rounded,
          label: 'Full Name',
          value: _displayName(),
          editingChild: TextFormField(
            controller: _fullNameController,
            textCapitalization: TextCapitalization.words,
            inputFormatters: AppInputSecurity.singleLineFormatters(
              maxLength: 120,
            ),
            validator: (v) => AppInputSecurity.validateSafeText(
              v,
              fieldName: 'Full name',
              minLength: 2,
              maxLength: 120,
            ),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: themeText,
            ),
            decoration: _fieldDecoration(
              'Enter full name',
            ).copyWith(filled: true, fillColor: themeField),
          ),
          themeCard: themeCard,
          themeText: themeText,
          themeSubText: themeSubText,
        ),
        _buildSimpleField(
          icon: Icons.location_on_rounded,
          label: 'Address',
          value: address.isNotEmpty ? address : 'Not provided',
          editingChild: TextFormField(
            controller: _addressController,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: AppInputSecurity.singleLineFormatters(
              maxLength: 200,
            ),
            validator: (v) => AppInputSecurity.validateSafeText(
              v,
              fieldName: 'Address',
              minLength: 6,
              maxLength: 200,
            ),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: themeText,
            ),
            decoration: _fieldDecoration(
              'Enter address',
            ).copyWith(filled: true, fillColor: themeField),
          ),
          themeCard: themeCard,
          themeText: themeText,
          themeSubText: themeSubText,
        ),
        _buildSimpleField(
          icon: Icons.phone_rounded,
          label: 'Mobile Number',
          value: _maskedMobileNumber(),
          editingChild: TextFormField(
            controller: _mobileController,
            keyboardType: TextInputType.phone,
            inputFormatters: AppInputSecurity.phoneFormatters(),
            validator: (v) {
              final err = AppInputSecurity.validatePhone(v);
              if (err != null) return err;
              final t = AppInputSecurity.sanitizePhone(
                v ?? '',
              ).replaceAll('+', '');
              if (t.length < 10) return 'Enter a valid number';
              return null;
            },
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: themeText,
            ),
            decoration: _fieldDecoration(
              'Enter mobile number',
            ).copyWith(filled: true, fillColor: themeField),
          ),
          themeCard: themeCard,
          themeText: themeText,
          themeSubText: themeSubText,
        ),
        _buildSimpleField(
          icon: Icons.person_outline_rounded,
          label: 'Sex',
          value: sex.isNotEmpty ? sex : 'Not provided',
          editingChild: DropdownButtonFormField2<String>(
            isExpanded: true,
            value: (_sexController.text.isNotEmpty
                ? _sexController.text
                : null),
            decoration: _fieldDecoration(
              'Select sex',
            ).copyWith(filled: true, fillColor: themeField),
            // Selected value (in the field) style
            style: TextStyle(
              color: themeText,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            // Dropdown list items (white), same as register/addbeneficiary
            items: const ['Male', 'Female', 'Prefer not to say']
                .map(
                  (s) => DropdownMenuItem<String>(
                    value: s,
                    child: Text(
                      s,
                      style: const TextStyle(
                        color: Colors.white, // list text
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
                .toList(),
            // Field shows icon + black text (like register.dart)
            selectedItemBuilder: (context) =>
                ['Male', 'Female', 'Prefer not to say']
                    .map(
                      (s) => Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (s == 'Male')
                              Icon(Icons.male, color: Colors.blue[700])
                            else if (s == 'Female')
                              Icon(Icons.female, color: Colors.pink[400])
                            else
                              const Icon(Icons.person_outline, color: kSubText),
                            const SizedBox(width: 8),
                            Text(
                              s,
                              style: TextStyle(
                                color: themeText, // field text
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
            onChanged: (val) => _sexController.text = val ?? '',
            validator: (_) => null,
          ),
          themeCard: themeCard,
          themeText: themeText,
          themeSubText: themeSubText,
        ),
      ],
    );
  }

  Widget _buildSimpleField({
    required IconData icon,
    required String label,
    required String value,
    required Widget editingChild,
    required Color themeCard,
    required Color themeText,
    required Color themeSubText,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(0),
      decoration: BoxDecoration(
        color: _editing ? themeCard : kCardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _editing
              ? kPrimaryLight.withOpacity(0.18)
              : kBorderColor.withOpacity(0.7),
          width: 1,
        ),
        boxShadow: [
          if (!_editing)
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: kPrimary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 16, color: kPrimary),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: themeText,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _editing
                ? editingChild
                : Text(
                    value,
                    style: TextStyle(
                      color: themeSubText,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeButtonBeneficiary = isDark ? kAccentDark : kSuccess;
    final themeButtonChangePw = isDark ? kAccentDark : kPrimaryLight;
    final textColor = Colors.white;

    if (_editing) {
      return Container(
        width: double.infinity,
        height: 44,
        decoration: BoxDecoration(
          color: themeButtonBeneficiary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ElevatedButton(
          onPressed: _saving ? null : _saveProfile,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
          child: _saving
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Save Changes',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontFamily: 'Montserrat',
                  ),
                ),
        ),
      );
    } else {
      return Consumer<DayungRoleProvider>(
        builder: (_, roles, __) {
          return Column(
            children: [
              if (roles.isPresident)
                _buildActionButton(
                  icon: Icons.rule_rounded,
                  label: 'User Preferences',
                  color: Colors.indigo,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ManageRulesPagePres(),
                      ),
                    );
                  },
                  textColor: Colors.white,
                ),
              const SizedBox(height: 8),
              if (roles.isPresident)
                _buildActionButton(
                  icon: Icons.assignment_turned_in_rounded,
                  label: 'RULES',
                  color: Colors.deepPurple,
                  onTap: () {
                    final user = Supabase.instance.client.auth.currentUser;
                    debugPrint(
                      'Required Applications button clicked by user: ${user?.id} (${user?.email})',
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RequiredApplicationsPage(),
                      ),
                    );
                  },
                  textColor: Colors.white,
                ),
              if (roles.isPresident) const SizedBox(height: 8),

              const SizedBox(height: 10),

              _buildActionButton(
                icon: Icons.lock_reset_rounded,
                label: 'Change Password',
                color: themeButtonChangePw,
                onTap: _openChangePasswordDialog,
                textColor: textColor,
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      );
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    Widget? trailing,
    Color textColor = Colors.white,
  }) {
    return Container(
      width: double.infinity,
      height: 44,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ElevatedButton.icon(
        icon: Icon(icon, color: textColor, size: 16),
        label: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
                fontFamily: 'Montserrat',
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing],
          ],
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        onPressed: onTap,
      ),
    );
  }
}

enum _PickSource { camera, gallery }
