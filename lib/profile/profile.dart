import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:capstone_app/Auth/login.dart' hide kWarn, kDanger;
import 'package:capstone_app/President/manage_rules.dart'
    hide kPrimary, kAccent;
import 'package:capstone_app/Providers/dayung_provider.dart';
import 'package:capstone_app/Providers/dayung_role_provider.dart';
import 'package:capstone_app/profile/required_application_page.dart'
    hide kAccent;
import 'package:capstone_app/SuperAdmin/superadmin_support.dart';
import 'package:capstone_app/ui/loading/page_skeleton.dart';
import 'package:capstone_app/utils/input_safety.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kText = Color(0xFF1F2937);
const kSubText = Color(0xFF4B5563);
const kPrimaryLight = Color(0xFF0D47A1);
const kAccentDark = Color(0xFF0D47A1);
const kCardBg = Color(0xFFFFFFFF);
const kBorderColor = Color(0xFFE5E7EB);
const kSurface = Color(0xFFF8FAFC);
const kSuccess = Color(0xFF10B981);
const kWarn = Color(0xFFF57C00);
const kDanger = Color(0xFFC62828);

class ProfilePage extends StatefulWidget {
  final VoidCallback? onBack;
  final bool showBackButton;

  const ProfilePage({super.key, this.onBack, this.showBackButton = false});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
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
  String? validIdUrl;
  String? proofOfResidencyUrl;

  bool _obscureCur = true;
  bool _obscureNew = true;
  bool _obscureConf = true;
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

  Future<void> _logAudit(
    String eventName, {
    Map<String, dynamic>? fields,
  }) async {
    await logAuditEvent(eventName, fields: fields);
  }

