import 'dart:io';
import 'dart:typed_data';

import 'package:capstone_app/Auth/login.dart';
import 'package:capstone_app/Beneficiary/beneficiary.dart';
import 'package:capstone_app/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

// Senior-friendly color palette (high contrast, softer tones)
const kBg = Color(0xFFFAFAF7); // warm off-white
const kText = Color(0xFF1F2937); // dark neutral
const kSubText = Color(0xFF4B5563); // softer dark gray
const kPrimary = Color(0xFF2F4F4F); // dark slate gray (headers)
const kAccent = Color(0xFF3E8E7E); // muted teal (buttons)
const kAccentDark = Color(0xFF2D6F63); // darker teal (pressed)
const kWarn = Color(0xFFB71C1C); // dark red (logout border)

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
  final ImagePicker _imagePicker = ImagePicker();

  final _currentPwController = TextEditingController();
  final _newPwController = TextEditingController();
  final _confirmPwController = TextEditingController();
  bool _obscureCur = true;
  bool _obscureNew = true;
  bool _obscureConf = true;

  String fullName = '';
  String mobileNumber = '';
  String address = '';
  String sex = '';
  String? profileUrl;
  String? birthCertificateUrl;
  String? marriageCertificateUrl;

  bool isLoading = true;
  bool _editing = false;
  bool _saving = false;
  bool _uploadingImage = false;

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

  void _openCertificate(String url) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Certificate'),
        content: url.endsWith('.pdf')
            ? Text('Open this PDF in browser?')
            : Image.network(url, fit: BoxFit.contain, height: 300),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (url.endsWith('.pdf'))
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                launchUrl(Uri.parse(url));
              },
              child: const Text('Open PDF'),
            ),
        ],
      ),
    );
  }

  Widget _certificateRow({
    required String label,
    required String? url,
    required VoidCallback onUpload,
    required VoidCallback onView,
  }) {
    return Row(
      children: [
        Icon(
          url != null && url.isNotEmpty
              ? Icons.check_circle
              : Icons.warning_amber_rounded,
          color: url != null && url.isNotEmpty ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        if (url != null && url.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.open_in_new, color: kAccent),
            tooltip: 'View',
            onPressed: () => _openCertificate(url),
          )
        else
          ElevatedButton.icon(
            icon: const Icon(Icons.upload_file),
            label: const Text('Add'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: onUpload,
          ),
      ],
    );
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

    InputDecoration _dec(String label, {IconData? icon, bool error = false}) {
      return InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: kSubText) : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: error ? kWarn : const Color(0xFFE5E7EB),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: error ? kWarn : kAccent, width: 2),
        ),
        errorText: null, // we render custom error rows below
      );
    }

    Widget _errRow(String msg) => Padding(
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
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Container(
                        margin: EdgeInsets.fromLTRB(
                          24,
                          0,
                          24,
                          MediaQuery.of(ctx).viewInsets.bottom + 24,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: (genErr != null ? kWarn : Colors.black12)
                                .withOpacity(0.45),
                          ),
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
                            // Title
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: kAccent.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.lock_reset,
                                    color: kAccent,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Change Password',
                                    style: TextStyle(
                                      color: kText,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: saving
                                      ? null
                                      : () => Navigator.of(ctx).pop(),
                                  icon: const Icon(
                                    Icons.close,
                                    color: kSubText,
                                  ),
                                  tooltip: 'Close',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // General error (e.g., offline)
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              child: genErr == null
                                  ? const SizedBox.shrink()
                                  : _errRow(genErr!),
                            ),
                            if (genErr != null) const SizedBox(height: 8),

                            // Current password
                            TextField(
                              controller: _currentPwController,
                              obscureText: _obscureCur,
                              onChanged: (_) => setD(() {
                                curErr = null;
                                genErr = null;
                              }),
                              decoration:
                                  _dec(
                                    'Current password',
                                    icon: Icons.lock_outline,
                                    error: curErr != null,
                                  ).copyWith(
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureCur
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: kSubText,
                                      ),
                                      onPressed: () => setD(
                                        () => _obscureCur = !_obscureCur,
                                      ),
                                    ),
                                  ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              child: curErr == null
                                  ? const SizedBox.shrink()
                                  : _errRow(curErr!),
                            ),
                            const SizedBox(height: 12),

                            // New password
                            TextField(
                              controller: _newPwController,
                              obscureText: _obscureNew,
                              onChanged: (_) => setD(() {
                                newErr = null;
                                genErr = null;
                              }),
                              decoration:
                                  _dec(
                                    'New password (min 6 chars)',
                                    icon: Icons.password_outlined,
                                    error: newErr != null,
                                  ).copyWith(
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureNew
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: kSubText,
                                      ),
                                      onPressed: () => setD(
                                        () => _obscureNew = !_obscureNew,
                                      ),
                                    ),
                                  ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              child: newErr == null
                                  ? const SizedBox.shrink()
                                  : _errRow(newErr!),
                            ),
                            const SizedBox(height: 12),

                            // Confirm password
                            TextField(
                              controller: _confirmPwController,
                              obscureText: _obscureConf,
                              onChanged: (_) => setD(() {
                                confErr = null;
                                genErr = null;
                              }),
                              decoration:
                                  _dec(
                                    'Confirm new password',
                                    icon: Icons.lock_person_outlined,
                                    error: confErr != null,
                                  ).copyWith(
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureConf
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: kSubText,
                                      ),
                                      onPressed: () => setD(
                                        () => _obscureConf = !_obscureConf,
                                      ),
                                    ),
                                  ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              child: confErr == null
                                  ? const SizedBox.shrink()
                                  : _errRow(confErr!),
                            ),
                            const SizedBox(height: 16),

                            // Actions
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 48,
                                    child: OutlinedButton(
                                      onPressed: saving
                                          ? null
                                          : () => Navigator.of(ctx).pop(),
                                      style: OutlinedButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        side: const BorderSide(
                                          color: kAccent,
                                          width: 1.5,
                                        ),
                                        foregroundColor: kAccent,
                                      ),
                                      child: const Text(
                                        'Cancel',
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
                                      onPressed: saving
                                          ? null
                                          : () async {
                                              // Clear previous errors
                                              setD(() {
                                                curErr = null;
                                                newErr = null;
                                                confErr = null;
                                                genErr = null;
                                              });

                                              final cur = _currentPwController
                                                  .text
                                                  .trim();
                                              final npw = _newPwController.text
                                                  .trim();
                                              final cnpw = _confirmPwController
                                                  .text
                                                  .trim();

                                              // Client-side validation
                                              if (cur.isEmpty)
                                                curErr =
                                                    'Current password is required';
                                              if (npw.isEmpty)
                                                newErr =
                                                    'New password is required';
                                              if (npw.isNotEmpty &&
                                                  npw.length < 6)
                                                newErr =
                                                    'New password must be at least 6 characters';
                                              if (cnpw.isEmpty)
                                                confErr =
                                                    'Please confirm your new password';
                                              if (npw.isNotEmpty &&
                                                  cnpw.isNotEmpty &&
                                                  npw != cnpw) {
                                                confErr =
                                                    'New passwords do not match';
                                              }
                                              if (curErr != null ||
                                                  newErr != null ||
                                                  confErr != null) {
                                                setD(() {});
                                                return;
                                              }

                                              setD(() => saving = true);
                                              try {
                                                final email = supabase
                                                    .auth
                                                    .currentUser
                                                    ?.email;
                                                if (email == null) {
                                                  throw const AuthException(
                                                    'No signed-in user.',
                                                  );
                                                }

                                                // Re-auth to verify current password
                                                await supabase.auth
                                                    .signInWithPassword(
                                                      email: email,
                                                      password: cur,
                                                    );

                                                // Update password
                                                await supabase.auth.updateUser(
                                                  UserAttributes(password: npw),
                                                );

                                                if (!mounted) return;
                                                Navigator.of(ctx).pop();
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Password updated successfully',
                                                    ),
                                                  ),
                                                );
                                              } on SocketException {
                                                setD(() {
                                                  genErr =
                                                      'Please check your internet connection and try again.';
                                                  saving = false;
                                                });
                                              } on AuthException catch (e) {
                                                final msg = e.message
                                                    .toLowerCase();
                                                setD(() {
                                                  if (msg.contains(
                                                        'invalid login',
                                                      ) ||
                                                      msg.contains('invalid') ||
                                                      msg.contains(
                                                        'credentials',
                                                      )) {
                                                    curErr =
                                                        'Current password is incorrect';
                                                  } else {
                                                    genErr = e.message;
                                                  }
                                                  saving = false;
                                                });
                                              } catch (e) {
                                                setD(() {
                                                  genErr =
                                                      'Something went wrong. Please try again.';
                                                  saving = false;
                                                });
                                              }
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: kAccent,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: saving
                                          ? const SizedBox(
                                              height: 22,
                                              width: 22,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2.5,
                                              ),
                                            )
                                          : const Text(
                                              'Save new password',
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
    try {
      final xFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 92,
      );
      if (xFile == null) return;
      final bytes = await xFile.readAsBytes();
      await _cropAndConfirm(
        bytes,
        originalFileName: 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Camera error: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Image selection failed: $e')));
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
            'full_name, mobile_number, address, sex, profile_url, birth_certificate_url, marriage_certificate_url',
          )
          .eq('id', currentUser.id)
          .maybeSingle();

      if (!mounted) return;
      if (response == null) {
        setState(() {
          fullName = '';
          mobileNumber = '';
          address = '';
          sex = '';
          profileUrl = null;
          isLoading = false;
        });
      } else {
        setState(() {
          fullName = (response['full_name'] as String?)?.trim() ?? '';
          mobileNumber = (response['mobile_number'] as String?)?.trim() ?? '';
          address = (response['address'] as String?)?.trim() ?? '';
          sex = (response['sex'] as String?)?.trim() ?? '';
          profileUrl = response['profile_url'] as String?;
          birthCertificateUrl = response['birth_certificate_url'] as String?;
          marriageCertificateUrl =
              response['marriage_certificate_url'] as String?;
          _fullNameController.text = fullName;
          _mobileController.text = mobileNumber;
          _addressController.text = address;
          _sexController.text = sex;
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load profile: $e')));
    }
  }

  String removeTitle(String name) {
    final titleRegex = RegExp(r'^(Mr\.|Mrs\.)\s', caseSensitive: false);
    return name.replaceAll(titleRegex, '').trim();
  }

  String _displayName() => removeTitle(fullName);

  String _initialOf(String? name) {
    final t = (name ?? '').trim();
    if (t.isEmpty) return 'M';
    return t.characters.first.toUpperCase();
  }

  Future<void> _uploadCroppedBytes(
    Uint8List bytes, {
    required String extension,
  }) async {
    setState(() => _uploadingImage = true);
    try {
      final userId = supabase.auth.currentUser!.id;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo updated')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload error: $e')));
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

  Future<void> _uploadCertificate({
    required String type, // 'birth' or 'marriage'
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null) return;

    final file = result.files.first;
    final bytes = file.bytes;
    final ext = file.extension ?? 'pdf';
    if (bytes == null) return;

    setState(() => _uploadingImage = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      final fileName = '$userId-${type}_certificate.${ext.toLowerCase()}';

      await supabase.storage
          .from('certificates')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl = supabase.storage
          .from('certificates')
          .getPublicUrl(fileName);

      final update = await supabase
          .from('users')
          .update({
            if (type == 'birth') 'birth_certificate_url': publicUrl,
            if (type == 'marriage') 'marriage_certificate_url': publicUrl,
          })
          .eq('id', userId)
          .select()
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        if (type == 'birth') birthCertificateUrl = publicUrl;
        if (type == 'marriage') marriageCertificateUrl = publicUrl;
        _uploadingImage = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${type[0].toUpperCase()}${type.substring(1)} certificate uploaded!',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload error: $e')));
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final userId = supabase.auth.currentUser!.id;
      final updated = {
        'full_name': _fullNameController.text.trim(),
        'mobile_number': _mobileController.text.trim(),
        'address': _addressController.text.trim(),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No profile found to update')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating profile: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await _showLogoutConfirmDialog();
    if (ok == true) {
      await Supabase.instance.client.auth.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('selectedDayungUnit');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Login()),
        (route) => false,
      );
    }
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
    final isWide = MediaQuery.of(context).size.width > 700;

    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kPrimary,
        elevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DayungSettingsPage()),
            ),
            icon: const Icon(Icons.settings, color: Colors.white),
          ),
        ],
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            GestureDetector(
                              onTap: _editing
                                  ? _chooseImageSource
                                  : _openProfilePreview,
                              child: Hero(
                                tag: 'profilePhotoHero',
                                child: CircleAvatar(
                                  radius: isWide ? 56 : 48,
                                  backgroundColor: const Color(0xFFE0E0E0),
                                  backgroundImage:
                                      (profileUrl != null &&
                                          profileUrl!.isNotEmpty)
                                      ? NetworkImage(profileUrl!)
                                      : null,
                                  child:
                                      (profileUrl == null ||
                                          profileUrl!.isEmpty)
                                      ? Text(
                                          _initialOf(fullName),
                                          style: TextStyle(
                                            fontSize: isWide ? 28 : 24,
                                            color: kPrimary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            if (_editing)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: InkWell(
                                  onTap: _chooseImageSource,
                                  borderRadius: BorderRadius.circular(24),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: kAccent,
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(8),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _displayName().isNotEmpty
                                    ? _displayName()
                                    : 'Your name',
                                style: TextStyle(
                                  fontSize: isWide ? 22 : 18,
                                  fontWeight: FontWeight.w700,
                                  color: kText,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                mobileNumber.isNotEmpty
                                    ? mobileNumber
                                    : 'Mobile not set',
                                style: const TextStyle(
                                  color: kSubText,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 44,
                                child: OutlinedButton.icon(
                                  icon: Icon(
                                    _editing ? Icons.close : Icons.edit,
                                    size: 20,
                                    color: kAccent,
                                  ),
                                  label: Text(
                                    _editing ? 'Cancel' : 'Edit Profile',
                                    style: const TextStyle(
                                      color: kAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: kAccent),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: () {
                                    if (_editing) {
                                      _fullNameController.text = fullName;
                                      _mobileController.text = mobileNumber;
                                      _addressController.text = address;
                                      _sexController.text = sex;
                                    }
                                    setState(() => _editing = !_editing);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _ProfileFieldCard(
                  icon: Icons.person,
                  label: 'Full Name',
                  value: _displayName(),
                  editingChild: TextFormField(
                    controller: _fullNameController,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Full name is required'
                        : null,
                    style: const TextStyle(fontSize: 16),
                    decoration: _fieldDecoration('Enter full name'),
                  ),
                ),
                _ProfileFieldCard(
                  icon: Icons.location_on,
                  label: 'Address',
                  value: address.isNotEmpty ? address : 'Not provided',
                  editingChild: TextFormField(
                    controller: _addressController,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 16),
                    decoration: _fieldDecoration('Enter address'),
                  ),
                ),
                _ProfileFieldCard(
                  icon: Icons.phone,
                  label: 'Mobile Number',
                  value: mobileNumber.isNotEmpty
                      ? mobileNumber
                      : 'Not provided',
                  editingChild: TextFormField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Mobile number is required';
                      if (t.length < 7) return 'Enter a valid number';
                      return null;
                    },
                    style: const TextStyle(fontSize: 16),
                    decoration: _fieldDecoration('Enter mobile number'),
                  ),
                ),
                _ProfileFieldCard(
                  icon: Icons.person_outline,
                  label: 'Sex',
                  value: sex.isNotEmpty ? sex : 'Not provided',
                  editingChild: DropdownButtonFormField<String>(
                    value: (_sexController.text.isNotEmpty
                        ? _sexController.text
                        : null),
                    items: const [
                      DropdownMenuItem(value: 'Male', child: Text('Male')),
                      DropdownMenuItem(value: 'Female', child: Text('Female')),
                      DropdownMenuItem(
                        value: 'Prefer not to say',
                        child: Text('Prefer not to say'),
                      ),
                    ],
                    onChanged: (val) => _sexController.text = val ?? '',
                    decoration: _fieldDecoration('Select sex'),
                  ),
                ),
                const SizedBox(height: 16),
                if (_editing) ...[
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.people),
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BeneficiaryPage(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      label: const Text(
                        'Beneficiaries',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.lock_reset),
                      onPressed: _openChangePasswordDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      label: const Text(
                        'Change Password',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.description, color: kPrimary),
                              const SizedBox(width: 10),
                              const Text(
                                'Certificates',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: kText,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _certificateRow(
                            label: 'Birth Certificate',
                            url: birthCertificateUrl,
                            onUpload: () => _uploadCertificate(type: 'birth'),
                            onView: () =>
                                _openCertificate(birthCertificateUrl ?? ''),
                          ),
                          const SizedBox(height: 10),
                          _certificateRow(
                            label: 'Marriage Certificate',
                            url: marriageCertificateUrl,
                            onUpload: () =>
                                _uploadCertificate(type: 'marriage'),
                            onView: () =>
                                _openCertificate(marriageCertificateUrl ?? ''),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.logout, color: kWarn),
                      onPressed: _confirmLogout,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kWarn),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      label: const Text(
                        'Logout',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: kWarn,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.home, color: kPrimary),
                    title: const Text(
                      'Manage Dayung',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'View current Dayung, apply or change',
                      style: TextStyle(color: kSubText),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DayungSettingsPage(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_uploadingImage)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Uploading photo...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileFieldCard extends StatelessWidget {
  const _ProfileFieldCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.editingChild,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget editingChild;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.of(context).textScaleFactor > 1.2;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: largeText ? 30 : 26, color: kPrimary),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: largeText ? 18 : 16,
                    fontWeight: FontWeight.w700,
                    color: kText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _isEditing(context)
                ? editingChild
                : Text(
                    value,
                    style: const TextStyle(color: kSubText, fontSize: 16),
                  ),
          ],
        ),
      ),
    );
  }

  bool _isEditing(BuildContext context) {
    final state = context.findAncestorStateOfType<_ProfilePageState>();
    return state?._editing ?? false;
  }
}

enum _PickSource { camera, gallery }