  Future<void> _fetchUserProfile() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      if (mounted) setState(() => isLoading = false);
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
    Color color = kAccentDark,
    IconData icon = Icons.check_circle,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    final animationController = AnimationController(
      vsync: this,
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
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
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

    Future.delayed(const Duration(seconds: 4), () async {
      await animationController.reverse();
      entry.remove();
      animationController.dispose();
    });
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

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            InputDecoration fieldDecoration(
              String label, {
              bool error = false,
              bool isPw = false,
              VoidCallback? toggle,
              bool obscure = false,
            }) {
              return InputDecoration(
                labelText: label,
                filled: true,
                fillColor: kSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: error ? kWarn : kBorderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: error ? kWarn : kPrimaryLight,
                    width: 1.6,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                suffixIcon: isPw
                    ? IconButton(
                        onPressed: toggle,
                        icon: Icon(
                          obscure
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 20,
                          color: kSubText,
                        ),
                      )
                    : null,
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
              contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              title: const Text(
                'Change Password',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (genErr != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: kDanger.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: kDanger,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  genErr ?? '',
                                  style: const TextStyle(
                                    color: kDanger,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      TextField(
                        controller: _currentPwController,
                        obscureText: _obscureCur,
                        decoration: fieldDecoration(
                          'Current password',
                          error: curErr != null,
                          isPw: true,
                          toggle: () =>
                              setStateDialog(() => _obscureCur = !_obscureCur),
                          obscure: _obscureCur,
                        ),
                      ),
                      if (curErr != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            curErr ?? '',
                            style: const TextStyle(color: kWarn, fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _newPwController,
                        obscureText: _obscureNew,
                        decoration: fieldDecoration(
                          'New password',
                          error: newErr != null,
                          isPw: true,
                          toggle: () =>
                              setStateDialog(() => _obscureNew = !_obscureNew),
                          obscure: _obscureNew,
                        ),
                      ),
                      if (newErr != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            newErr ?? '',
                            style: const TextStyle(color: kWarn, fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirmPwController,
                        obscureText: _obscureConf,
                        decoration: fieldDecoration(
                          'Confirm password',
                          error: confErr != null,
                          isPw: true,
                          toggle: () => setStateDialog(
                            () => _obscureConf = !_obscureConf,
                          ),
                          obscure: _obscureConf,
                        ),
                      ),
                      if (confErr != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            confErr ?? '',
                            style: const TextStyle(color: kWarn, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setStateDialog(() => saving = true);
                          curErr = null;
                          newErr = null;
                          confErr = null;
                          genErr = null;

                          if (_currentPwController.text.isEmpty) {
                            curErr = 'Please enter your current password.';
                          }
                          if (_newPwController.text.length < 6) {
                            newErr = 'Password must be at least 6 characters.';
                          }
                          if (_confirmPwController.text !=
                              _newPwController.text) {
                            confErr = 'Passwords do not match.';
                          }
                          if (curErr != null ||
                              newErr != null ||
                              confErr != null) {
                            setStateDialog(() => saving = false);
                            return;
                          }

                          try {
                            await supabase.auth.updateUser(
                              UserAttributes(password: _newPwController.text),
                            );
                            if (mounted && context.mounted) {
                              _showTopPopup('Password updated successfully');
                              Navigator.pop(dialogContext);
                            }
                          } catch (e) {
                            genErr = 'Unable to update password: $e';
                          } finally {
                            if (mounted) setStateDialog(() => saving = false);
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
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
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (!mounted) return;
      _showTopPopup(
        'Camera permission denied',
        color: kWarn,
        icon: Icons.error_outline,
      );
      return;
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
          toolbarColor: kPrimaryLight,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: kAccentDark,
          hideBottomControls: false,
          lockAspectRatio: false,
        ),
        IOSUiSettings(title: 'Crop Photo', aspectRatioLockEnabled: false),
      ],
    );
    if (crop == null) return;

    final croppedBytes = await File(crop.path).readAsBytes();
    if (!mounted) return;

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
              backgroundColor: kAccentDark,
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

  Future<void> _uploadCroppedBytes(
    Uint8List bytes, {
    required String extension,
  }) async {
    setState(() => _uploadingImage = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      if (profileUrl != null && profileUrl!.isNotEmpty) {
        final uri = Uri.parse(profileUrl!);
        final segments = uri.pathSegments;
        final fileName = segments.isNotEmpty ? segments.last : null;
        if (fileName != null && fileName.isNotEmpty) {
          await supabase.storage.from('avatars').remove([fileName]);
        }
      }

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
      await _logAudit(
        'USER_ACTIVITY_PROFILE_PICTURE_UPDATED',
        fields: {'source': 'profile_page'},
      );
      if (!mounted) return;
      _showTopPopup('Profile photo updated');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
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
                        borderRadius: BorderRadius.circular(20),
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
        await _logAudit(
          'USER_ACTIVITY_PROFILE_UPDATED',
          fields: {'source': 'profile_page'},
        );
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
  }

  Future<void> handleLogout(BuildContext context) async {
    final dayungUnitProvider = context.read<DayungUnitProvider>();
    final dayungRoleProvider = context.read<DayungRoleProvider>();
    await logAuditEvent(
      'USER_ACTIVITY_SIGN_OUT',
      fields: {'source': 'profile_page'},
    );
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selectedDayungUnit');
    await prefs.remove('selectedDayungUnitData');

    if (!context.mounted) return;

    try {
      dayungUnitProvider.clear();
    } catch (_) {}
    try {
      await dayungRoleProvider.refreshRoles(null);
    } catch (_) {}

    if (!context.mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
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
      filled: true,
      fillColor: kSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kBorderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: kPrimaryLight, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeBg = isDark ? const Color(0xFF18181B) : const Color(0xFFFAFAF7);
    final themeCard = isDark ? const Color(0xFF23232A) : kCardBg;
    final themeText = isDark ? Colors.white : kText;
    final themeSubText = isDark ? Colors.white70 : kSubText;
    final themeField = isDark ? const Color(0xFF23232A) : kSurface;
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
      body: SafeArea(
        child: Column(
          children: [
            _buildModernHeader(context, isWide),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  isWide ? 24 : 16,
                  16,
                  isWide ? 24 : 16,
                  24,
                ),
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
                          _buildProfileHero(themeCard, themeText, themeSubText),
                          const SizedBox(height: 16),
                          _buildProfileFields(
                            themeCard,
                            themeText,
                            themeSubText,
                            themeField,
                          ),
                          const SizedBox(height: 16),
                          _buildActionButtons(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernHeader(BuildContext context, bool isWide) {
    final showBackButton = widget.showBackButton && widget.onBack != null;
    return Container(
      padding: EdgeInsets.fromLTRB(
        30,
        isWide ? 36 : 28,
        isWide ? 24 : 16,
        isWide ? 32 : 24,
      ),
      decoration: const BoxDecoration(
        color: kPrimaryLight,
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
          if (showBackButton)
            IconButton(
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 26,
              ),
              onPressed: widget.onBack,
            ),
          if (showBackButton) const SizedBox(width: 16),
          Expanded(
            child: Text(
              'My Profile',
              style: TextStyle(
                fontSize: isWide ? 24 : 17,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontFamily: 'Montserrat',
                letterSpacing: 0.3,
              ),
            ),
          ),
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
                fontSize: 13,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _editing ? kWarn : kAccentDark,
              foregroundColor: Colors.white,
              minimumSize: const Size(96, 42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            onPressed: _toggleEditingMode,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHero(
    Color themeCard,
    Color themeText,
    Color themeSubText,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: themeCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kBorderColor.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _editing ? _chooseImageSource : _openProfilePreview,
                child: Hero(
                  tag: 'profilePhotoHero',
                  child: CircleAvatar(
                    radius: 42,
                    backgroundColor: kPrimaryLight.withValues(alpha: 0.12),
                    backgroundImage:
                        (profileUrl != null && profileUrl!.isNotEmpty)
                        ? NetworkImage(profileUrl!)
                        : null,
                    child: (profileUrl == null || profileUrl!.isEmpty)
                        ? Text(
                            _initialOf(_displayName()),
                            style: const TextStyle(
                              color: kPrimaryLight,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Montserrat',
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AutoSizeText(
                      _displayName().isNotEmpty ? _displayName() : 'Your name',
                      maxLines: 2,
                      minFontSize: 16,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: themeText,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      activeDayungName ?? 'No approved Dayung unit yet',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: themeSubText,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: kPrimaryLight.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _editing
                            ? 'Editing mode is active'
                            : 'Profile is ready',
                        style: const TextStyle(
                          color: kPrimaryLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Email',
                  email.isNotEmpty ? email : 'Not provided',
                  Icons.email_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSummaryCard(
                  'Phone',
                  mobileNumber.isNotEmpty
                      ? _maskedMobileNumber()
                      : 'Not provided',
                  Icons.phone_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildSummaryRow(
            Icons.badge_rounded,
            'Dayung Unit',
            activeDayungName ?? 'No approved unit yet',
          ),
          _buildSummaryRow(
            Icons.home_rounded,
            'Address',
            _displayLocationSummary(),
          ),
          _buildSummaryRow(
            Icons.cake_rounded,
            'Date of Birth',
            _displayDateOfBirth(),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorderColor.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: kPrimaryLight),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: kSubText,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: kText,
              fontFamily: 'OpenSans',
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(IconData icon, String label, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorderColor.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kPrimaryLight.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: kPrimaryLight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: kSubText,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
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

  Widget _buildProfileFields(
    Color themeCard,
    Color themeText,
    Color themeSubText,
    Color themeField,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: themeCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kBorderColor.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        key: _personalInfoKey,
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
            editingChild: DropdownButtonFormField<String>(
              initialValue: _sexController.text.isNotEmpty
                  ? _sexController.text
                  : null,
              decoration: _fieldDecoration(
                'Select sex',
              ).copyWith(filled: true, fillColor: themeField),
              items: const [
                'Male',
                'Female',
                'Prefer not to say',
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (val) => _sexController.text = val ?? '',
            ),
            themeCard: themeCard,
            themeText: themeText,
            themeSubText: themeSubText,
          ),
        ],
      ),
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
        color: _editing ? themeCard : kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _editing
              ? kPrimaryLight.withValues(alpha: 0.18)
              : kBorderColor.withValues(alpha: 0.45),
        ),
        boxShadow: [
          _editing
              ? const BoxShadow(
                  color: Colors.transparent,
                  blurRadius: 0,
                  offset: Offset(0, 0),
                )
              : BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: kPrimaryLight.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 16, color: kPrimaryLight),
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
    if (_editing) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kAccentDark.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kAccentDark.withValues(alpha: 0.16)),
        ),
        child: ElevatedButton(
          onPressed: _saving ? null : _saveProfile,
          style: ElevatedButton.styleFrom(
            backgroundColor: kAccentDark,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
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
    }

    return Consumer<DayungRoleProvider>(
      builder: (_, roles, __) {
        return Column(
          children: [
            if (roles.isPresident)
              _buildActionButton(
                icon: Icons.rule_rounded,
                label: 'ferences',
                color: const Color(0xFF4338CA),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ManageRulesPagePres(),
                  ),
                ),
              ),
            if (roles.isPresident) const SizedBox(height: 8),
            if (roles.isPresident)
              _buildActionButton(
                icon: Icons.assignment_turned_in_rounded,
                label: 'RULES',
                color: const Color(0xFF7C3AED),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RequiredApplicationsPage(),
                  ),
                ),
              ),
            if (roles.isPresident) const SizedBox(height: 8),
            _buildActionButton(
              icon: Icons.lock_reset_rounded,
              label: 'Change Password',
              color: kPrimaryLight,
              onTap: _openChangePasswordDialog,
            ),
            const SizedBox(height: 8),
            // _buildActionButton(
            //   icon: Icons.logout_rounded,
            //   label: 'Logout',
            //   color: const Color(0xFFEF4444),
            //   onTap: () => handleLogout(context),
            // ),
          ],
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Container(
      width: double.infinity,
      height: 48,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ElevatedButton.icon(
        icon: Icon(icon, color: Colors.white, size: 16),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontFamily: 'Montserrat',
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        onPressed: onTap,
      ),
    );
  }
}

enum _PickSource { camera, gallery }
